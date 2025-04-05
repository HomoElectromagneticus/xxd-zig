const std = @import("std");
const clap = @import("clap");

const Color = enum {
    green,
    yellow,
};

const printParams = struct {
    binary: bool = false,
    num_columns: usize = 16,
    little_endian: bool = false,
    group_size: usize = 2,
    stop_after: usize = undefined,
    position_offset: usize = 0,
    postscript: bool = false,
    decimal: bool = false,
    start_at: usize = 0,
    upper_case: bool = false,
    line_length: usize = undefined,
    colorize: bool = true,
    c_style: bool = false,
    c_style_name: []const u8 = "",
};

// this will only work on linux or MacOS. for windows users, it will simply
// always return 80
fn get_terminal_width(terminal_handle: std.posix.fd_t) usize {
    var winsize: std.posix.system.winsize = undefined;
    const errno = std.posix.system.ioctl(
        terminal_handle,
        std.posix.T.IOCGWINSZ,
        @intFromPtr(&winsize),
    );
    if (std.posix.errno(errno) == .SUCCESS) {
        return winsize.col;
    } else {
        return 80;
    }
}

// colorize the terminal output
fn colorize(writer: anytype, color: Color) !void {
    //                                         bold ----\ green ---\
    if (color == Color.green) try writer.print("\u{001b}[1m\u{001b}[32m", .{});
    //                                          bold ----\ yellow --\
    if (color == Color.yellow) try writer.print("\u{001b}[1m\u{001b}[33m", .{});
}

// tell the terminal to go back to standard color
fn uncolor(writer: anytype) !void {
    try writer.print("\u{001b}[0m", .{});
}

fn print_columns(writer: anytype, params: printParams, input: []const u8) !usize {
    // number of printed characters of translated input (not including the
    // index markers on the left!)
    var num_printed_chars: usize = 0;
    // number of spaces for lining up the ascii characters in the final row
    var num_spaces: usize = 0;

    // split the input into groups, where the size is determined by the print
    // parameters
    var groups_iterator = std.mem.window(
        u8,
        input,
        params.group_size,
        params.group_size,
    );

    while (groups_iterator.next()) |group| {
        // in case the last group during a little-endian dump is not full, add
        // extra spaces
        if ((params.little_endian) and (group.len < params.group_size)) {
            const delta: usize = 2 * (params.group_size - group.len);
            for (0..delta) |_| {
                try writer.print(" ", .{});
                num_printed_chars += 1;
            }
        }
        for (0..group.len) |idx| {
            var i: usize = idx;
            // if we are doing a little-endian dump, we need to print the
            // values in the group backwards
            if (params.little_endian) i = group.len - (idx + 1);

            if (params.binary) {
                // no color for binary ouput - this is what xxd does as well
                try writer.print("{b:0>8}", .{group[i]});
                num_printed_chars += 8;
            } else {
                // handle colors. if the character is not a printable ascii
                // char, it should be printed in yellow. otherwise green
                if ((group[i] < 32 or group[i] > 126) and params.colorize) {
                    try colorize(writer, Color.yellow);
                } else if (params.colorize) {
                    try colorize(writer, Color.green);
                }
                // print the hex value of the current character
                if (params.upper_case) {
                    try writer.print("{X:0>2}", .{group[i]});
                } else {
                    try writer.print("{x:0>2}", .{group[i]});
                }
                if (params.colorize) try uncolor(writer); // reset color
                num_printed_chars += 2;
            }
        }
        // at the end of a group, add a space
        try writer.print(" ", .{});
        num_printed_chars += 1;
    }

    // if it's the last part of the input, we need to line up the ascii text
    // with the previous columns
    if (input.len < params.num_columns) {
        num_spaces += params.line_length -| num_printed_chars;

        // when the number of columns is not evenly divisible by the group
        // size, we need an extra space or the ASCII won't line up right
        if (params.num_columns % params.group_size != 0) num_spaces += 1;

        for (0..num_spaces) |_| {
            try writer.print(" ", .{});
        }
    }
    // add an extra space to copy xxd
    try writer.print(" ", .{});
    return input.len;
}

