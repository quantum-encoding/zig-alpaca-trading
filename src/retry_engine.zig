// Copyright (c) 2025 QUANTUM ENCODING LTD
// Author: Rich <rich@quantumencoding.io>
// Website: https://quantumencoding.io
// 
// Licensed under the MIT License. See LICENSE file for details.

const std = @import("std");
const errors = @import("alpaca_errors.zig");

/// Enterprise-grade retry engine with exponential backoff and jitter
/// Implements production-level resilience patterns for high-frequency trading

pub const RetryConfig = struct {
    max_attempts: u32 = 5,
    base_delay_ms: u64 = 100,
    max_delay_ms: u64 = 30000,
    backoff_multiplier: f64 = 2.0,
    jitter_factor: f64 = 0.1,
    enable_circuit_breaker: bool = true,
    circuit_failure_threshold: u32 = 10,
    circuit_recovery_timeout_ms: u64 = 60000,
};

pub const CircuitState = enum {
    closed,    // Normal operation
    open,      // Circuit is open, failing fast
    half_open, // Testing if service recovered
};

pub const CircuitBreaker = struct {
    state: CircuitState = .closed,
    failure_count: u32 = 0,
    success_count: u32 = 0,
    last_failure_time: i64 = 0,
    config: RetryConfig,
    mutex: std.Thread.Mutex = .{},
    
    pub fn init(config: RetryConfig) CircuitBreaker {
        return CircuitBreaker{
            .config = config,
        };
    }
    
    pub fn canExecute(self: *CircuitBreaker) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        switch (self.state) {
            .closed => return true,
            .open => {
                const now = std.time.milliTimestamp();
                if (now - self.last_failure_time > self.config.circuit_recovery_timeout_ms) {
                    self.state = .half_open;
                    return true;
                }
                return false;
            },
            .half_open => return true,
        }
    }
    
    pub fn onSuccess(self: *CircuitBreaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.failure_count = 0;
        if (self.state == .half_open) {
            self.success_count += 1;
            if (self.success_count >= 3) {
                self.state = .closed;
                self.success_count = 0;
            }
        }
    }
    
    pub fn onFailure(self: *CircuitBreaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.failure_count += 1;
        self.last_failure_time = std.time.milliTimestamp();
        
        if (self.failure_count >= self.config.circuit_failure_threshold) {
            self.state = .open;
            self.success_count = 0;
        }
    }
};

