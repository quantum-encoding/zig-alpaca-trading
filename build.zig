const std = @import("std");

pub fn build(b: *std.Build) void {
    // Export the main module for external projects
    _ = b.addModule("quantum-alpaca", .{
        .root_source_file = b.path("src/alpaca_client.zig"),
    });
}