const std = @import("std");
const clap = @import("clap");

const printParams = struct {
    line_length: usize = undefined,
    num_columns: usize = 16,
    group_size: usize = 2,
};

fn print_output(writer: anytype, params: printParams, input: []const u8) !void {

    // where in the input does the line start
    var line_start_position: usize = 0;
    // number of printed characters of translated input (not including the
    // index markers on the left!)
    var num_printed_chars: usize = 0;

    for (input, 0..) |character, index| {
        // check to see if we are at the end of a column (or at the very first
        // character of the input)
        if (index % params.num_columns == 0) {
            // if so, print a space and then the slice of the string the
            // columns on the line represent
            try writer.print("  {s}\n", .{input[line_start_position..index]});
            line_start_position = index;
            num_printed_chars = 0;
            // add the index for the next line
            try writer.print("{x:0>8}:", .{index});
        }
        // if we are at the end of a group, add a space
        if (index % params.group_size == 0) {
            try writer.print(" ", .{});
            num_printed_chars += 1;
        }
        // if we are at the end of the input
        if (index == input.len - 1) {
            // figure out how many spaces to put in so that the text lines up
            // nicely
            const num_spaces: usize = 1 + params.line_length - num_printed_chars;
            for (0..num_spaces) |_| {
                try writer.print(" ", .{});
            }
            try writer.print(" {s}\n", .{input[line_start_position..]});
            break;
        }
        // print the hex value of the current character
        try writer.print("{x}", .{character});
        num_printed_chars += 2;
    }
}

pub fn main() !void {
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-c, --columns <usize>   Format <columns> per line, default is 16, max 256
        \\-g, --groupsize <usize> Separate the output of in <groupsize> bytes, default 2
        \\-s, --string <str>      An option parameter which can be specified multiple times.
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

    // printing the passed arguments for debugging
    if (res.args.help != 0) {
        std.debug.print("--help\n", .{});
    }
    if (res.args.columns) |c| {
        std.debug.print("--columns = {d}\n", .{c});
    }
    if (res.args.groupsize) |g| {
        std.debug.print("--groupsize = {d}\n", .{g});
    }
    if (res.args.string) |s| {
        std.debug.print("--string = {s}\n", .{s});
    }

    // store details about how we are printing in this struct
    var current_print_params = printParams{};
    // setting the number of columns to use when printing (default 16)
    if (res.args.columns) |c| {
        current_print_params.num_columns = c;
    }
    // setting the output grouping when printing (default 2)
    if (res.args.groupsize) |g| {
        current_print_params.group_size = g;
    }
    current_print_params.line_length =
        ((current_print_params.group_size * 2) + 1) *
        (current_print_params.num_columns / current_print_params.group_size);

    // if we have an input, print it using the specified parameters
    if (res.args.string) |s| {
        try print_output(stdout, current_print_params, s);
    }

    try bw.flush(); // don't forget to flush!
}