const std = @import("std");
const clap = @import("clap");

const Color = enum {
    green,
    yellow,
};

const printParams = struct {
    binary: bool = false,
    num_columns: usize = 16,
    group_size: usize = 2,
    stop_after: usize = undefined,
    position_offset: usize = 0,
    postscript: bool = false,
    decimal: bool = false,
    start_at: usize = 0,
    upper_case: bool = false,
    line_length: usize = undefined,
    colorize: bool = true,
};

fn colorize(writer: anytype, color: Color) !void {
    //                                         bold ----\ green ---\
    if (color == Color.green) try writer.print("\u{001b}[1m\u{001b}[32m", .{});
    //                                          bold ----\ yellow --\
    if (color == Color.yellow) try writer.print("\u{001b}[1m\u{001b}[33m", .{});
}

fn uncolor(writer: anytype) !void {
    try writer.print("\u{001b}[0m", .{});
}

fn print_columns(writer: anytype, params: printParams, input: []const u8) !usize {
    // amount of bytes converted into hex
    var num_printed_bytes: usize = 0;
    // number of printed characters of translated input (not including the
    // index markers on the left!)
    var num_printed_chars: usize = 0;
    // number of spaces for lining up the ascii characters in the final row
    var num_spaces: usize = 0;

    for (input, 0..) |character, index| {
        if (params.binary) {
            // no color for binary ouput - this is what xxd does as well
            try writer.print("{b:0>8}", .{character});
            num_printed_chars += 8;
        } else {
            // handle colors. if the character is not a printable ascii char,
            // it should be printed in yellow. otherwise green
            if ((character < 32 or character > 126) and params.colorize) {
                try colorize(writer, Color.yellow);
            } else if (params.colorize) {
                try colorize(writer, Color.green);
            }
            // print the hex value of the current character
            if (params.upper_case) {
                try writer.print("{X:0>2}", .{character});
            } else {
                try writer.print("{x:0>2}", .{character});
            }
            num_printed_chars += 2;
            if (params.colorize) try uncolor(writer); // reset color
        }
        num_printed_bytes += 1;
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
    // if it's the last part of the input, we need to line up the ascii text
    // with the previous columns
    if (num_printed_bytes != params.num_columns) {
        num_spaces += params.line_length - num_printed_chars;

        for (0..num_spaces) |_| {
            try writer.print(" ", .{});
        }
    }
    // add an extra space to copy xxd
    try writer.print(" ", .{});
    // print the content of the line as ascii characters
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
    return num_printed_bytes;
}

fn print_output(writer: anytype, params: printParams, input: []const u8) !void {
    // define how much of the input to print
    var length = input.len;
    if (params.stop_after != 0) length = params.stop_after;

    // this variable is used to print the file position information for a row
    var file_pos: usize = params.position_offset + params.start_at;

    // if the user asked for plain dump, just dump everything no formatting
    if (params.postscript) {
        for (input[params.start_at..length]) |character| {
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

    // specify what parameters our program can take via clap
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit
        \\-b                      Binary digit dump, default is hex
        \\-c, --columns <INT>     Write <INT> per line, default is 16
        \\-g, --groupsize <INT>   Group the output in <INT> bytes, default 2
        \\    --string <STR>      Optional input string (ignores FILENAME)
        \\-l, --len <INT>         Stop writing after <INT> bytes 
        \\-o, --off <INT>         Add an offset to the displayed file position
        \\-p                      Plain dump, no formatting
        \\-d                      Show offset in decimal and not hex
        \\-s, --seek <INT>        Start at <INT> bytes absolute
        \\-u                      Use upper-case hex letters, default is lower-case
        \\-R                      Disable color output
        \\<FILENAME>
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
        // Report useful error and exit.
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // if -h or --help is passed in, print usage text, help text, then quit
    if (res.args.help != 0) {
        const usage_notes =
            \\Usage:
            \\    xxd-zig [options] [filename]
            \\
            \\    If --string is not set and a filename not given,
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

    var print_params = printParams{};

    // setting to binary output also changes other parameters to reasonable
    // values (this can be overridden)
    if (res.args.b != 0) {
        print_params.binary = true;
        print_params.group_size = 1;
        print_params.num_columns = 6;
    }

    if (res.args.columns) |c| print_params.num_columns = c;

    if (res.args.groupsize) |g| print_params.group_size = g;

    if (res.args.len) |l| print_params.stop_after = l;

    if (res.args.off) |o| print_params.position_offset = o;

    if (res.args.p != 0) print_params.postscript = true;

    if (res.args.d != 0) print_params.decimal = true;

    if (res.args.seek) |s| print_params.start_at = s;

    if (res.args.u != 0) print_params.upper_case = true;

    if (res.args.R != 0) print_params.colorize = false;

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
        try print_output(stdout, print_params, s);
    } else if (res.positionals.len > 0) { //from an input file
        // interpret the filepath
        var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path = try std.fs.realpath(res.positionals[0], &path_buffer);

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

        try print_output(stdout, print_params, stdin_contents);
    }
    try bw.flush(); // don't forget to flush!
}
