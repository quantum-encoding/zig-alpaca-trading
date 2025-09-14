const std = @import("std");
const AlpacaClient = @import("quantum-alpaca").AlpacaClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Testing Quantum Alpaca Client ===\n\n", .{});

    // Get API credentials from environment
    const api_key = std.process.getEnvVarOwned(allocator, "ALPACA_API_KEY") catch {
        std.debug.print("Error: ALPACA_API_KEY environment variable not set\n", .{});
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

    // Test: Get account information
    std.debug.print("1. Getting Account Information\n", .{});
    var response = try client.getAccount();
    defer response.deinit();

    if (response.status == .ok) {
        std.debug.print("   ✅ Account request successful\n", .{});
        std.debug.print("   Response length: {} bytes\n", .{response.body.len});
    } else {
        std.debug.print("   ❌ Account request failed with status: {}\n", .{response.status});
        std.debug.print("   Response: {s}\n", .{response.body});
    }

    std.debug.print("\nTest completed!\n", .{});
}