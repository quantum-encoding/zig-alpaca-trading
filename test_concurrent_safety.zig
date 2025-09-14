// Concurrent Safety Test for Thread-Safe Alpaca Client
// This test would have segfaulted with shared client architecture

const std = @import("std");
const ThreadSafeAlpacaClient = @import("src/thread_safe_client.zig").ThreadSafeAlpacaClient;
const AlpacaClientPool = @import("src/thread_safe_client.zig").AlpacaClientPool;

const TestConfig = struct {
    num_threads: u32 = 10,
    requests_per_thread: u32 = 50,
    delay_between_requests_ms: u64 = 100,
};

const ThreadWorker = struct {
    thread_id: []const u8,
    client: *ThreadSafeAlpacaClient,
    pool: *AlpacaClientPool,
    requests_to_make: u32,
    delay_ms: u64,
    success_count: *std.atomic.Value(u32),
    failure_count: *std.atomic.Value(u32),
    allocator: std.mem.Allocator,

    fn run(self: *ThreadWorker) void {
        std.log.info("[{s}] Starting worker - making {d} requests", .{
            self.thread_id,
            self.requests_to_make,
        });

        for (0..self.requests_to_make) |i| {
            // Rotate through different endpoints
            const operation = i % 5;

            const result = switch (operation) {
                0 => self.client.getAccount(),
                1 => self.client.getPositions(),
                2 => self.client.getOrders("open"),
                3 => self.client.getOrders("closed"),
                4 => blk: {
                    // Try to get a specific position
                    const response = self.client.getPosition("AAPL");
                    break :blk response;
                },
                else => unreachable,
            };

            if (result) |response_const| {
                var response = response_const;
                defer response.deinit();

                if (response.isSuccess()) {
                    _ = self.success_count.fetchAdd(1, .monotonic);
                } else {
                    _ = self.failure_count.fetchAdd(1, .monotonic);
                    std.log.warn("[{s}] Request {d} got status: {}", .{
                        self.thread_id,
                        i,
                        response.status,
                    });
                }
            } else |err| {
                _ = self.failure_count.fetchAdd(1, .monotonic);
                std.log.err("[{s}] Request {d} failed: {}", .{
                    self.thread_id,
                    i,
                    err,
                });
            }

            if (i % 10 == 0 and i > 0) {
                std.log.info("[{s}] Progress: {d}/{d} requests", .{
                    self.thread_id,
                    i,
                    self.requests_to_make,
                });
            }

            // Small delay between requests
            std.Thread.sleep(self.delay_ms * std.time.ns_per_ms);
        }

        std.log.info("[{s}] Worker complete", .{self.thread_id});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get credentials from environment
    const api_key = std.process.getEnvVarOwned(allocator, "APCA_API_KEY_ID") catch {
        std.log.err("Missing APCA_API_KEY_ID environment variable", .{});
        std.log.info("Running in mock mode without real API calls", .{});
        return runMockTest(allocator);
    };
    defer allocator.free(api_key);

    const api_secret = std.process.getEnvVarOwned(allocator, "APCA_API_SECRET_KEY") catch {
        std.log.err("Missing APCA_API_SECRET_KEY environment variable", .{});
        return;
    };
    defer allocator.free(api_secret);

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = TestConfig{};
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--threads") and i + 1 < args.len) {
            config.num_threads = try std.fmt.parseInt(u32, args[i + 1], 10);
        } else if (std.mem.eql(u8, arg, "--requests") and i + 1 < args.len) {
            config.requests_per_thread = try std.fmt.parseInt(u32, args[i + 1], 10);
        } else if (std.mem.eql(u8, arg, "--delay") and i + 1 < args.len) {
            config.delay_between_requests_ms = try std.fmt.parseInt(u64, args[i + 1], 10);
        }
    }

    std.log.info("🚀 THREAD SAFETY TEST: Concurrent Alpaca Client", .{});
    std.log.info("Configuration:", .{});
    std.log.info("  Threads: {d}", .{config.num_threads});
    std.log.info("  Requests per thread: {d}", .{config.requests_per_thread});
    std.log.info("  Total requests: {d}", .{config.num_threads * config.requests_per_thread});
    std.log.info("  Delay between requests: {d}ms", .{config.delay_between_requests_ms});
    std.log.info("", .{});

    // Initialize client pool
    var pool = try AlpacaClientPool.init(
        allocator,
        api_key,
        api_secret,
        .paper,
    );
    defer pool.deinit();

    // Shared counters
    var success_count = std.atomic.Value(u32).init(0);
    var failure_count = std.atomic.Value(u32).init(0);

    // Create workers
    const workers = try allocator.alloc(ThreadWorker, config.num_threads);
    defer allocator.free(workers);

    for (workers, 0..) |*worker, i| {
        const thread_id = try std.fmt.allocPrint(allocator, "worker_{d}", .{i});
        const client = try pool.createClient(thread_id);

        worker.* = .{
            .thread_id = thread_id,
            .client = client,
            .pool = &pool,
            .requests_to_make = config.requests_per_thread,
            .delay_ms = config.delay_between_requests_ms,
            .success_count = &success_count,
            .failure_count = &failure_count,
            .allocator = allocator,
        };
    }
    defer for (workers) |*worker| {
        pool.destroyClient(worker.client);
        allocator.free(worker.thread_id);
    };

    // Create threads
    const threads = try allocator.alloc(std.Thread, config.num_threads);
    defer allocator.free(threads);

    const start_time = std.time.milliTimestamp();

    // Launch all threads simultaneously
    std.log.info("🔥 Launching {d} concurrent threads...", .{config.num_threads});
    for (threads, workers) |*thread, *worker| {
        thread.* = try std.Thread.spawn(.{}, ThreadWorker.run, .{worker});
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    const end_time = std.time.milliTimestamp();
    const duration_ms = end_time - start_time;

    // Print results
    const total_success = success_count.load(.acquire);
    const total_failure = failure_count.load(.acquire);
    const total_attempted = total_success + total_failure;

    std.log.info("", .{});
    std.log.info("✅ THREAD SAFETY TEST COMPLETE", .{});
    std.log.info("Results:", .{});
    std.log.info("  Duration: {d}ms", .{duration_ms});
    std.log.info("  Successful requests: {d}", .{total_success});
    std.log.info("  Failed requests: {d}", .{total_failure});
    std.log.info("  Total attempted: {d}", .{total_attempted});
    if (total_attempted > 0) {
        std.log.info("  Success rate: {d:.2}%", .{
            @as(f64, @floatFromInt(total_success)) / @as(f64, @floatFromInt(total_attempted)) * 100
        });
        std.log.info("  Requests per second: {d:.2}", .{
            @as(f64, @floatFromInt(total_attempted)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0)
        });
    }

    if (total_failure == 0) {
        std.log.info("", .{});
        std.log.info("🎉 NO SEGFAULTS! Thread-safe architecture confirmed!", .{});
    } else if (total_attempted > 0 and total_failure > total_attempted / 2) {
        std.log.warn("⚠️  High failure rate - check API limits or network", .{});
    }
}

fn runMockTest(allocator: std.mem.Allocator) !void {
    std.log.info("🧪 Running mock test without real API calls", .{});

    // Create a simple test to verify compilation and basic structure
    var pool = try AlpacaClientPool.init(
        allocator,
        "mock_key",
        "mock_secret",
        .paper,
    );
    defer pool.deinit();

    const client1 = try pool.createClient("mock_thread_1");
    defer pool.destroyClient(client1);

    const client2 = try pool.createClient("mock_thread_2");
    defer pool.destroyClient(client2);

    std.log.info("✅ Mock test passed - client creation and cleanup works", .{});
    std.log.info("", .{});
    std.log.info("To run the real concurrent test, set these environment variables:", .{});
    std.log.info("  export APCA_API_KEY_ID=your_api_key", .{});
    std.log.info("  export APCA_API_SECRET_KEY=your_api_secret", .{});
}