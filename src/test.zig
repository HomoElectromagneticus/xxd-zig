const std = @import("std");

pub fn main() !u8 {
    // standard output is for the actual output of the application
    const stdout_file = std.io.getStdOut();
    var bw = std.io.bufferedWriter(stdout_file.writer());
    const stdout_buf = bw.writer();

    // standard error is for any error messages / logs / etc (no buffer needed)
    const stderr_file = std.io.getStdErr();
    const stderr = stderr_file.writer();

    // need to allocate memory in order to parse the command-line args, handle
    // buffers, etc
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const path_string = "test.file";

    // interpret the filepath
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path: []u8 = std.fs.realpath(
        path_string,
        &path_buffer,
    ) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try stderr.print("xxd-zig: File \"{s}\" not found!\n", .{path_string});
            },
            else => {
                try stderr.print("xxd-zig: {s}\n", .{@errorName(err)});
            },
        }
        return 1;
    };

    // open the file
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    // get a buffered reader for the file
    var buffered = std.io.bufferedReader(file.reader());
    var bufreader = buffered.reader();

    var buffer: [16]u8 = undefined;
    @memset(buffer[0..], 0); //sets all the bytes in buffer to 0

    var bytes_read: usize = 0;
    while (true) {
        // Essaye de lire 16 octets à la fois
        const n = try bufreader.readAll(&buffer);
        if (n == 0) {
            break; // Fin du fichier
        }

        // Traiter ici les données lues, ici on les affiche simplement
        try stdout_buf.print("{s}", .{buffer[0..n]});

        bytes_read += n;
    }

    try stdout_buf.print("\nFin du fichier. Nombre total d'octets lus: {}\n", .{bytes_read});
    try bw.flush();
    return 0;
}
