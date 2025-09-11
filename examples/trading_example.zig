// Copyright (c) 2025 QUANTUM ENCODING LTD
// Author: Rich <rich@quantumencoding.io>
// Website: https://quantumencoding.io
// 
// Licensed under the MIT License. See LICENSE file for details.

const std = @import("std");
const AlpacaClient = @import("quantum-alpaca").AlpacaClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Quantum Alpaca Trading Client Example ===\n\n", .{});

    // Get API credentials from environment
    const api_key = std.process.getEnvVarOwned(allocator, "ALPACA_API_KEY") catch {
        std.debug.print("Error: ALPACA_API_KEY environment variable not set\n", .{});
        std.debug.print("Please set: export ALPACA_API_KEY=your_api_key\n", .{});
        std.debug.print("         : export ALPACA_SECRET_KEY=your_secret_key\n", .{});
        return;
    };
    defer allocator.free(api_key);

    const api_secret = std.process.getEnvVarOwned(allocator, "ALPACA_SECRET_KEY") catch {
        std.debug.print("Error: ALPACA_SECRET_KEY environment variable not set\n", .{});
        return;
    };
    defer allocator.free(api_secret);

    // Initialize client for paper trading
    var client = AlpacaClient.init(
        allocator,
        api_key,
        api_secret,
        .paper,
    );
    defer client.deinit();

    // Example 1: Get account information
    try exampleGetAccount(&client);

    // Example 2: Get market clock
    try exampleGetClock(&client);

    // Example 3: Get positions (if any)
    try exampleGetPositions(&client);

    // Example 4: Submit a paper order (commented out to prevent accidental orders)
    // try exampleSubmitOrder(&client);

    std.debug.print("\nAll examples completed successfully!\n", .{});
}

fn exampleGetAccount(client: *AlpacaClient) !void {
    std.debug.print("1. Getting Account Information\n", .{});
    
    var response = try client.getAccount();
    defer response.deinit();

    if (response.status == .ok) {
        const account = try response.json(AlpacaClient.Account);
        defer account.deinit();
        
        std.debug.print("   Account Status: {s}\n", .{account.value.status});
        std.debug.print("   Buying Power: {s}\n", .{account.value.buying_power});
        std.debug.print("   Portfolio Value: {s}\n", .{account.value.portfolio_value});
        std.debug.print("   Pattern Day Trader: {}\n\n", .{account.value.pattern_day_trader});
    } else {
        std.debug.print("   Failed to get account: Status {}\n\n", .{response.status});
    }
}

fn exampleGetClock(client: *AlpacaClient) !void {
    std.debug.print("2. Getting Market Clock\n", .{});
    
    var response = try client.getClock();
    defer response.deinit();

    if (response.status == .ok) {
        // Parse the clock response
        const ClockResponse = struct {
            timestamp: []const u8,
            is_open: bool,
            next_open: []const u8,
            next_close: []const u8,
        };
        
        const clock = try response.json(ClockResponse);
        defer clock.deinit();
        
        std.debug.print("   Market is: {s}\n", .{if (clock.value.is_open) "OPEN" else "CLOSED"});
        std.debug.print("   Next Open: {s}\n", .{clock.value.next_open});
        std.debug.print("   Next Close: {s}\n\n", .{clock.value.next_close});
    } else {
        std.debug.print("   Failed to get clock: Status {}\n\n", .{response.status});
    }
}

fn exampleGetPositions(client: *AlpacaClient) !void {
    std.debug.print("3. Getting Current Positions\n", .{});
    
    var response = try client.getPositions();
    defer response.deinit();

    if (response.status == .ok) {
        const positions = try response.json([]AlpacaClient.Position);
        defer positions.deinit();
        
        if (positions.value.len == 0) {
            std.debug.print("   No open positions\n\n", .{});
        } else {
            std.debug.print("   Found {} position(s):\n", .{positions.value.len});
            for (positions.value) |pos| {
                std.debug.print("     - {s}: {} shares @ ${s}\n", .{
                    pos.symbol,
                    pos.qty,
                    pos.avg_entry_price,
                });
            }
            std.debug.print("\n", .{});
        }
    } else {
        std.debug.print("   Failed to get positions: Status {}\n\n", .{response.status});
    }
}

fn exampleSubmitOrder(client: *AlpacaClient) !void {
    std.debug.print("4. Submitting Paper Order (TEST)\n", .{});
    
    // Example order: Buy 1 share of SPY at market
    const order = AlpacaClient.OrderRequest{
        .symbol = "SPY",
        .qty = 1,
        .side = "buy",
        .type = "market",
        .time_in_force = "day",
    };

    var response = try client.submitOrder(order);
    defer response.deinit();

    if (response.status == .ok) {
        const order_response = try response.json(AlpacaClient.Order);
        defer order_response.deinit();
        
        std.debug.print("   Order submitted successfully!\n", .{});
        std.debug.print("   Order ID: {s}\n", .{order_response.value.id});
        std.debug.print("   Symbol: {s}\n", .{order_response.value.symbol});
        std.debug.print("   Status: {s}\n\n", .{order_response.value.status});
    } else {
        std.debug.print("   Failed to submit order: Status {}\n", .{response.status});
        std.debug.print("   Response: {s}\n\n", .{response.body});
    }
}