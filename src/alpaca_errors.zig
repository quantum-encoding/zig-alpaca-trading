// Copyright (c) 2025 QUANTUM ENCODING LTD
// Author: Rich <rich@quantumencoding.io>
// Website: https://quantumencoding.io
// 
// Licensed under the MIT License. See LICENSE file for details.

const std = @import("std");

/// Production-grade error handling for Alpaca API operations
/// Complete error taxonomy matching all possible API failure modes

/// Network and transport errors
pub const NetworkError = error{
    ConnectionRefused,
    ConnectionTimeout,
    ConnectionReset,
    DnsResolutionFailed,
    SslHandshakeFailed,
    ProxyConnectionFailed,
    NetworkUnreachable,
    HostUnreachable,
};

/// Authentication and authorization errors
pub const AuthError = error{
    InvalidApiKey,
    InvalidSecretKey,
    ExpiredApiKey,
    InsufficientPermissions,
    AccountSuspended,
    IpNotWhitelisted,
    TwoFactorRequired,
    SessionExpired,
};

/// Trading and order errors
pub const TradingError = error{
    InsufficientFunds,
    InsufficientBuyingPower,
    OrderRejected,
    OrderNotFound,
    OrderAlreadyFilled,
    OrderAlreadyCanceled,
    InvalidOrderType,
    InvalidTimeInForce,
    InvalidSymbol,
    MarketClosed,
    TradingHalted,
    PatternDayTraderRestriction,
    MaxOrdersExceeded,
    MaxPositionsExceeded,
    DuplicateOrderId,
    InvalidQuantity,
    InvalidPrice,
    PriceOutOfRange,
    PositionNotFound,
    CannotClosePosition,
};

/// Market data errors
pub const MarketDataError = error{
    SubscriptionRequired,
    DataNotAvailable,
    InvalidTimeframe,
    InvalidDateRange,
    SymbolNotFound,
    ExchangeNotSupported,
    RateLimitExceeded,
    DataFeedDisconnected,
};

/// Account and compliance errors
pub const AccountError = error{
    AccountNotActive,
    AccountRestricted,
    AccountNotApproved,
    KycRequired,
    DocumentsRequired,
    AccountLocked,
    AccountClosed,
    ComplianceViolation,
    RegulatoryRestriction,
};

/// API and system errors
pub const SystemError = error{
    ApiMaintenance,
    ApiDeprecated,
    InvalidApiVersion,
    InvalidRequestFormat,
    InvalidJsonPayload,
    MissingRequiredField,
    InvalidFieldValue,
    RequestTooLarge,
    InternalServerError,
    ServiceUnavailable,
    GatewayTimeout,
};

/// Rate limiting errors with retry information
pub const RateLimitError = struct {
    retry_after_ms: u64,
    limit: u32,
    remaining: u32,
    reset_at: i64,
};

/// Comprehensive error response structure
pub const ErrorResponse = struct {
    code: u16,
    message: []const u8,
    details: ?ErrorDetails = null,
};

pub const ErrorDetails = struct {
    field: ?[]const u8 = null,
    issue: ?[]const u8 = null,
    suggestion: ?[]const u8 = null,
    documentation_url: ?[]const u8 = null,
};

/// Master error set combining all error types
pub const AlpacaError = NetworkError || AuthError || TradingError || 
                        MarketDataError || AccountError || SystemError;

/// Error context for detailed error reporting
pub const ErrorContext = struct {
    endpoint: []const u8,
    method: []const u8,
    status_code: u16,
    error_type: AlpacaError,
    message: []const u8,
    timestamp: i64,
    request_id: ?[]const u8 = null,
    rate_limit_info: ?RateLimitError = null,
    
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            "AlpacaError: {s} {s} failed with status {d}: {s} (type: {s})",
            .{ self.method, self.endpoint, self.status_code, self.message, @errorName(self.error_type) }
        );
        if (self.request_id) |id| {
            try writer.print(" [request_id: {s}]", .{id});
        }
    }
};

/// Map HTTP status codes to specific errors
pub fn mapStatusToError(status_code: u16, response_body: []const u8) AlpacaError {
    _ = response_body; // Will be parsed for specific error details in production
    
    return switch (status_code) {
        400 => error.InvalidRequestFormat,
        401 => error.InvalidApiKey,
        402 => error.SubscriptionRequired,
        403 => error.InsufficientPermissions,
        404 => error.OrderNotFound,
        409 => error.DuplicateOrderId,
        422 => error.InvalidFieldValue,
        429 => error.RateLimitExceeded,
        500 => error.InternalServerError,
        502 => error.ServiceUnavailable,
        503 => error.ApiMaintenance,
        504 => error.GatewayTimeout,
        else => error.InternalServerError,
    };
}

/// Extract rate limit information from response headers
pub fn extractRateLimitInfo(headers: []const std.http.Header) ?RateLimitError {
    var retry_after: ?u64 = null;
    var limit: ?u32 = null;
    var remaining: ?u32 = null;
    var reset_at: ?i64 = null;
    
    for (headers) |header| {
        if (std.mem.eql(u8, header.name, "X-RateLimit-Limit")) {
            limit = std.fmt.parseInt(u32, header.value, 10) catch null;
        } else if (std.mem.eql(u8, header.name, "X-RateLimit-Remaining")) {
            remaining = std.fmt.parseInt(u32, header.value, 10) catch null;
        } else if (std.mem.eql(u8, header.name, "X-RateLimit-Reset")) {
            reset_at = std.fmt.parseInt(i64, header.value, 10) catch null;
        } else if (std.mem.eql(u8, header.name, "Retry-After")) {
            retry_after = std.fmt.parseInt(u64, header.value, 10) catch null;
        }
    }
    
    if (retry_after != null and limit != null and remaining != null and reset_at != null) {
        return RateLimitError{
            .retry_after_ms = retry_after.? * 1000,
            .limit = limit.?,
            .remaining = remaining.?,
            .reset_at = reset_at.?,
        };
    }
    
    return null;
}

/// Determine if an error is retryable
pub fn isRetryable(err: AlpacaError) bool {
    return switch (err) {
        error.ConnectionTimeout,
        error.ConnectionReset,
        error.NetworkUnreachable,
        error.ServiceUnavailable,
        error.GatewayTimeout,
        error.RateLimitExceeded,
        error.ApiMaintenance,
        => true,
        else => false,
    };
}

/// Calculate exponential backoff delay
pub fn calculateBackoffMs(attempt: u32, base_delay_ms: u64) u64 {
    const max_delay_ms: u64 = 60000; // 1 minute max
    const jitter_factor = 0.1; // 10% jitter
    
    var delay = base_delay_ms * std.math.pow(u64, 2, attempt);
    if (delay > max_delay_ms) {
        delay = max_delay_ms;
    }
    
    // Add jitter to prevent thundering herd
    const jitter = @as(u64, @intFromFloat(@as(f64, @floatFromInt(delay)) * jitter_factor));
    return delay + (std.crypto.random.int(u64) % jitter);
}