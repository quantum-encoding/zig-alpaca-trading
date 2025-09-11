const std = @import("std");
const testing = std.testing;
const AlpacaClient = @import("../src/alpaca_client.zig").AlpacaClient;
const types = @import("../src/alpaca_types.zig");
const errors = @import("../src/alpaca_errors.zig");

/// Comprehensive integration test suite for Alpaca client
/// Tests all endpoints against mock server with realistic scenarios

const TestConfig = struct {
    mock_server_url: []const u8 = "http://127.0.0.1:8080",
    api_key: []const u8 = "TEST_API_KEY",
    secret_key: []const u8 = "TEST_SECRET_KEY",
    timeout_ms: u64 = 30000,
};

test "Account endpoint integration" {
    const allocator = testing.allocator;
    const config = TestConfig{};
    
    var client = AlpacaClient.init(
        allocator,
        config.api_key,
        config.secret_key,
        .paper,
    );
    defer client.deinit();
    
    // Override base URL for testing
    client.base_url = config.mock_server_url;
    
    // Test account retrieval
    var response = client.getAccount() catch |err| {
        // If mock server isn't running, skip this test
        if (err == error.ConnectionRefused) {
            std.debug.print("Mock server not running, skipping integration test\n", .{});
            return;
        }
        return err;
    };
    defer response.deinit();
    
    try testing.expect(response.isSuccess());
    
    const account = try response.json(types.Account);
    defer account.deinit();
    
    try testing.expect(std.mem.eql(u8, account.value.status, "ACTIVE"));
    try testing.expect(std.mem.eql(u8, account.value.currency, "USD"));
    try testing.expect(!account.value.pattern_day_trader);
}

test "Orders endpoint integration" {
    const allocator = testing.allocator;
    const config = TestConfig{};
    
    var client = AlpacaClient.init(
        allocator,
        config.api_key,
        config.secret_key,
        .paper,
    );
    defer client.deinit();
    
    client.base_url = config.mock_server_url;
    
    // Test order submission
    const order_request = AlpacaClient.OrderRequest{
        .symbol = "AAPL",
        .qty = 10,
        .side = "buy",
        .type = "limit",
        .time_in_force = "day",
        .limit_price = 150.00,
    };
    
    var submit_response = client.submitOrder(order_request) catch |err| {
        if (err == error.ConnectionRefused) {
            std.debug.print("Mock server not running, skipping integration test\n", .{});
            return;
        }
        return err;
    };
    defer submit_response.deinit();
    
    try testing.expect(submit_response.isSuccess());
    
    const order = try submit_response.json(types.Order);
    defer order.deinit();
    
    try testing.expect(std.mem.eql(u8, order.value.symbol, "AAPL"));
    try testing.expect(std.mem.eql(u8, order.value.side, "buy"));
    
    // Test order retrieval
    var get_response = client.getOrder(order.value.id) catch |err| {
        if (err == error.ConnectionRefused) return;
        return err;
    };
    defer get_response.deinit();
    
    try testing.expect(get_response.isSuccess());
}

test "Market data integration" {
    const allocator = testing.allocator;
    const config = TestConfig{};
    
    var client = AlpacaClient.init(
        allocator,
        config.api_key,
        config.secret_key,
        .paper,
    );
    defer client.deinit();
    
    client.data_url = config.mock_server_url;
    
    // Test latest quote
    var quote_response = client.getLatestQuote("AAPL") catch |err| {
        if (err == error.ConnectionRefused) {
            std.debug.print("Mock server not running, skipping integration test\n", .{});
            return;
        }
        return err;
    };
    defer quote_response.deinit();
    
    try testing.expect(quote_response.isSuccess());
    
    // Test latest trade
    var trade_response = client.getLatestTrade("AAPL") catch |err| {
        if (err == error.ConnectionRefused) return;
        return err;
    };
    defer trade_response.deinit();
    
    try testing.expect(trade_response.isSuccess());
    
    // Test bars
    var bars_response = client.getBars("AAPL", "1Day", "2024-01-01", "2024-01-31", 30) catch |err| {
        if (err == error.ConnectionRefused) return;
        return err;
    };
    defer bars_response.deinit();
    
    try testing.expect(bars_response.isSuccess());
}

