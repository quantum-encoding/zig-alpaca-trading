// Copyright (c) 2025 QUANTUM ENCODING LTD
// Thread-Safe Alpaca Client - Client-Per-Thread Pattern
//
// CRITICAL: std.http.Client is NOT thread-safe for requests
// Solution: Each thread gets its own complete client instance

const std = @import("std");
const http = std.http;
const types = @import("alpaca_types.zig");
const errors = @import("alpaca_errors.zig");

/// Thread-safe Alpaca client using Client-Per-Thread pattern
/// Each thread/worker must create its own instance
/// Never share instances across threads!
pub const ThreadSafeAlpacaClient = struct {
    allocator: std.mem.Allocator,
    client: http.Client,
    api_key: []const u8,
    api_secret: []const u8,
    base_url: []const u8,
    data_url: []const u8,
    thread_id: []const u8,
    request_count: std.atomic.Value(u64),

    pub const Environment = enum {
        paper,
        live,

        pub fn getBaseUrl(self: Environment) []const u8 {
            return switch (self) {
                .paper => "https://paper-api.alpaca.markets",
                .live => "https://api.alpaca.markets",
            };
        }

        pub fn getDataUrl(_: Environment) []const u8 {
            return "https://data.alpaca.markets";
        }
    };

    /// Initialize a thread-local Alpaca client
    /// IMPORTANT: Each thread must call this to get its own client
    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        api_secret: []const u8,
        environment: Environment,
        thread_id: []const u8,
    ) !ThreadSafeAlpacaClient {
        const key_copy = try allocator.dupe(u8, api_key);
        errdefer allocator.free(key_copy);

        const secret_copy = try allocator.dupe(u8, api_secret);
        errdefer allocator.free(secret_copy);

        const thread_id_copy = try allocator.dupe(u8, thread_id);
        errdefer allocator.free(thread_id_copy);

        std.log.info("[{s}] Initializing thread-local Alpaca client", .{thread_id});

        return .{
            .allocator = allocator,
            .client = http.Client{ .allocator = allocator },
            .api_key = key_copy,
            .api_secret = secret_copy,
            .base_url = environment.getBaseUrl(),
            .data_url = environment.getDataUrl(),
            .thread_id = thread_id_copy,
            .request_count = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *ThreadSafeAlpacaClient) void {
        const total_requests = self.request_count.load(.acquire);
        std.log.info("[{s}] Shutting down client after {d} requests", .{
            self.thread_id,
            total_requests,
        });

        self.client.deinit();
        self.allocator.free(self.api_key);
        self.allocator.free(self.api_secret);
        self.allocator.free(self.thread_id);
    }

    pub const Response = struct {
        status: http.Status,
        body: []u8,
        allocator: std.mem.Allocator,
        request_id: u64,
        thread_id: []const u8,

        pub fn deinit(self: *Response) void {
            self.allocator.free(self.body);
        }

        pub fn json(self: Response, comptime T: type) !std.json.Parsed(T) {
            if (self.status != .ok) {
                std.log.err("[{s}] Request #{d} failed with status {}", .{
                    self.thread_id,
                    self.request_id,
                    self.status,
                });
                return error.RequestFailed;
            }

            return std.json.parseFromSlice(T, self.allocator, self.body, .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            });
        }

        pub fn isSuccess(self: Response) bool {
            const code = @intFromEnum(self.status);
            return code >= 200 and code < 300;
        }
    };

    // Re-export types
    pub const Account = types.Account;
    pub const Position = types.Position;
    pub const Order = types.Order;
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
    };

    fn makeAuthHeaders(self: *ThreadSafeAlpacaClient) ![2]http.Header {
        return [2]http.Header{
            .{ .name = "APCA-API-KEY-ID", .value = self.api_key },
            .{ .name = "APCA-API-SECRET-KEY", .value = self.api_secret },
        };
    }

    fn request(
        self: *ThreadSafeAlpacaClient,
        method: http.Method,
        endpoint: []const u8,
        body: ?[]const u8,
        use_data_url: bool,
    ) !Response {
        const request_id = self.request_count.fetchAdd(1, .monotonic);

        std.log.debug("[{s}] Request #{d}: {} {s}", .{
            self.thread_id,
            request_id,
            method,
            endpoint,
        });

        const base = if (use_data_url) self.data_url else self.base_url;
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base, endpoint });
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);

        const auth_headers = try self.makeAuthHeaders();
        var headers = std.ArrayList(http.Header).empty;
        defer headers.deinit(self.allocator);

        try headers.appendSlice(self.allocator, &auth_headers);
        if (body != null) {
            try headers.append(self.allocator, .{ .name = "Content-Type", .value = "application/json" });
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

        return Response{
            .status = response.head.status,
            .body = body_slice,
            .allocator = self.allocator,
            .request_id = request_id,
            .thread_id = self.thread_id,
        };
    }

    // Account endpoints
    pub fn getAccount(self: *ThreadSafeAlpacaClient) !Response {
        return self.request(.GET, "/v2/account", null, false);
    }

    // Position endpoints
    pub fn getPositions(self: *ThreadSafeAlpacaClient) !Response {
        return self.request(.GET, "/v2/positions", null, false);
    }

    pub fn getPosition(self: *ThreadSafeAlpacaClient, symbol: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/positions/{s}", .{symbol});
        defer self.allocator.free(endpoint);
        return self.request(.GET, endpoint, null, false);
    }

    pub fn closePosition(self: *ThreadSafeAlpacaClient, symbol: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/positions/{s}", .{symbol});
        defer self.allocator.free(endpoint);
        return self.request(.DELETE, endpoint, null, false);
    }

    pub fn closeAllPositions(self: *ThreadSafeAlpacaClient) !Response {
        return self.request(.DELETE, "/v2/positions", null, false);
    }

    // Order endpoints
    pub fn getOrders(self: *ThreadSafeAlpacaClient, status: ?[]const u8) !Response {
        const endpoint = if (status) |s|
            try std.fmt.allocPrint(self.allocator, "/v2/orders?status={s}", .{s})
        else
            "/v2/orders";
        defer if (status != null) self.allocator.free(endpoint);
        return self.request(.GET, endpoint, null, false);
    }

    pub fn getOrder(self: *ThreadSafeAlpacaClient, order_id: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/orders/{s}", .{order_id});
        defer self.allocator.free(endpoint);
        return self.request(.GET, endpoint, null, false);
    }

    pub fn createOrder(self: *ThreadSafeAlpacaClient, order: OrderRequest) !Response {
        const json_body = try std.json.stringifyAlloc(self.allocator, order, .{});
        defer self.allocator.free(json_body);

        std.log.info("[{s}] Placing order for {s}", .{ self.thread_id, order.symbol });

        return self.request(.POST, "/v2/orders", json_body, false);
    }

    pub fn cancelOrder(self: *ThreadSafeAlpacaClient, order_id: []const u8) !Response {
        const endpoint = try std.fmt.allocPrint(self.allocator, "/v2/orders/{s}", .{order_id});
        defer self.allocator.free(endpoint);

        std.log.info("[{s}] Canceling order {s}", .{ self.thread_id, order_id });

        return self.request(.DELETE, endpoint, null, false);
    }

    pub fn cancelAllOrders(self: *ThreadSafeAlpacaClient) !Response {
        std.log.warn("[{s}] Canceling ALL orders", .{self.thread_id});
        return self.request(.DELETE, "/v2/orders", null, false);
    }
};

/// Client pool for managing multiple thread-local clients
pub const AlpacaClientPool = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    api_secret: []const u8,
    environment: ThreadSafeAlpacaClient.Environment,

    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        api_secret: []const u8,
        environment: ThreadSafeAlpacaClient.Environment,
    ) !AlpacaClientPool {
        return .{
            .allocator = allocator,
            .api_key = try allocator.dupe(u8, api_key),
            .api_secret = try allocator.dupe(u8, api_secret),
            .environment = environment,
        };
    }

    pub fn deinit(self: *AlpacaClientPool) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.api_secret);
    }

    /// Create a new thread-local client
    /// Each thread should call this once and own the client
    pub fn createClient(self: *AlpacaClientPool, thread_id: []const u8) !*ThreadSafeAlpacaClient {
        const client = try self.allocator.create(ThreadSafeAlpacaClient);
        client.* = try ThreadSafeAlpacaClient.init(
            self.allocator,
            self.api_key,
            self.api_secret,
            self.environment,
            thread_id,
        );
        return client;
    }

    pub fn destroyClient(self: *AlpacaClientPool, client: *ThreadSafeAlpacaClient) void {
        client.deinit();
        self.allocator.destroy(client);
    }
};