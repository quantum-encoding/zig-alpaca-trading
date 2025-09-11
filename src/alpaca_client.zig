// Copyright (c) 2025 QUANTUM ENCODING LTD
// Author: Rich <rich@quantumencoding.io>
// Website: https://quantumencoding.io
// 
// Licensed under the MIT License. See LICENSE file for details.

const std = @import("std");
const http = std.http;
const types = @import("alpaca_types.zig");
const errors = @import("alpaca_errors.zig");

/// Alpaca Markets API client for Zig 0.16.0
/// Production-grade, enterprise-level client for algorithmic trading
/// Feature-complete implementation with comprehensive error handling
pub const AlpacaClient = struct {
    allocator: std.mem.Allocator,
    client: http.Client,
    api_key: []const u8,
    api_secret: []const u8,
    base_url: []const u8,
    data_url: []const u8,

    pub const Environment = enum {
        paper,
        live,

        pub fn getBaseUrl(self: Environment) []const u8 {
            return switch (self) {
                .paper => "https://paper-api.alpaca.markets",
                .live => "https://api.alpaca.markets",
            };
        }

        pub fn getDataUrl(self: Environment) []const u8 {
            return "https://data.alpaca.markets";
        }
    };

    /// Initialize Alpaca client with API credentials
    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        api_secret: []const u8,
        environment: Environment,
    ) AlpacaClient {
        return .{
            .allocator = allocator,
            .client = http.Client{ .allocator = allocator },
            .api_key = api_key,
            .api_secret = api_secret,
            .base_url = environment.getBaseUrl(),
            .data_url = environment.getDataUrl(),
        };
    }

    pub fn deinit(self: *AlpacaClient) void {
        self.client.deinit();
    }

    pub const Response = struct {
        status: http.Status,
        body: []u8,
        headers: []http.Header,
        allocator: std.mem.Allocator,
        request_id: ?[]const u8 = null,
        rate_limit_info: ?errors.RateLimitError = null,

        pub fn deinit(self: *Response) void {
            self.allocator.free(self.body);
            self.allocator.free(self.headers);
            if (self.request_id) |id| self.allocator.free(id);
        }

        /// Parse response as JSON with full error handling
        pub fn json(self: Response, comptime T: type) !std.json.Parsed(T) {
            if (self.status != .ok) {
                const err = errors.mapStatusToError(@intFromEnum(self.status), self.body);
                return err;
            }
            
            return std.json.parseFromSlice(T, self.allocator, self.body, .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            }) catch |err| {
                std.debug.print("JSON parse error for type {s}: {s}\n", .{@typeName(T), self.body});
                return err;
            };
        }

        /// Check if response indicates success
        pub fn isSuccess(self: Response) bool {
            const code = @intFromEnum(self.status);
            return code >= 200 and code < 300;
        }

        /// Get error context for failed requests
        pub fn getErrorContext(self: Response, endpoint: []const u8, method: []const u8) errors.ErrorContext {
            return errors.ErrorContext{
                .endpoint = endpoint,
                .method = @tagName(method),
                .status_code = @intFromEnum(self.status),
                .error_type = errors.mapStatusToError(@intFromEnum(self.status), self.body),
                .message = self.body,
                .timestamp = std.time.milliTimestamp(),
                .request_id = self.request_id,
                .rate_limit_info = self.rate_limit_info,
            };
        }
    };

    // Re-export production-grade type definitions
    pub const Account = types.Account;
    pub const Position = types.Position;
    pub const Order = types.Order;
    pub const Asset = types.Asset;
    pub const Clock = types.Clock;
    pub const Calendar = types.Calendar;
    pub const Bar = types.Bar;
    pub const Quote = types.Quote;
    pub const Trade = types.Trade;
    pub const OrderSide = types.OrderSide;
    pub const OrderType = types.OrderType;
    pub const TimeInForce = types.TimeInForce;
    pub const OrderStatus = types.OrderStatus;
    pub const OrderClass = types.OrderClass;
    pub const Activity = types.Activity;
    pub const PortfolioHistory = types.PortfolioHistory;
    
    // Legacy structures (kept for compatibility)
    pub const Account = struct {
        id: []const u8,
        account_number: []const u8,
        status: []const u8,
        currency: []const u8,
        buying_power: []const u8,
        portfolio_value: []const u8,
        cash: []const u8,
        pattern_day_trader: bool,
        trading_blocked: bool,
        transfers_blocked: bool,
        account_blocked: bool,
        trade_suspended_by_user: bool,
        daytrade_count: i32,
        daytrading_buying_power: []const u8,
    };

    pub const Position = struct {
        asset_id: []const u8,
        symbol: []const u8,
        exchange: []const u8,
        asset_class: []const u8,
        qty: []const u8,
        qty_available: []const u8,
        avg_entry_price: []const u8,
        side: []const u8,
        market_value: []const u8,
        cost_basis: []const u8,
        unrealized_pl: []const u8,
        unrealized_plpc: []const u8,
        unrealized_intraday_pl: []const u8,
        unrealized_intraday_plpc: []const u8,
        current_price: []const u8,
        lastday_price: []const u8,
        change_today: []const u8,
    };

    pub const Order = struct {
        id: []const u8,
        client_order_id: []const u8,
        created_at: []const u8,
        updated_at: []const u8,
        submitted_at: []const u8,
        filled_at: ?[]const u8,
        expired_at: ?[]const u8,
        canceled_at: ?[]const u8,
        failed_at: ?[]const u8,
        asset_id: []const u8,
        symbol: []const u8,
        asset_class: []const u8,
        notional: ?[]const u8,
        qty: ?[]const u8,
        filled_qty: []const u8,
        type: []const u8,
        side: []const u8,
        time_in_force: []const u8,
        limit_price: ?[]const u8,
        stop_price: ?[]const u8,
        filled_avg_price: ?[]const u8,
        status: []const u8,
        extended_hours: bool,
        legs: ?[]Order,
    };

    pub const OrderRequest = struct {
        symbol: []const u8,
        qty: ?f64 = null,
        notional: ?f64 = null,
        side: []const u8,
        type: []const u8,
        time_in_force: []const u8,
        limit_price: ?f64 = null,
        stop_price: ?f64 = null,
        extended_hours: ?bool = null,
        client_order_id: ?[]const u8 = null,
        order_class: ?[]const u8 = null,
        take_profit: ?struct {
            limit_price: f64,
        } = null,
        stop_loss: ?struct {
            stop_price: f64,
            limit_price: ?f64 = null,
        } = null,
    };

    fn makeAuthHeaders(self: *AlpacaClient) ![2]http.Header {
        return [2]http.Header{
            .{ .name = "APCA-API-KEY-ID", .value = self.api_key },
            .{ .name = "APCA-API-SECRET-KEY", .value = self.api_secret },
        };
    }

    fn request(
        self: *AlpacaClient,
        method: http.Method,
        endpoint: []const u8,
        body: ?[]const u8,
        use_data_url: bool,
    ) !Response {
        const base = if (use_data_url) self.data_url else self.base_url;
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base, endpoint });
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);
        
        const auth_headers = try self.makeAuthHeaders();
        var headers = std.ArrayList(http.Header).init(self.allocator);
        defer headers.deinit();
        
        try headers.appendSlice(&auth_headers);
        if (body != null) {
            try headers.append(.{ .name = "Content-Type", .value = "application/json" });
        }

        var req = try self.client.request(method, uri, .{
            .extra_headers = headers.items,
        });
        defer req.deinit();

        if (body) |b| {
            req.transfer_encoding = .{ .content_length = b.len };
            var body_writer = try req.sendBodyUnflushed(&.{});
            try body_writer.writer.writeAll(b);
            try body_writer.end();
            try req.connection.?.flush();
        } else {
            try req.sendBodiless();
        }

        var response = try req.receiveHead(&.{});

        var transfer_buffer: [8192]u8 = undefined;
        const response_reader = response.reader(&transfer_buffer);
        
        const body_data = try response_reader.allocRemaining(
            self.allocator,
            std.Io.Limit.limited(10 * 1024 * 1024)
        );
        defer self.allocator.free(body_data);

        const body_slice = try self.allocator.dupe(u8, body_data);
        
        // Extract headers for rate limit info
        const headers_copy = try self.allocator.alloc(http.Header, response.head.headers.list.items.len);
        for (response.head.headers.list.items, 0..) |header, i| {
            headers_copy[i] = header;
        }
        
        // Extract request ID if present
        var request_id: ?[]const u8 = null;
        for (headers_copy) |header| {
            if (std.mem.eql(u8, header.name, "X-Request-Id")) {
                request_id = try self.allocator.dupe(u8, header.value);
                break;
            }
        }
        
        // Extract rate limit information
        const rate_limit_info = errors.extractRateLimitInfo(headers_copy);

        return Response{
            .status = response.head.status,
            .body = body_slice,
            .headers = headers_copy,
            .allocator = self.allocator,
            .request_id = request_id,
            .rate_limit_info = rate_limit_info,
        };
    }

    // Account endpoints
    pub fn getAccount(self: *AlpacaClient) !Response {
        return self.request(.GET, "/v2/account", null, false);
    }

    // Positions endpoints
    pub fn getPositions(self: *AlpacaClient) !Response {
        return self.request(.GET, "/v2/positions", null, false);
    }

    pub fn getPosition(self: *AlpacaClient, symbol: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/positions/{s}", .{symbol});
        defer self.allocator.free(endpoint);
        return self.request(.GET, endpoint, null, false);
    }

    pub fn closePosition(self: *AlpacaClient, symbol: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/positions/{s}", .{symbol});
        defer self.allocator.free(endpoint);
        return self.request(.DELETE, endpoint, null, false);
    }

    pub fn closeAllPositions(self: *AlpacaClient) !Response {
        return self.request(.DELETE, "/v2/positions", null, false);
    }

    // Orders endpoints
    pub fn getOrders(self: *AlpacaClient) !Response {
        return self.request(.GET, "/v2/orders", null, false);
    }

    pub fn getOrder(self: *AlpacaClient, order_id: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/orders/{s}", .{order_id});
        defer self.allocator.free(endpoint);
        return self.request(.GET, endpoint, null, false);
    }

    pub fn submitOrder(self: *AlpacaClient, order: OrderRequest) !Response {
        const json_str = try std.json.stringifyAlloc(self.allocator, order, .{});
        defer self.allocator.free(json_str);
        return self.request(.POST, "/v2/orders", json_str, false);
    }

    pub fn cancelOrder(self: *AlpacaClient, order_id: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/orders/{s}", .{order_id});
        defer self.allocator.free(endpoint);
        return self.request(.DELETE, endpoint, null, false);
    }

    pub fn cancelAllOrders(self: *AlpacaClient) !Response {
        return self.request(.DELETE, "/v2/orders", null, false);
    }

    // Market data endpoints
    pub fn getLatestQuote(self: *AlpacaClient, symbol: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/stocks/{s}/quotes/latest", .{symbol});
        defer self.allocator.free(endpoint);
        return self.request(.GET, endpoint, null, true);
    }

    pub fn getLatestTrade(self: *AlpacaClient, symbol: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/stocks/{s}/trades/latest", .{symbol});
        defer self.allocator.free(endpoint);
        return self.request(.GET, endpoint, null, true);
    }

    pub fn getBars(
        self: *AlpacaClient,
        symbol: []const u8,
        timeframe: []const u8,
        start: ?[]const u8,
        end: ?[]const u8,
        limit: ?u32,
    ) !Response {
        var query = std.ArrayList(u8).init(self.allocator);
        defer query.deinit();
        
        try query.appendSlice("/v2/stocks/");
        try query.appendSlice(symbol);
        try query.appendSlice("/bars?timeframe=");
        try query.appendSlice(timeframe);
        
        if (start) |s| {
            try query.appendSlice("&start=");
            try query.appendSlice(s);
        }
        if (end) |e| {
            try query.appendSlice("&end=");
            try query.appendSlice(e);
        }
        if (limit) |l| {
            try query.writer().print("&limit={d}", .{l});
        }
        
        return self.request(.GET, query.items, null, true);
    }

    // Portfolio history
    pub fn getPortfolioHistory(
        self: *AlpacaClient,
        period: ?[]const u8,
        timeframe: ?[]const u8,
    ) !Response {
        var query = std.ArrayList(u8).init(self.allocator);
        defer query.deinit();
        
        try query.appendSlice("/v2/account/portfolio/history");
        
        var first = true;
        if (period) |p| {
            try query.appendSlice("?period=");
            try query.appendSlice(p);
            first = false;
        }
        if (timeframe) |t| {
            try query.appendSlice(if (first) "?" else "&");
            try query.appendSlice("timeframe=");
            try query.appendSlice(t);
        }
        
        return self.request(.GET, query.items, null, false);
    }

    // Clock
    pub fn getClock(self: *AlpacaClient) !Response {
        return self.request(.GET, "/v2/clock", null, false);
    }

    // Calendar
    pub fn getCalendar(self: *AlpacaClient) !Response {
        return self.request(.GET, "/v2/calendar", null, false);
    }
};