pub const RetryEngine = struct {
    allocator: std.mem.Allocator,
    config: RetryConfig,
    circuit_breaker: ?CircuitBreaker,
    rate_limiter: RateLimiter,
    
    const RateLimiter = struct {
        tokens: f64,
        max_tokens: f64,
        refill_rate: f64, // tokens per second
        last_refill: i64,
        mutex: std.Thread.Mutex = .{},
        
        pub fn init(max_requests_per_minute: u32) RateLimiter {
            const max_tokens = @as(f64, @floatFromInt(max_requests_per_minute));
            return RateLimiter{
                .tokens = max_tokens,
                .max_tokens = max_tokens,
                .refill_rate = max_tokens / 60.0, // per second
                .last_refill = std.time.milliTimestamp(),
            };
        }
        
        pub fn tryAcquire(self: *RateLimiter, tokens_needed: f64) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.refillTokens();
            
            if (self.tokens >= tokens_needed) {
                self.tokens -= tokens_needed;
                return true;
            }
            return false;
        }
        
        pub fn getWaitTimeMs(self: *RateLimiter, tokens_needed: f64) u64 {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            self.refillTokens();
            
            if (self.tokens >= tokens_needed) {
                return 0;
            }
            
            const tokens_deficit = tokens_needed - self.tokens;
            const wait_seconds = tokens_deficit / self.refill_rate;
            return @intFromFloat(wait_seconds * 1000.0);
        }
        
        fn refillTokens(self: *RateLimiter) void {
            const now = std.time.milliTimestamp();
            const elapsed_ms = now - self.last_refill;
            const elapsed_seconds = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
            
            const tokens_to_add = elapsed_seconds * self.refill_rate;
            self.tokens = @min(self.max_tokens, self.tokens + tokens_to_add);
            self.last_refill = now;
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, config: RetryConfig) RetryEngine {
        return RetryEngine{
            .allocator = allocator,
            .config = config,
            .circuit_breaker = if (config.enable_circuit_breaker) CircuitBreaker.init(config) else null,
            .rate_limiter = RateLimiter.init(200), // Alpaca's 200 requests per minute limit
        };
    }
    
    /// Execute function with retry logic and rate limiting
    pub fn execute(
        self: *RetryEngine,
        comptime ReturnType: type,
        context: anytype,
        func: fn (@TypeOf(context)) anyerror!ReturnType,
    ) !ReturnType {
        // Check circuit breaker
        if (self.circuit_breaker) |*cb| {
            if (!cb.canExecute()) {
                return errors.AlpacaError.ServiceUnavailable;
            }
        }
        
        var attempt: u32 = 0;
        var last_error: anyerror = undefined;
        
        while (attempt < self.config.max_attempts) {
            // Rate limiting
            if (!self.rate_limiter.tryAcquire(1.0)) {
                const wait_ms = self.rate_limiter.getWaitTimeMs(1.0);
                if (wait_ms > 0 and wait_ms < 5000) { // Don't wait more than 5 seconds
                    std.time.sleep(wait_ms * std.time.ns_per_ms);
                }
            }
            
            // Attempt execution
            const result = func(context);
            
            if (result) |success| {
                // Success - update circuit breaker
                if (self.circuit_breaker) |*cb| {
                    cb.onSuccess();
                }
                return success;
            } else |err| {
                last_error = err;
                attempt += 1;
                
                // Check if error is retryable
                const alpaca_err = self.convertToAlpacaError(err);
                if (!errors.isRetryable(alpaca_err)) {
                    if (self.circuit_breaker) |*cb| {
                        cb.onFailure();
                    }
                    return err;
                }
                
                // Calculate backoff delay
                if (attempt < self.config.max_attempts) {
                    const delay_ms = self.calculateBackoffDelay(attempt);
                    std.time.sleep(delay_ms * std.time.ns_per_ms);
                }
            }
        }
        
        // All attempts failed
        if (self.circuit_breaker) |*cb| {
            cb.onFailure();
        }
        
        return last_error;
    }
    
    fn convertToAlpacaError(self: *RetryEngine, err: anyerror) errors.AlpacaError {
        _ = self;
        return switch (err) {
            error.ConnectionRefused => error.ConnectionRefused,
            error.ConnectionTimedOut => error.ConnectionTimeout,
            error.ConnectionResetByPeer => error.ConnectionReset,
            error.NetworkUnreachable => error.NetworkUnreachable,
            error.HostUnreachable => error.HostUnreachable,
            error.OutOfMemory => error.InternalServerError,
            else => error.InternalServerError,
        };
    }
    
    fn calculateBackoffDelay(self: *RetryEngine, attempt: u32) u64 {
        var delay = @as(f64, @floatFromInt(self.config.base_delay_ms)) * 
                   std.math.pow(f64, self.config.backoff_multiplier, @as(f64, @floatFromInt(attempt)));
        
        // Cap at max delay
        delay = @min(delay, @as(f64, @floatFromInt(self.config.max_delay_ms)));
        
        // Add jitter to prevent thundering herd
        const jitter_range = delay * self.config.jitter_factor;
        const jitter = (std.crypto.random.float(f64) - 0.5) * jitter_range;
        delay += jitter;
        
        return @max(1, @as(u64, @intFromFloat(delay)));
    }
    
    /// Get current rate limiter status
    pub fn getRateLimitStatus(self: *RetryEngine) struct { tokens: f64, max_tokens: f64, refill_rate: f64 } {
        self.rate_limiter.mutex.lock();
        defer self.rate_limiter.mutex.unlock();
        
        self.rate_limiter.refillTokens();
        
        return .{
            .tokens = self.rate_limiter.tokens,
            .max_tokens = self.rate_limiter.max_tokens,
            .refill_rate = self.rate_limiter.refill_rate,
        };
    }
    
    /// Get circuit breaker status
    pub fn getCircuitBreakerStatus(self: *RetryEngine) ?struct { 
        state: CircuitState, 
        failure_count: u32, 
        success_count: u32,
        can_execute: bool 
    } {
        if (self.circuit_breaker) |*cb| {
            cb.mutex.lock();
            defer cb.mutex.unlock();
            
            return .{
                .state = cb.state,
                .failure_count = cb.failure_count,
                .success_count = cb.success_count,
                .can_execute = cb.canExecute(),
            };
        }
        return null;
    }
};