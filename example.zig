const std = @import("std");
// When using as a dependency, this would be:
// const AlpacaClient = @import("quantum-alpaca").AlpacaClient;
const AlpacaClient = @import("src/alpaca_client.zig").AlpacaClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get API credentials from environment
    const api_key = std.process.getEnvVarOwned(allocator, "ALPACA_API_KEY") catch {
        std.debug.print("Please set ALPACA_API_KEY and ALPACA_SECRET_KEY environment variables\n", .{});
        return;
    };
    defer allocator.free(api_key);

    const api_secret = std.process.getEnvVarOwned(allocator, "ALPACA_SECRET_KEY") catch {
        std.debug.print("Please set ALPACA_SECRET_KEY environment variable\n", .{});
        return;
    };
    defer allocator.free(api_secret);

    // Initialize client for paper trading
    var client = AlpacaClient.init(
        allocator,
        api_key,
        api_secret,
        .paper, // Use .live for production
    );
    defer client.deinit();

    // Get account information
    std.debug.print("Fetching account information...\n", .{});
    var response = try client.getAccount();
    defer response.deinit();

    if (response.isSuccess()) {
        std.debug.print("✅ Successfully connected to Alpaca API\n", .{});
        std.debug.print("Response length: {} bytes\n", .{response.body.len});

        // Try to parse as raw JSON first
        if (response.body.len > 0 and response.body[0] == '{') {
            // It's JSON, try to parse
            const account = response.json(AlpacaClient.Account) catch |err| {
                std.debug.print("Parse error: {}\n", .{err});
                std.debug.print("Raw response (first 500 chars): {s}\n", .{response.body[0..@min(500, response.body.len)]});
                return err;
            };
            defer account.deinit();

            std.debug.print("Account Status: {s}\n", .{account.value.status});
            std.debug.print("Buying Power: ${s}\n", .{account.value.buying_power});
            std.debug.print("Portfolio Value: ${s}\n", .{account.value.portfolio_value});
            std.debug.print("Cash: ${s}\n", .{account.value.cash});
        } else {
            std.debug.print("Response doesn't look like JSON\n", .{});
            std.debug.print("First bytes: ", .{});
            for (response.body[0..@min(20, response.body.len)]) |byte| {
                std.debug.print("{x:0>2} ", .{byte});
            }
            std.debug.print("\n", .{});
        }
    } else {
        std.debug.print("❌ Failed to connect: HTTP {}\n", .{response.status});
        std.debug.print("Response: {s}\n", .{response.body});
    }

    // Get market clock
    std.debug.print("\nChecking market status...\n", .{});
    var clock_response = try client.getClock();
    defer clock_response.deinit();

    if (clock_response.isSuccess()) {
        const ClockData = struct {
            timestamp: []const u8,
            is_open: bool,
            next_open: []const u8,
            next_close: []const u8,
        };

        const clock = try clock_response.json(ClockData);
        defer clock.deinit();

        std.debug.print("Market is: {s}\n", .{if (clock.value.is_open) "OPEN 🟢" else "CLOSED 🔴"});
        std.debug.print("Next Open: {s}\n", .{clock.value.next_open});
        std.debug.print("Next Close: {s}\n", .{clock.value.next_close});
    }

    // Example: Submit a paper order (commented out for safety)
    // const order = AlpacaClient.OrderRequest{
    //     .symbol = "AAPL",
    //     .qty = 1,
    //     .side = "buy",
    //     .type = "market",
    //     .time_in_force = "day",
    // };
    // var order_response = try client.submitOrder(order);
    // defer order_response.deinit();

    std.debug.print("\n✅ Quantum Alpaca client is working!\n", .{});
}