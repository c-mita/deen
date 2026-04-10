const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimization = b.standardOptimizeOption(.{});
    const process = b.addExecutable(.{
        .name = "process",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/process.zig"),
            .target = b.graph.host,
            .optimize = optimization,
        }),
    });

    const de_filter = b.addExecutable(.{
        .name = "de_filter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/de_filter.zig"),
            .target = b.graph.host,
            .optimize = optimization,
        }),
    });

    const lookup = b.addExecutable(.{
        .name = "lookup",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lookup.zig"),
            .target = b.graph.host,
            .optimize = optimization,
        }),
    });

    const german_jsonl_gz = b.path("data/german_defs.jsonl.gz");
    const unzip_jsonl = b.addSystemCommand(&.{
        "gzip",
        "-c",
        "-d",
    });
    unzip_jsonl.addFileArg(german_jsonl_gz);
    const unzip_stdout = unzip_jsonl.captureStdOut();

    const trie_builder = b.addExecutable(.{
        .name = "trie_builder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/process.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });

    const run_processor = b.addRunArtifact(trie_builder);

    run_processor.setStdIn(.{ .lazy_path = unzip_stdout });
    const trie_data = run_processor.addOutputFileArg("data.trie");
    const definition_data = run_processor.addOutputFileArg("data.dat");

    const deen = b.addExecutable(.{
        .name = "deen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/deen.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSmall,
        }),
    });
    deen.root_module.addAnonymousImport("data.trie", .{ .root_source_file = trie_data });
    deen.root_module.addAnonymousImport("data.dat", .{ .root_source_file = definition_data });

    const gen_step = b.step("generate", "Generate the trie assests");
    gen_step.dependOn(&run_processor.step);

    const deen_step = b.step("deen", "Generate deen with embedded data.");
    const deen_exec = b.addInstallArtifact(deen, .{});
    deen_step.dependOn(&deen_exec.step);

    const tools_step = b.step("tools", "Build the various tool binaries.");
    const de_filter_artifact = b.addInstallArtifact(de_filter, .{});
    const process_artifact = b.addInstallArtifact(process, .{});
    const lookup_artifact = b.addInstallArtifact(lookup, .{});
    tools_step.dependOn(&de_filter_artifact.step);
    tools_step.dependOn(&process_artifact.step);
    tools_step.dependOn(&lookup_artifact.step);
}
