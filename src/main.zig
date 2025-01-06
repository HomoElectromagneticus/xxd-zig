const std = @import("std");
const clap = @import("clap");

const printParams = struct {
    line_length: usize = undefined,
    num_columns: usize = 16,
    group_size: usize = 2,
    stop_after: usize = undefined,
};

fn print_columns(writer: anytype, params: printParams, input: []const u8) !usize {
    // amount of bytes converted into hex
    var num_printed_bytes: usize = 0;
    // number of printed characters of translated input (not including the
    // index markers on the left!)
    var num_printed_chars: usize = 0;

    for (input, 0..) |character, index| {
        // print the hex value of the current character
        try writer.print("{x:0>2}", .{character});
        num_printed_bytes += 1;
        num_printed_chars += 2;
        // if we are at the end of the input, print a space and break
        if (index == input.len - 1) {
            try writer.print(" ", .{});
            num_printed_chars += 1;
            break;
        }
        // if we are at the end of a group, add a space
        if ((index + 1) % params.group_size == 0) {
            try writer.print(" ", .{});
            num_printed_chars += 1;
        }
    }
    // figure out how many spaces to put in so that the text lines up nicely
    var num_spaces: usize = 0;
    if (num_printed_bytes != params.num_columns) {
        num_spaces += params.line_length -| num_printed_chars;
    }
    for (0..num_spaces) |_| {
        try writer.print(" ", .{});
    }

    // print the input of the line as ascii characters
    for (input) |raw_char| {
        if ('\n' == raw_char or '\t' == raw_char) {
            try writer.print(".", .{});
        } else {
            try writer.print("{c}", .{raw_char});
        }
    }
    return num_printed_bytes;
}

fn print_output(writer: anytype, params: printParams, input: []const u8) !void {
    var new_file_pos: usize = 0;

    // split the buffer into segments based on the number of columns / bytes
    // specified via the command line arguments (default 16)
    var input_iterator = std.mem.window(u8, input, params.num_columns, params.num_columns);

    // loop through the buffer and print the output in chunks of the columns
    while (input_iterator.next()) |slice| {
        // print the file position
        try writer.print("{x:0>8}: ", .{new_file_pos});
        new_file_pos += try print_columns(writer, params, slice);
        try writer.print("\n", .{});
    }
}

pub fn main() !void {
    // stdout is for the actual output of your application
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    // need to allocate memory in order to parse the command-line args, handle
    // buffers, etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // First we specify what parameters our program can take.
    // We use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-c, --columns <usize>   Format <columns> per line, default is 16, max 256
        \\-g, --groupsize <usize> Separate the output of in <groupsize> bytes, default 2
        \\-s, --string <str>      Optional input string
        \\-f, --file <str>        Optional input file
        \\-l, --len <usize>       Stop writing afer <len> bytes
        \\
    );

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostics` provides.
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        // Report useful error and exit.
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // print help message and quit if -h is passed in
    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    // store details about how we are printing in this struct
    var print_params = printParams{};
    // the number of columns to use when printing (default 16)
    if (res.args.columns) |c| {
        print_params.num_columns = c;
    }
    // the output grouping when printing (default 2)
    if (res.args.groupsize) |g| {
        print_params.group_size = g;
    }
    // the printed line length - it needs to be this complex to support odd
    // numbers of columns
    print_params.line_length = ((print_params.group_size * 2) + 1) *
        (print_params.num_columns / print_params.group_size);
    if (print_params.num_columns % 2 != 0) print_params.line_length += 3;

    // if we have a simple input string
    if (res.args.string) |s| {
        // decide how much of the input to print
        if (res.args.len) |l| {
            print_params.stop_after = l;
        } else {
            print_params.stop_after = s.len;
        }

        try print_output(stdout, print_params, s[0..print_params.stop_after]);
    }

    // if we have an input file
    if (res.args.file) |f| {
        // interpret the filepath
        var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path = try std.fs.realpath(f, &path_buffer);

        // load the file into memory in a single allocation
        const file_contents = try std.fs.cwd().readFileAlloc(gpa.allocator(), path, std.math.maxInt(usize));
        defer gpa.allocator().free(file_contents);

        // decide how much of the input to print
        if (res.args.len) |l| {
            print_params.stop_after = l;
        } else {
            print_params.stop_after = file_contents.len;
        }

        try print_output(stdout, print_params, file_contents[0..print_params.stop_after]);
    }

    try bw.flush(); // don't forget to flush!
}
