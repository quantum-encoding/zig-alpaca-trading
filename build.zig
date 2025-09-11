const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the library module
    const alpaca_module = b.addModule("quantum-alpaca", .{
        .root_source_file = b.path("src/alpaca_client.zig"),
    });

    // Examples executable
    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("examples/trading_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("quantum-alpaca", alpaca_module);

    const run_example = b.addRunArtifact(example);
    const run_examples_step = b.step("example", "Run trading example");
    run_examples_step.dependOn(&run_example.step);

    // Unit Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/alpaca_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Integration Tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("quantum-alpaca", alpaca_module);
    
    // Mock Server
    const mock_server = b.addExecutable(.{
        .name = "mock_server",
        .root_source_file = b.path("examples/mock_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const run_mock_server = b.addRunArtifact(mock_server);
    
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    
    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_unit_tests.step);
    
    const integration_test_step = b.step("test-integration", "Run integration tests only");
    integration_test_step.dependOn(&run_integration_tests.step);
    
    const mock_server_step = b.step("mock-server", "Run mock server for testing");
    mock_server_step.dependOn(&run_mock_server.step);
}