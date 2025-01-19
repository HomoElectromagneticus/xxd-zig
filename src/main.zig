const std = @import("std");
const clap = @import("clap");

const printParams = struct {
    line_length: usize = undefined,
    num_columns: usize = 16,
    group_size: usize = 2,
    start_at: usize = 0,
    stop_after: usize = undefined,
    upper_case: bool = false,
    decimal: bool = false,
    postscript: bool = false,
    position_offset: usize = 0,
};

fn print_columns(writer: anytype, params: printParams, input: []const u8) !usize {
    // amount of bytes converted into hex
    var num_printed_bytes: usize = 0;
    // number of printed characters of translated input (not including the
    // index markers on the left!)
    var num_printed_chars: usize = 0;

    for (input, 0..) |character, index| {
        // print the hex value of the current character
        if (params.upper_case) {
            try writer.print("{X:0>2}", .{character});
        } else {
            try writer.print("{x:0>2}", .{character});
        }
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

    // print the content of the line as ascii characters
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
    // define how much of the input to print
    var length = input.len;
    if (params.stop_after != 0) length = params.stop_after;

    // this variable is used to print the file position information for a row
    var new_file_pos: usize = params.position_offset + params.start_at;

    // if the user asked for postscript plain hexdump style, just dump it all
    // with no fancy formatting
    if (params.postscript) {
        for (input[params.start_at..length]) |character| {
            if (params.upper_case) {
                try writer.print("{X:0>2}", .{character});
            } else {
                try writer.print("{x:0>2}", .{character});
            }
        }
        try writer.print("\n", .{});
        return;
    }

    // split the buffer into segments based on the number of columns / bytes
    // specified via the command line arguments (default 16)
    var input_iterator = std.mem.window(
        u8,
        input[params.start_at..length],
        params.num_columns,
        params.num_columns,
    );

    // loop through the buffer and print the output in chunks of the columns
    while (input_iterator.next()) |slice| {
        // print the file position in hex (default) or decimal
        if (params.decimal) {
            try writer.print("{d:0>8}: ", .{new_file_pos});
        } else {
            try writer.print("{x:0>8}: ", .{new_file_pos});
        }
        new_file_pos += try print_columns(writer, params, slice);
        try writer.print("\n", .{});
    }
}

pub fn main() !void {
    // stdout is for the actual output of the application
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    // stdin is for the actual input of the appplication
    const stdin = std.io.getStdIn().reader();

    // need to allocate memory in order to parse the command-line args, handle
    // buffers, etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // First we specify what parameters our program can take.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit
        \\-c, --columns <usize>   Format <columns> per line, default is 16
        \\-g, --groupsize <usize> Group the output of in <groupsize> bytes, default 2
        \\    --string <str>      Optional input string
        \\-f, --file <str>        Optional input file
        \\-l, --len <usize>       Stop writing after <len> bytes
        \\-o, --off <usize>       Add an offset to the displayed file position
        \\-p                      Output in postscript plain hexdump style
        \\-d                      Show offset in decimal and not hex
        \\-s, --seek <usize>      Start at <usize> bytes absolute
        \\-u                      Use upper-case hex letters, default is lower-case
        \\
    );

    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional for the clap library.
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

    // if -h or --help is passed in, print usage text, help text, then quit
    if (res.args.help != 0) {
        const usage_notes =
            \\Usage:
            \\    xxd-zig [options]
            \\
            \\    If neither --string, -f, nor --file are set,
            \\    the program will read from stdin.
            \\
            \\Options:
        ;
        try stdout.print("{s}\n", .{usage_notes});
        try bw.flush();
        const help_options = clap.HelpOptions{
            .spacing_between_parameters = 1,
            .max_width = 72, //TODO: set to current terminal size
        };
        return clap.help(
            std.io.getStdErr().writer(),
            clap.Help,
            &params,
            help_options,
        );
    }

    // store details about how we are printing in this struct
    var print_params = printParams{};

    // the number of columns to use when printing
    if (res.args.columns) |c| {
        print_params.num_columns = c;
    }
    // the output grouping when printing
    if (res.args.groupsize) |g| {
        print_params.group_size = g;
    }
    // the printed line length - it needs to be this complex to support odd
    // numbers of columns
    print_params.line_length = ((print_params.group_size * 2) + 1) *
        (print_params.num_columns / print_params.group_size);
    if (print_params.num_columns % 2 != 0) print_params.line_length += 3;

    // handle the position offset option if specified
    if (res.args.off) |o| {
        print_params.position_offset = o;
    }

    if (res.args.p != 0) print_params.postscript = true;

    if (res.args.d != 0) print_params.decimal = true;

    if (res.args.seek) |s| {
        print_params.start_at = s;
    }

    if (res.args.u != 0) print_params.upper_case = true;

    if (res.args.len) |l| {
        print_params.stop_after = l;
    }

    // if we have a simple input string
    if (res.args.string) |s| {
        try print_output(stdout, print_params, s);
    }

    // if we have an input file
    if (res.args.file) |f| {
        // interpret the filepath
        var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path = try std.fs.realpath(f, &path_buffer);

        // load the file into memory in a single allocation
        const file_contents = try std.fs.cwd().readFileAlloc(
            gpa.allocator(),
            path,
            std.math.maxInt(usize),
        );
        defer gpa.allocator().free(file_contents);

        try print_output(stdout, print_params, file_contents);
    }

    // if we have no specified input string or input file, we will read from
    // stdin. we'll need to allocate memory since we don't know the size of
    // what's coming from stdin at compile time
    const stdin_contents = try stdin.readAllAlloc(gpa.allocator(), std.math.maxInt(usize));
    defer gpa.allocator().free(stdin_contents);

    try print_output(stdout, print_params, stdin_contents);

    try bw.flush(); // don't forget to flush!
}