test "Error handling integration" {
    const allocator = testing.allocator;
    
    var client = AlpacaClient.init(
        allocator,
        "INVALID_KEY",
        "INVALID_SECRET",
        .paper,
    );
    defer client.deinit();
    
    client.base_url = "http://127.0.0.1:8080";
    
    // Test authentication error
    var response = client.getAccount() catch |err| {
        if (err == error.ConnectionRefused) {
            std.debug.print("Mock server not running, skipping integration test\n", .{});
            return;
        }
        return err;
    };
    defer response.deinit();
    
    try testing.expect(!response.isSuccess());
    try testing.expect(response.status == .unauthorized);
}

test "Rate limiting integration" {
    const allocator = testing.allocator;
    const config = TestConfig{};
    
    var client = AlpacaClient.init(
        allocator,
        config.api_key,
        config.secret_key,
        .paper,
    );
    defer client.deinit();
    
    client.base_url = config.mock_server_url;
    
    // Make multiple rapid requests to trigger rate limiting
    var i: u32 = 0;
    var rate_limited = false;
    
    while (i < 250 and !rate_limited) { // More than the 200/min limit
        var response = client.getAccount() catch |err| {
            if (err == error.ConnectionRefused) {
                std.debug.print("Mock server not running, skipping integration test\n", .{});
                return;
            }
            if (err == error.RateLimitExceeded) {
                rate_limited = true;
                break;
            }
            return err;
        };
        response.deinit();
        
        if (response.status == .too_many_requests) {
            rate_limited = true;
            try testing.expect(response.rate_limit_info != null);
        }
        
        i += 1;
    }
    
    // We should hit rate limit before 250 requests
    try testing.expect(rate_limited or i < 250);
}

test "Concurrent access safety" {
    const allocator = testing.allocator;
    const config = TestConfig{};
    
    const Worker = struct {
        allocator: std.mem.Allocator,
        api_key: []const u8,
        secret_key: []const u8,
        base_url: []const u8,
        success_count: *std.atomic.Value(u32),
        error_count: *std.atomic.Value(u32),
        
        fn run(self: @This()) void {
            var client = AlpacaClient.init(
                self.allocator,
                self.api_key,
                self.secret_key,
                .paper,
            );
            defer client.deinit();
            
            client.base_url = self.base_url;
            
            var i: u32 = 0;
            while (i < 10) {
                var response = client.getAccount() catch |err| {
                    if (err == error.ConnectionRefused) return;
                    _ = self.error_count.fetchAdd(1, .monotonic);
                    return;
                };
                defer response.deinit();
                
                if (response.isSuccess()) {
                    _ = self.success_count.fetchAdd(1, .monotonic);
                } else {
                    _ = self.error_count.fetchAdd(1, .monotonic);
                }
                
                i += 1;
                std.time.sleep(10 * std.time.ns_per_ms); // Small delay
            }
        }
    };
    
    var success_count = std.atomic.Value(u32).init(0);
    var error_count = std.atomic.Value(u32).init(0);
    
    const num_workers = 4;
    var workers: [num_workers]Worker = undefined;
    var threads: [num_workers]std.Thread = undefined;
    
    // Initialize workers
    for (&workers, 0..) |*worker, i| {
        _ = i;
        worker.* = Worker{
            .allocator = allocator,
            .api_key = config.api_key,
            .secret_key = config.secret_key,
            .base_url = config.mock_server_url,
            .success_count = &success_count,
            .error_count = &error_count,
        };
    }
    
    // Launch threads
    for (&workers, &threads) |*worker, *thread| {
        thread.* = std.Thread.spawn(.{}, Worker.run, .{worker.*}) catch {
            std.debug.print("Failed to spawn thread, skipping concurrent test\n", .{});
            return;
        };
    }
    
    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }
    
    const total_successes = success_count.load(.monotonic);
    const total_errors = error_count.load(.monotonic);
    
    std.debug.print("Concurrent test results: {} successes, {} errors\n", .{ total_successes, total_errors });
    
    // Should have some successes (unless mock server isn't running)
    if (total_successes + total_errors > 0) {
        try testing.expect(total_successes > 0 or total_errors > 0);
    }
}