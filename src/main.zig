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
        // if we are at the end of a group, add a space
        if (index % params.group_size == 0) {
            try writer.print(" ", .{});
            num_printed_chars += 1;
        }
        // check to see if we are at the end of a column (or at the very first
        // character of the input)
        if (index % params.num_columns == 0) {
            // if so, print the slice of the string the columns on the line
            // represent
            for (input[line_start_position..index]) |raw_char| {
                if ('\n' == raw_char or '\t' == raw_char) {
                    try writer.print(".", .{});
                } else {
                    try writer.print("{c}", .{raw_char});
                }
            }
            try writer.print("\n", .{});
            line_start_position = index;
            num_printed_chars = 0;
            // add the index for the next line
            try writer.print("{x:0>8}: ", .{index});
        }
        // print the hex value of the current character
        try writer.print("{x:0>2}", .{character});
        num_printed_chars += 2;

        // if we are at the end of the input
        if (index == input.len - 1) {
            // figure out how many spaces to put in so that the text lines up
            // nicely
            const num_spaces: usize = params.line_length - num_printed_chars;
            for (0..num_spaces) |_| {
                try writer.print(" ", .{});
            }

            for (input[line_start_position..]) |raw_char| {
                if ('\n' == raw_char or '\t' == raw_char) {
                    try writer.print(".", .{});
                } else {
                    try writer.print("{c}", .{raw_char});
                }
            }
            try writer.print("\n", .{});
            break;
        }
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
        \\-s, --string <str>      Optional input string
        \\-f, --file <str>        Optional input file
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

    // if we have a simple input string, print it using the spec'd parameters
    if (res.args.string) |s| {
        try print_output(stdout, current_print_params, s);
    }

    // if we have an input file, we need to allocate memory, read in the file,
    // and finally print it according the specified parameters
    if (res.args.file) |f| {
        // try to open the specified file
        const input_file = try std.fs.cwd().openFile(f, .{});
        defer input_file.close();
        // allocate memory to store the file's raw data
        const input_file_data = try input_file.readToEndAlloc(gpa.allocator(), 128);
        defer gpa.allocator().free(input_file_data);
        // try to print the hex using the spec'd parameters
        try print_output(stdout, current_print_params, input_file_data);
    }

    try bw.flush(); // don't forget to flush!
}
