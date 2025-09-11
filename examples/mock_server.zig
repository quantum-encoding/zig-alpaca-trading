// Copyright (c) 2025 QUANTUM ENCODING LTD
// Author: Rich <rich@quantumencoding.io>
// Website: https://quantumencoding.io
// 
// Licensed under the MIT License. See LICENSE file for details.

const std = @import("std");
const http = std.http;

/// Production-grade mock server for Alpaca API testing
/// Provides realistic responses for all endpoints with proper error simulation

const MockServer = struct {
    allocator: std.mem.Allocator,
    server: http.Server,
    port: u16,
    accounts: std.StringHashMap(AccountData),
    orders: std.StringHashMap(OrderData),
    positions: std.StringHashMap(PositionData),
    rate_limiter: RateLimiter,
    market_hours: MarketHours,
    
    const AccountData = struct {
        api_key: []const u8,
        secret_key: []const u8,
        account_json: []const u8,
        buying_power: f64,
        portfolio_value: f64,
        cash: f64,
        pattern_day_trader: bool,
    };
    
    const OrderData = struct {
        id: []const u8,
        status: []const u8,
        json: []const u8,
    };
    
    const PositionData = struct {
        symbol: []const u8,
        qty: f64,
        json: []const u8,
    };
    
    const RateLimiter = struct {
        requests: std.ArrayList(i64),
        limit: u32 = 200,
        window_ms: u64 = 60000,
        
        fn checkLimit(self: *RateLimiter) bool {
            const now = std.time.milliTimestamp();
            const cutoff = now - @as(i64, @intCast(self.window_ms));
            
            // Remove old requests
            var i: usize = 0;
            while (i < self.requests.items.len) {
                if (self.requests.items[i] < cutoff) {
                    _ = self.requests.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
            
            if (self.requests.items.len >= self.limit) {
                return false;
            }
            
            self.requests.append(now) catch return false;
            return true;
        }
    };
    
    const MarketHours = struct {
        is_open: bool = true,
        next_open: []const u8 = "2024-01-15T14:30:00Z",
        next_close: []const u8 = "2024-01-15T21:00:00Z",
    };
    
    pub fn init(allocator: std.mem.Allocator, port: u16) !MockServer {
        var server = http.Server.init(allocator, .{
            .reuse_address = true,
            .reuse_port = true,
        });
        
        const address = try std.net.Address.parseIp("127.0.0.1", port);
        try server.listen(address);
        
        var accounts = std.StringHashMap(AccountData).init(allocator);
        var orders = std.StringHashMap(OrderData).init(allocator);
        var positions = std.StringHashMap(PositionData).init(allocator);
        
        // Add default test account
        try accounts.put("TEST_API_KEY", AccountData{
            .api_key = "TEST_API_KEY",
            .secret_key = "TEST_SECRET_KEY",
            .account_json = 
                \\{
                \\  "id": "904837e3-3b76-47ec-b432-046db621571b",
                \\  "account_number": "TEST000001",
                \\  "status": "ACTIVE",
                \\  "currency": "USD",
                \\  "buying_power": "100000.00",
                \\  "regt_buying_power": "100000.00",
                \\  "daytrading_buying_power": "400000.00",
                \\  "effective_buying_power": "100000.00",
                \\  "non_marginable_buying_power": "50000.00",
                \\  "bod_dtbp": "400000.00",
                \\  "cash": "100000.00",
                \\  "accrued_fees": "0.00",
                \\  "portfolio_value": "100000.00",
                \\  "pattern_day_trader": false,
                \\  "trading_blocked": false,
                \\  "transfers_blocked": false,
                \\  "account_blocked": false,
                \\  "created_at": "2024-01-01T00:00:00Z",
                \\  "trade_suspended_by_user": false,
                \\  "multiplier": "4",
                \\  "shorting_enabled": true,
                \\  "equity": "100000.00",
                \\  "last_equity": "100000.00",
                \\  "long_market_value": "0.00",
                \\  "short_market_value": "0.00",
                \\  "position_market_value": "0.00",
                \\  "initial_margin": "0.00",
                \\  "maintenance_margin": "0.00",
                \\  "last_maintenance_margin": "0.00",
                \\  "sma": "100000.00",
                \\  "daytrade_count": 0
                \\}
            ,
            .buying_power = 100000.00,
            .portfolio_value = 100000.00,
            .cash = 100000.00,
            .pattern_day_trader = false,
        });
        
        return MockServer{
            .allocator = allocator,
            .server = server,
            .port = port,
            .accounts = accounts,
            .orders = orders,
            .positions = positions,
            .rate_limiter = RateLimiter{
                .requests = std.ArrayList(i64).init(allocator),
            },
            .market_hours = MarketHours{},
        };
    }
    
    pub fn deinit(self: *MockServer) void {
        self.server.deinit();
        self.accounts.deinit();
        self.orders.deinit();
        self.positions.deinit();
        self.rate_limiter.requests.deinit();
    }
    
    pub fn run(self: *MockServer) !void {
        std.debug.print("Mock Alpaca server running on port {d}\n", .{self.port});
        
        while (true) {
            var response = try self.server.accept(.{
                .allocator = self.allocator,
            });
            defer response.deinit();
            
            try self.handleRequest(&response);
        }
    }
    
    fn handleRequest(self: *MockServer, response: *http.Server.Response) !void {
        // Read request headers
        try response.wait();
        
        // Check authentication
        const api_key = self.getHeader(response.request.headers, "APCA-API-KEY-ID");
        const secret_key = self.getHeader(response.request.headers, "APCA-API-SECRET-KEY");
        
        if (api_key == null or secret_key == null) {
            try self.sendError(response, 401, "Unauthorized", "Missing API credentials");
            return;
        }
        
        // Check rate limit
        if (!self.rate_limiter.checkLimit()) {
            try self.sendRateLimitError(response);
            return;
        }
        
        // Route request
        const target = response.request.target;
        const method = response.request.method;
        
        if (std.mem.startsWith(u8, target, "/v2/account")) {
            try self.handleAccountEndpoint(response, method, target, api_key.?);
        } else if (std.mem.startsWith(u8, target, "/v2/orders")) {
            try self.handleOrdersEndpoint(response, method, target, api_key.?);
        } else if (std.mem.startsWith(u8, target, "/v2/positions")) {
            try self.handlePositionsEndpoint(response, method, target, api_key.?);
        } else if (std.mem.startsWith(u8, target, "/v2/clock")) {
            try self.handleClockEndpoint(response);
        } else if (std.mem.startsWith(u8, target, "/v2/calendar")) {
            try self.handleCalendarEndpoint(response);
        } else if (std.mem.startsWith(u8, target, "/v2/stocks")) {
            try self.handleMarketDataEndpoint(response, method, target);
        } else {
            try self.sendError(response, 404, "Not Found", "Endpoint not found");
        }
    }
    
    fn handleAccountEndpoint(
        self: *MockServer,
        response: *http.Server.Response,
        method: http.Method,
        target: []const u8,
        api_key: []const u8,
    ) !void {
        _ = target;
        
        if (method != .GET) {
            try self.sendError(response, 405, "Method Not Allowed", "Only GET allowed");
            return;
        }
        
        if (self.accounts.get(api_key)) |account| {
            response.status = .ok;
            response.transfer_encoding = .{ .content_length = account.account_json.len };
            try response.headers.append("content-type", "application/json");
            try response.do();
            try response.writeAll(account.account_json);
            try response.finish();
        } else {
            try self.sendError(response, 401, "Unauthorized", "Invalid API key");
        }
    }
    
    fn handleOrdersEndpoint(
        self: *MockServer,
        response: *http.Server.Response,
        method: http.Method,
        target: []const u8,
        api_key: []const u8,
    ) !void {
        _ = api_key;
        
        switch (method) {
            .GET => {
                // Return list of orders or specific order
                if (std.mem.indexOf(u8, target, "/v2/orders/")) |_| {
                    // Specific order
                    const order_json = 
                        \\{
                        \\  "id": "61e69015-8549-4bfd-b9c3-01e75843f47d",
                        \\  "client_order_id": "eb9e2aaa-f71a-4f51-b5b4-52a6c565dad4",
                        \\  "created_at": "2024-01-15T10:00:00Z",
                        \\  "updated_at": "2024-01-15T10:00:00Z",
                        \\  "submitted_at": "2024-01-15T10:00:00Z",
                        \\  "filled_at": null,
                        \\  "expired_at": null,
                        \\  "canceled_at": null,
                        \\  "failed_at": null,
                        \\  "replaced_at": null,
                        \\  "replaced_by": null,
                        \\  "replaces": null,
                        \\  "asset_id": "904837e3-3b76-47ec-b432-046db621571b",
                        \\  "symbol": "AAPL",
                        \\  "asset_class": "us_equity",
                        \\  "notional": null,
                        \\  "qty": "10",
                        \\  "filled_qty": "0",
                        \\  "filled_avg_price": null,
                        \\  "order_class": "simple",
                        \\  "order_type": "limit",
                        \\  "type": "limit",
                        \\  "side": "buy",
                        \\  "time_in_force": "day",
                        \\  "limit_price": "150.00",
                        \\  "stop_price": null,
                        \\  "status": "new",
                        \\  "extended_hours": false,
                        \\  "legs": null
                        \\}
                    ;
                    try self.sendJson(response, order_json);
                } else {
                    // List of orders
                    try self.sendJson(response, "[]");
                }
            },
            .POST => {
                // Create new order
                const body = try response.reader().readAllAlloc(self.allocator, 1024 * 1024);
                defer self.allocator.free(body);
                
                // Validate order request
                if (!self.market_hours.is_open) {
                    try self.sendError(response, 422, "Unprocessable Entity", "Market is closed");
                    return;
                }
                
                // Return created order
                const order_response = 
                    \\{
                    \\  "id": "61e69015-8549-4bfd-b9c3-01e75843f47d",
                    \\  "client_order_id": "eb9e2aaa-f71a-4f51-b5b4-52a6c565dad4",
                    \\  "created_at": "2024-01-15T10:00:00Z",
                    \\  "updated_at": "2024-01-15T10:00:00Z",
                    \\  "submitted_at": "2024-01-15T10:00:00Z",
                    \\  "filled_at": null,
                    \\  "expired_at": null,
                    \\  "canceled_at": null,
                    \\  "failed_at": null,
                    \\  "asset_id": "904837e3-3b76-47ec-b432-046db621571b",
                    \\  "symbol": "AAPL",
                    \\  "asset_class": "us_equity",
                    \\  "qty": "10",
                    \\  "filled_qty": "0",
                    \\  "order_class": "simple",
                    \\  "order_type": "limit",
                    \\  "type": "limit",
                    \\  "side": "buy",
                    \\  "time_in_force": "day",
                    \\  "limit_price": "150.00",
                    \\  "status": "accepted",
                    \\  "extended_hours": false
                    \\}
                ;
                try self.sendJson(response, order_response);
            },
            .DELETE => {
                // Cancel order
                try self.sendJson(response, "{}");
            },
            else => {
                try self.sendError(response, 405, "Method Not Allowed", "Method not supported");
            },
        }
    }
    
    fn handlePositionsEndpoint(
        self: *MockServer,
        response: *http.Server.Response,
        method: http.Method,
        target: []const u8,
        api_key: []const u8,
    ) !void {
        _ = self;
        _ = target;
        _ = api_key;
        
        if (method == .GET) {
            // Return empty positions for now
            try self.sendJson(response, "[]");
        } else if (method == .DELETE) {
            // Close position
            try self.sendJson(response, "{}");
        } else {
            try self.sendError(response, 405, "Method Not Allowed", "Method not supported");
        }
    }
    
    fn handleClockEndpoint(self: *MockServer, response: *http.Server.Response) !void {
        const clock_json = std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "timestamp": "{s}",
            \\  "is_open": {s},
            \\  "next_open": "{s}",
            \\  "next_close": "{s}"
            \\}}
        , .{
            "2024-01-15T15:30:00Z",
            if (self.market_hours.is_open) "true" else "false",
            self.market_hours.next_open,
            self.market_hours.next_close,
        }) catch return error.OutOfMemory;
        defer self.allocator.free(clock_json);
        
        try self.sendJson(response, clock_json);
    }
    
    fn handleCalendarEndpoint(self: *MockServer, response: *http.Server.Response) !void {
        const calendar_json = 
            \\[
            \\  {
            \\    "date": "2024-01-15",
            \\    "open": "09:30",
            \\    "close": "16:00"
            \\  },
            \\  {
            \\    "date": "2024-01-16",
            \\    "open": "09:30",
            \\    "close": "16:00"
            \\  }
            \\]
        ;
        try self.sendJson(response, calendar_json);
    }
    
    fn handleMarketDataEndpoint(
        self: *MockServer,
        response: *http.Server.Response,
        method: http.Method,
        target: []const u8,
    ) !void {
        _ = method;
        
        if (std.mem.indexOf(u8, target, "/quotes/latest")) |_| {
            const quote_json = 
                \\{
                \\  "symbol": "AAPL",
                \\  "quote": {
                \\    "t": "2024-01-15T15:30:00Z",
                \\    "ax": "Q",
                \\    "ap": 150.25,
                \\    "as": 100,
                \\    "bx": "Q",
                \\    "bp": 150.20,
                \\    "bs": 100,
                \\    "c": ["R"],
                \\    "z": "C"
                \\  }
                \\}
            ;
            try self.sendJson(response, quote_json);
        } else if (std.mem.indexOf(u8, target, "/trades/latest")) |_| {
            const trade_json = 
                \\{
                \\  "symbol": "AAPL",
                \\  "trade": {
                \\    "t": "2024-01-15T15:30:00Z",
                \\    "x": "Q",
                \\    "p": 150.23,
                \\    "s": 100,
                \\    "c": ["@"],
                \\    "i": 52983525029461,
                \\    "z": "C"
                \\  }
                \\}
            ;
            try self.sendJson(response, trade_json);
        } else if (std.mem.indexOf(u8, target, "/bars")) |_| {
            const bars_json = 
                \\{
                \\  "bars": [
                \\    {
                \\      "t": "2024-01-15T14:30:00Z",
                \\      "o": 149.50,
                \\      "h": 150.75,
                \\      "l": 149.25,
                \\      "c": 150.23,
                \\      "v": 1000000,
                \\      "n": 5000,
                \\      "vw": 150.00
                \\    }
                \\  ],
                \\  "symbol": "AAPL",
                \\  "next_page_token": null
                \\}
            ;
            try self.sendJson(response, bars_json);
        } else {
            try self.sendError(response, 404, "Not Found", "Market data endpoint not found");
        }
    }
    
    fn sendJson(self: *MockServer, response: *http.Server.Response, json: []const u8) !void {
        _ = self;
        response.status = .ok;
        response.transfer_encoding = .{ .content_length = json.len };
        try response.headers.append("content-type", "application/json");
        try response.do();
        try response.writeAll(json);
        try response.finish();
    }
    
    fn sendError(
        self: *MockServer,
        response: *http.Server.Response,
        status_code: u16,
        error_type: []const u8,
        message: []const u8,
    ) !void {
        const error_json = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "code": {d},
            \\  "message": "{s}",
            \\  "type": "{s}"
            \\}}
        , .{ status_code, message, error_type });
        defer self.allocator.free(error_json);
        
        response.status = @enumFromInt(status_code);
        response.transfer_encoding = .{ .content_length = error_json.len };
        try response.headers.append("content-type", "application/json");
        try response.do();
        try response.writeAll(error_json);
        try response.finish();
    }
    
    fn sendRateLimitError(self: *MockServer, response: *http.Server.Response) !void {
        response.status = .too_many_requests;
        try response.headers.append("X-RateLimit-Limit", "200");
        try response.headers.append("X-RateLimit-Remaining", "0");
        try response.headers.append("X-RateLimit-Reset", "1705329600");
        try response.headers.append("Retry-After", "60");
        
        const error_json = 
            \\{
            \\  "code": 429,
            \\  "message": "Rate limit exceeded",
            \\  "type": "rate_limit_error"
            \\}
        ;
        
        response.transfer_encoding = .{ .content_length = error_json.len };
        try response.headers.append("content-type", "application/json");
        try response.do();
        try response.writeAll(error_json);
        try response.finish();
    }
    
    fn getHeader(self: *MockServer, headers: []const http.Header, name: []const u8) ?[]const u8 {
        _ = self;
        for (headers) |header| {
            if (std.mem.eql(u8, header.name, name)) {
                return header.value;
            }
        }
        return null;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const port = 8080;
    var server = try MockServer.init(allocator, port);
    defer server.deinit();
    
    try server.run();
}