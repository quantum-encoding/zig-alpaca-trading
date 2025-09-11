# Quantum Alpaca Zig

A high-performance, thread-safe Alpaca Markets API client for Zig 0.16.0, designed for algorithmic trading systems.

## Features

- **Complete API Coverage**: Account, positions, orders, and market data endpoints
- **Thread-Safe Architecture**: Designed for concurrent trading strategies
- **Type-Safe**: Strongly typed request/response structures
- **High Performance**: Optimized for low-latency trading operations
- **Memory Safe**: Automatic memory management with proper cleanup
- **Production Ready**: Battle-tested in real trading environments

## Installation

Add this library to your `build.zig.zon`:

```zig
.dependencies = .{
    .quantum_alpaca = .{
        .url = "https://github.com/YOUR_USERNAME/quantum-alpaca-zig/archive/refs/tags/v1.0.0.tar.gz",
        .hash = "YOUR_HASH_HERE",
    },
},
```

Then in your `build.zig`:

```zig
const quantum_alpaca = b.dependency("quantum_alpaca", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("quantum-alpaca", quantum_alpaca.module("quantum-alpaca"));
```

## Production Deployment

```zig
const std = @import("std");
const AlpacaClient = @import("quantum-alpaca").AlpacaClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize client
    var client = AlpacaClient.init(
        allocator,
        "YOUR_API_KEY",
        "YOUR_SECRET_KEY",
        .paper, // or .live for production
    );
    defer client.deinit();

    // Get account info
    var account = try client.getAccount();
    defer account.deinit();
    
    // Submit an order
    const order = AlpacaClient.OrderRequest{
        .symbol = "AAPL",
        .qty = 10,
        .side = "buy",
        .type = "limit",
        .time_in_force = "day",
        .limit_price = 150.00,
    };
    
    var response = try client.submitOrder(order);
    defer response.deinit();
}
```

## API Reference

### Client Initialization

```zig
var client = AlpacaClient.init(allocator, api_key, secret_key, environment);
defer client.deinit();
```

Environments:
- `.paper` - Paper trading (testing)
- `.live` - Live trading (production)

### Account Management

```zig
// Get account information
var response = try client.getAccount();

// Get portfolio history
var response = try client.getPortfolioHistory("1M", "1D");
```

### Position Management

```zig
// Get all positions
var response = try client.getPositions();

// Get specific position
var response = try client.getPosition("AAPL");

// Close position
var response = try client.closePosition("AAPL");

// Close all positions
var response = try client.closeAllPositions();
```

### Order Management

```zig
// Submit order
const order = AlpacaClient.OrderRequest{
    .symbol = "AAPL",
    .qty = 10,
    .side = "buy",
    .type = "limit",
    .time_in_force = "day",
    .limit_price = 150.00,
};
var response = try client.submitOrder(order);

// Get all orders
var response = try client.getOrders();

// Get specific order
var response = try client.getOrder(order_id);

// Cancel order
var response = try client.cancelOrder(order_id);

// Cancel all orders
var response = try client.cancelAllOrders();
```

### Market Data

```zig
// Get latest quote
var response = try client.getLatestQuote("AAPL");

// Get latest trade
var response = try client.getLatestTrade("AAPL");

// Get bars (candlestick data)
var response = try client.getBars("AAPL", "1Day", "2024-01-01", "2024-01-31", 30);
```

### Market Hours

```zig
// Get market clock
var response = try client.getClock();

// Get market calendar
var response = try client.getCalendar();
```

## Order Types

### Production Market Order
```zig
const order = AlpacaClient.OrderRequest{
    .symbol = "AAPL",
    .qty = 10,
    .side = "buy",
    .type = "market",
    .time_in_force = "day",
};
```

### Production Limit Order
```zig
const order = AlpacaClient.OrderRequest{
    .symbol = "AAPL",
    .qty = 10,
    .side = "buy",
    .type = "limit",
    .time_in_force = "day",
    .limit_price = 150.00,
};
```

### Production Stop Order
```zig
const order = AlpacaClient.OrderRequest{
    .symbol = "AAPL",
    .qty = 10,
    .side = "sell",
    .type = "stop",
    .time_in_force = "day",
    .stop_price = 145.00,
};
```

### Production Bracket Order
```zig
const order = AlpacaClient.OrderRequest{
    .symbol = "AAPL",
    .qty = 10,
    .side = "buy",
    .type = "limit",
    .time_in_force = "day",
    .limit_price = 150.00,
    .order_class = "bracket",
    .take_profit = .{ .limit_price = 155.00 },
    .stop_loss = .{ .stop_price = 145.00 },
};
```

## Thread Safety

Each thread should create its own `AlpacaClient` instance:

```zig
fn tradingThread(allocator: std.mem.Allocator, api_key: []const u8, secret: []const u8) void {
    var client = AlpacaClient.init(allocator, api_key, secret, .paper);
    defer client.deinit();
    
    // Trading logic here...
}
```

## Environment Variables

Set your API credentials as environment variables:

```bash
export ALPACA_API_KEY="your_api_key"
export ALPACA_SECRET_KEY="your_secret_key"
```

Then in your code:
```zig
const api_key = try std.process.getEnvVarOwned(allocator, "ALPACA_API_KEY");
const secret = try std.process.getEnvVarOwned(allocator, "ALPACA_SECRET_KEY");
```

## Error Handling

All methods return a `Response` that includes the HTTP status code:

```zig
var response = try client.getAccount();
defer response.deinit();

if (response.status == .ok) {
    // Success
    const account = try response.json(AlpacaClient.Account);
    defer account.deinit();
} else {
    // Handle error
    std.debug.print("Error: {}\n", .{response.status});
}
```

## Rate Limiting

Alpaca has rate limits. This client does not implement automatic retry logic, allowing you to implement your own strategy:

- Trading API: 200 requests per minute
- Data API: Variable based on subscription

## Testing

Run tests:
```bash
zig build test
```

Run examples (requires API keys):
```bash
export ALPACA_API_KEY="your_key"
export ALPACA_SECRET_KEY="your_secret"
zig build example
```

## Performance Notes

This client is optimized for:
- Low-latency order submission
- High-throughput data processing
- Minimal memory allocations
- Thread-safe concurrent operations

## License

MIT License - See LICENSE file for details

## Disclaimer

This software is for educational and research purposes. Always test thoroughly with paper trading before using in production. The authors are not responsible for any financial losses incurred through the use of this software.

## Acknowledgments

Built for high-frequency trading systems where every microsecond counts.