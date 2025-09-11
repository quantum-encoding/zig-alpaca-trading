# Quantum Alpaca Trading Guide

## 🎯 For Algorithmic Traders

This library provides production-grade Alpaca Markets API integration for Zig, extracted from real HFT systems.

## Why Zig for Trading?

- **Zero-cost abstractions**: No hidden allocations or GC pauses
- **Deterministic performance**: Consistent sub-millisecond response times
- **Memory control**: Precise control over every allocation
- **Compile-time safety**: Catch errors before they cost money
- **Native speed**: C-level performance with better safety

## Trading-Specific Features

### 1. Rate Limit Management
```zig
// Built-in rate limiting prevents API throttling
// Automatically handles Alpaca's 200 req/min limit
var client = AlpacaClient.init(allocator, api_key, secret, .paper);
// The retry engine handles 429 responses automatically
```

### 2. Order Execution Patterns
```zig
// Fire-and-forget market orders
const order = try client.submitOrder(.{
    .symbol = "AAPL",
    .qty = 100,
    .side = .buy,
    .type = .market,
    .time_in_force = .day,
});

// Limit orders with retry on rejection
const limit_order = try client.submitOrder(.{
    .symbol = "TSLA",
    .qty = 50,
    .side = .sell,
    .type = .limit,
    .limit_price = 250.00,
    .time_in_force = .gtc,
});
```

### 3. Position Management
```zig
// Get all positions with automatic retry
const positions = try client.getPositions();
defer positions.deinit();

for (positions.value) |position| {
    if (position.unrealized_pl < -100) {
        // Stop loss logic
        try client.closePosition(position.symbol);
    }
}
```

### 4. Real-Time Market Data (WebSocket)
```zig
// Subscribe to trades and quotes
var ws_client = try AlpacaWebSocket.init(allocator, api_key, secret);
defer ws_client.deinit();

try ws_client.subscribe(&.{"AAPL", "TSLA", "SPY"});

while (true) {
    const msg = try ws_client.receive();
    switch (msg) {
        .trade => |t| processTraade(t),
        .quote => |q| processQuote(q),
        .bar => |b| processBar(b),
    }
}
```

## Performance Optimizations

### Memory Pool Pattern
```zig
// Pre-allocate for hot path
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

// Fast allocations in trading loop
while (market_open) {
    const order_allocator = arena.allocator();
    const order = try submitOrder(order_allocator, ...);
    // No individual frees needed
}
```

### Concurrent Strategy Execution
```zig
// Each strategy gets its own client (client-per-worker pattern)
fn strategyWorker(symbol: []const u8) void {
    var client = AlpacaClient.init(allocator, key, secret, .paper);
    defer client.deinit();
    
    while (trading) {
        const data = try client.getLatestBar(symbol);
        if (shouldTrade(data)) {
            try client.submitOrder(...);
        }
    }
}

// Launch multiple strategies
for (symbols) |symbol| {
    _ = try std.Thread.spawn(.{}, strategyWorker, .{symbol});
}
```

## Risk Management

### Position Sizing
```zig
fn calculatePositionSize(account: Account, risk_percent: f64) u32 {
    const risk_amount = account.equity * (risk_percent / 100.0);
    const max_shares = @floatToInt(u32, risk_amount / stop_loss_distance);
    return @min(max_shares, account.buying_power / current_price);
}
```

### Circuit Breaker Integration
```zig
// Automatic circuit breaker on repeated failures
if (retry_engine.getCircuitBreakerStatus()) |status| {
    if (status.state == .open) {
        // Stop trading, alert operator
        log.err("Circuit breaker open - halting trades", .{});
        return;
    }
}
```

## Backtesting Support

```zig
// Use mock server for backtesting
const mock_client = try AlpacaClient.init(allocator, "mock", "mock", .paper);
mock_client.base_url = "http://localhost:8080"; // Your mock server

// Run same strategies against historical data
const backtest_result = try runStrategy(mock_client, historical_data);
```

## Production Deployment

### Environment Setup
```bash
# Production credentials (keep secure!)
export ALPACA_API_KEY=your_live_key
export ALPACA_SECRET_KEY=your_live_secret

# Paper trading for testing
export ALPACA_PAPER_KEY=your_paper_key
export ALPACA_PAPER_SECRET=your_paper_secret
```

### Monitoring
```zig
// Log all trades for audit
const order_result = try client.submitOrder(order);
log.info("Order submitted: {} {} {} @ {}", .{
    order.side, order.qty, order.symbol, order.limit_price
});

// Track performance metrics
metrics.record(.{
    .orders_submitted = stats.orders,
    .success_rate = stats.successful / stats.total,
    .avg_latency_ms = stats.total_latency / stats.total,
});
```

## Common Patterns

### Pairs Trading
```zig
fn pairsTrade(long_symbol: []const u8, short_symbol: []const u8) !void {
    // Submit orders atomically
    const long_order = try client.submitOrder(.{
        .symbol = long_symbol,
        .side = .buy,
        .qty = 100,
    });
    
    const short_order = try client.submitOrder(.{
        .symbol = short_symbol,
        .side = .sell_short,
        .qty = 100,
    });
    
    // Monitor spread
    while (true) {
        const spread = try calculateSpread(long_symbol, short_symbol);
        if (spread < target_spread) {
            try client.closePosition(long_symbol);
            try client.closePosition(short_symbol);
            break;
        }
    }
}
```

### Market Making
```zig
fn marketMaker(symbol: []const u8, spread: f64) !void {
    const quote = try client.getLatestQuote(symbol);
    
    // Place bid and ask
    const bid = try client.submitOrder(.{
        .symbol = symbol,
        .side = .buy,
        .type = .limit,
        .limit_price = quote.bid - spread/2,
    });
    
    const ask = try client.submitOrder(.{
        .symbol = symbol,
        .side = .sell,
        .type = .limit,
        .limit_price = quote.ask + spread/2,
    });
    
    // Manage inventory
    monitorAndRebalance(symbol);
}
```

## Safety Features

1. **Automatic retry on transient failures**
2. **Circuit breaker prevents cascade failures**
3. **Rate limiting prevents API bans**
4. **Memory safety prevents crashes during trading**
5. **Compile-time validation of order parameters**

## Support

For trading-specific questions, open an issue with the `trading` tag.

Remember: This library is a tool. Your strategy, risk management, and execution are what determine success.

**Trade responsibly. Start with paper trading. Never risk more than you can afford to lose.**

---
*Built by traders, for traders. Extracted from real HFT systems.*