// for the ascii output on the right-hand-side
fn print_ascii(writer: anytype, params: printParams, input: []const u8) !void {
    for (input) |raw_char| {
        // handle color
        if (params.colorize) try colorize(writer, Color.green);
        // printable ascii characters are all within 32 to 176. every other
        // character should be a "." as xxd does it
        if (raw_char >= 32 and raw_char <= 126) {
            try writer.print("{c}", .{raw_char});
        } else {
            if (params.colorize) try colorize(writer, Color.yellow);
            try writer.print(".", .{});
        }
        if (params.colorize) try uncolor(writer); //turn off color
    }
}

fn print_plain_dump(writer: anytype, params: printParams, input: []const u8) !void {
    for (input) |character| {
        if (params.binary) {
            try writer.print("{b:0>8}", .{character});
        } else {
            if (params.upper_case) {
                try writer.print("{X:0>2}", .{character});
            } else {
                try writer.print("{x:0>2}", .{character});
            }
        }
    }
    try writer.print("\n", .{});
}

fn print_c_inc_style(writer: anytype, params: printParams, input: []const u8) !void {
    try writer.print("unsigned char {s}[] = {{\n  ", .{params.c_style_name});
    for (input, 0..) |character, index| {
        // handle linebreaks and the indenting to look like xxd
        if (index % (params.num_columns) == 0 and index != 0) {
            try writer.print("\n  ", .{});
        }
        if (params.binary) {
            try writer.print("0b{b:0>8}, ", .{character});
        } else {
            if (params.upper_case) {
                try writer.print("0x{X:0>2}, ", .{character});
            } else {
                try writer.print("0x{x:0>2}, ", .{character});
            }
        }
    }
    try writer.print("\n}};\nunsigned int {s}_len = {d};\n", .{ params.c_style_name, input.len });
}

fn print_output(writer: anytype, params: printParams, input: []const u8) !void {
    // define how much of the input to print
    var length = input.len;
    if (params.stop_after != 0) length = params.stop_after;

    // this variable is used to print the file position information for a row
    var file_pos: usize = params.position_offset + params.start_at;

    // if the user asked for plain dump, just dump everything no formatting
    if (params.postscript) {
        try print_plain_dump(
            writer,
            params,
            input[params.start_at..length],
        );
        return;
    }

    // if the user asked for a c import style ouput, use that function
    if (params.c_style) {
        try print_c_inc_style(
            writer,
            params,
            input[params.start_at..length],
        );
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
            try writer.print("{d:0>8}: ", .{file_pos});
        } else {
            try writer.print("{x:0>8}: ", .{file_pos});
        }
        file_pos += try print_columns(writer, params, slice);
        try print_ascii(writer, params, slice);
        try writer.print("\n", .{});
    }
}

pub fn main() !void {
    // stdout is for the actual output of the application
    const stdout_file = std.io.getStdOut();
    var bw = std.io.bufferedWriter(stdout_file.writer());
    const stdout = bw.writer();

    // stdin is for the actual input of the appplication
    const stdin = std.io.getStdIn().reader();

    // need to allocate memory in order to parse the command-line args, handle
    // buffers, etc
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // usage notes that will get print with the help text
    const usage_notes =
        \\xxd-zig creates a hex dump of a given file or standard input
        \\Usage:
        \\    xxd-zig <options> <filename>
        \\
        \\    If --string is not set and a filename not given, the
        \\    program will read from stdin. If more than one filename
        \\    is passed in, only the first will be considered.
        \\
        \\Options:
    ;

    // specify what parameters our program can take via clap
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit
        \\-b, --binary            Binary digit dump, default is hex
        \\-c, --columns <INT>     Dump <INT> per line, default 16
        \\-e                      Little-endian dump (default big-endian)
        \\-g <INT>                Group the output in <INT> bytes, default 2
        \\    --string <STR>      Optional input string (ignores FILENAME)
        \\-i                      Output in C include file style
        \\-n <STR>                Set the variable name for C include output (-i) 
        \\-l, --len <INT>         Stop writing after <INT> bytes 
        \\-o, --offset <INT>      Add an offset to the displayed file position
        \\-p                      Plain dump, no formatting
        \\-d                      Show offset in decimal and not in hex
        \\-s, --seek <INT>        Start at <INT> bytes absolute
        \\-u                      Use upper-case hex letters, default is lower
        \\-R                      Disable color output
        \\<FILENAME>              Path of file to convert to hex
    );

    // custom parsing to enable the argument strings for the help text to be
    // more easy to interpret for the user
    const parsers = comptime .{
        .STR = clap.parsers.string,
        .INT = clap.parsers.int(usize, 10),
        .FILENAME = clap.parsers.string,
    };

    // initialize the clap diagnostics, used for reporting errors. is optional
    var diag = clap.Diagnostic{};
    // parse the command-line arguments
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        // if the user entered a strange option
        if (err == error.InvalidArgument) {
            try stdout.print("Invalid argument! Try passing in '-h'.\n", .{});
            try bw.flush();
            return;
            // report useful error and exit
        } else {
            diag.report(std.io.getStdErr().writer(), err) catch {};
            return err;
        }
    };
    defer res.deinit();

    // if -h or --help is passed in, print usage text, help text, then quit
    if (res.args.help != 0) {
        try stdout.print("{s}\n", .{usage_notes});
        try bw.flush();
        const help_options = clap.HelpOptions{
            .description_on_new_line = false,
            .description_indent = 0,
            .max_width = get_terminal_width(std.io.getStdOut().handle),
            .spacing_between_parameters = 0,
        };
        return clap.help(
            std.io.getStdErr().writer(),
            clap.Help,
            &params,
            help_options,
        );
    }

    var print_params = printParams{};

    // setting to binary output also changes other parameters to reasonable
    // values (this can be overridden)
    if (res.args.binary != 0) {
        print_params.binary = true;
        print_params.group_size = 1;
        print_params.num_columns = 6;
    }

    // setting to c import style output also changes other parameters to
    // reasonable values (this can be overridden)
    if (res.args.i != 0) {
        print_params.c_style = true;
        print_params.num_columns = 12;
    }

    if (res.args.n) |n| print_params.c_style_name = n;

    if (res.args.columns) |c| print_params.num_columns = c;

    if (res.args.g) |g| print_params.group_size = g;

    if (res.args.len) |l| print_params.stop_after = l;

    if (res.args.offset) |o| print_params.position_offset = o;

    if (res.args.p != 0) print_params.postscript = true;

    if (res.args.d != 0) print_params.decimal = true;

    if (res.args.seek) |s| print_params.start_at = s;

    if (res.args.u != 0) print_params.upper_case = true;

    if ((res.args.R != 0) or !(std.fs.File.isTty(stdout_file))) {
        print_params.colorize = false;
    }

    if (res.args.e != 0) print_params.little_endian = true;

    // the printed line length - useful for ensuring nice text alignment
    if (print_params.binary == false) {
        print_params.line_length = (print_params.num_columns * 2) +
            (print_params.num_columns / print_params.group_size);
        if (print_params.num_columns % 2 != 0) print_params.line_length += 1;
    } else {
        print_params.line_length = (print_params.num_columns * 8) +
            (print_params.num_columns / print_params.group_size);
        if (print_params.num_columns % 2 != 0 and print_params.group_size != 1) {
            print_params.line_length += 1;
        }
    }

    // choose how to print the output based on where the input comes from
    if (res.args.string) |s| { //from an input string
        // just use "string" for the c import style name in this input case if
        // the name is not set via the "-n" option
        if (print_params.c_style_name.len == 0) print_params.c_style_name = "string";

        try print_output(stdout, print_params, s);
    } else if (res.positionals[0]) |positional| { //from an input file
        // interpret the filepath
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fs.realpath(positional, &path_buffer);

        // define the c sytle import name from the file path if it's not set by
        // the user via the "-n" option
        if (print_params.c_style_name.len == 0) print_params.c_style_name = positional;

        // load the file into memory in a single allocation
        const file_contents = try std.fs.cwd().readFileAlloc(
            gpa.allocator(),
            path,
            std.math.maxInt(usize),
        );
        defer gpa.allocator().free(file_contents);

        try print_output(stdout, print_params, file_contents);
    } else { //from stdin
        // we'll need to allocate memory since we don't know the size of what's
        // coming from stdin at compile time
        const stdin_contents = try stdin.readAllAlloc(gpa.allocator(), std.math.maxInt(usize));
        defer gpa.allocator().free(stdin_contents);

        // just use "stdin" for the c import style name in this input case (if
        // it's not set by the user via the "-n" option)
        if (print_params.c_style_name.len == 0) print_params.c_style_name = "stdin";

        try print_output(stdout, print_params, stdin_contents);
    }
    try bw.flush(); // don't forget to flush!
}
