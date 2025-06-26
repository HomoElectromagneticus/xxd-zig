const std = @import("std");
const clap = @import("clap");
const lib = @import("lib.zig");

const rev_modes_msg =
    \\
    \\xxd-zig: Error while parsing the dump in reverse mode! This could
    \\         be because the arguments used to make the dump do not match
    \\         those used to reverse the dump (-b for binary, -a for 
    \\         autoskip, etc).
    \\
;

const rev_invalid_char_msg =
    \\
    \\xxd-zig: Caught an invalid character while reversing dump. Aborting...
    \\
;

const rev_nothing_printed_msg =
    \\xxd-zig: Nothing was printed while running in reverse mode! This
    \\         could be because you chose the wrong options for the data.
    \\         Try passing in -h for for help.
    \\
;

const rev_input_string_msg =
    \\xxd-zig: Reverse mode for an input string is not allowed.
    \\
;

const no_plain_autoskip_msg =
    \\xxd-zig: Cannot use autoskip when doing a "plain" postscript dump.
    \\
;

const no_c_autoskip_msg =
    \\xxd-zig: Cannot use autoskip when doing a C include style dump.
    \\
;

const no_index_msg =
    \\xxd-zig: There is no index in this mode, the -d option has no effect.
    \\
;

const incompatible_dump_type_msg =
    \\zig-xxd: Sorry, cannot revert this type of hexdump.
    \\
;

// only works on linux & MacOS. on windows, it will simply always return 80
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

    // usage notes that will get printed with the help text
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
        \\-a                      Toggle autoskip: A '*' replaces null lines
        \\-b, --binary            Binary digit dump, default is hex
        \\-C                      Capitalise variable names in C include file style (-i)
        \\-c, --columns <INT>     Dump <INT> per line, default 16
        \\-d                      Show offset in decimal and not in hex
        \\-e                      Little-endian dump (default big-endian)
        \\-g <INT>                Group the output in <INT> bytes, default 2
        \\-h, --help              Display this help and exit
        \\-i                      Output in C include file style
        \\-l, --len <INT>         Stop writing after <INT> bytes 
        \\-n <STR>                Set the variable name for C include file style (-i) 
        \\-o, --offset <INT>      Add an offset to the displayed file position
        \\-p                      Plain dump, no formatting
        \\-r                      Reverse mode: convert dump into binary
        \\-s, --seek <INT>        Start at <INT> bytes absolute
        \\    --string <STR>      Optional input string (ignores FILENAME and stdin)
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
    var clap_diag = clap.Diagnostic{};
    // parse the command-line arguments
    const res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &clap_diag,
        .allocator = arena.allocator(),
    }) catch |err| {
        // if the user entered a strange option or argument, let them know
        if (err == error.InvalidArgument) {
            try stderr.writeAll("Invalid option! Try passing in '-h' for help.\n");
            return 1;
        } else if (err == error.InvalidCharacter) {
            try stderr.writeAll("Invalid option argument! Try passing in '-h' for help.\n");
            return 1;
        } else {
            // report (semi) useful error and exit
            try clap_diag.report(std.io.getStdErr().writer(), err);
            return err;
        }
    };

    // if -h or --help is passed in, print usage text, help text, then quit
    if (res.args.help != 0) {
        try stdout_buf.print("{s}\n", .{usage_notes});
        try bw.flush();
        const help_options = clap.HelpOptions{
            .description_on_new_line = false,
            .description_indent = 0,
            .max_width = get_terminal_width(std.io.getStdOut().handle),
            .spacing_between_parameters = 0,
        };
        try clap.help(
            std.io.getStdErr().writer(),
            clap.Help,
            &params,
            help_options,
        );
        return 0;
    }

    var print_params = lib.printParams{};

    // get the system page size to know how much to read at a time of the input
    print_params.page_size = std.heap.pageSize();

    if (res.args.a != 0) print_params.autoskip = true;

    // setting the mode to plain dump (called postscript in the original xxd)
    // also changes other parameters (which can be overriden)
    if (res.args.p != 0) {
        print_params.postscript = true;
        print_params.num_columns = 30;
        // you cannot use autoskip for plain dumps, as the lack of an index
        // will cause the dump to be irreversable
        if (res.args.a != 0) {
            try stderr.writeAll(no_plain_autoskip_msg);
            return 1;
        }
    }

    // setting to c import style output also changes other parameters to
    // reasonable values (this can also be overridden)
    if (res.args.i != 0) {
        print_params.c_style = true;
        print_params.num_columns = 12;
        // you cannot use autoskip for c-include dumps, as the lack of an index
        // will cause the dump to be irreversable
        if (res.args.a != 0) {
            try stderr.writeAll(no_c_autoskip_msg);
            return 1;
        }
        // there is no index in c-include mode, so this would do nothing
        if (res.args.p != 0) {
            try stderr.writeAll("xxd-zig: Incompatible modes! Try -h for help.\n");
            return 1;
        }
    }

    // setting to binary output also changes other parameters to reasonable
    // values (this can be overridden by the user passing in other options)
    if (res.args.binary != 0) {
        print_params.binary = true;
        print_params.group_size = 1;
        print_params.num_columns = 6;
    }

    if (res.args.C != 0) print_params.c_style_capitalise = true;

    if (res.args.columns) |c| print_params.num_columns = c;

    if (res.args.d != 0) {
        print_params.decimal = true;
        // there is no index in plain postscript mode, so this would do nothing
        if (res.args.p != 0) {
            try stderr.writeAll(no_index_msg);
            return 1;
        }
    }

    if (res.args.e != 0) print_params.little_endian = true;

    if (res.args.g) |g| print_params.group_size = g;

    if (res.args.len) |l| print_params.stop_after = l;

    if (res.args.n) |n| print_params.c_style_name = n;

    if (res.args.offset) |o| print_params.position_offset = o;

    if (res.args.seek) |s| print_params.start_at = s;

    if (res.args.u != 0) print_params.upper_case = true;

    // turn off colorize if the user chooses, or if the output is not a terminal
    if ((res.args.R != 0) or !(std.fs.File.isTty(stdout_file))) {
        print_params.colorize = false;
    }

    if (res.args.r != 0) {
        // the original can't reverse little-endian or c-inlude style dumps either
        if (print_params.little_endian or print_params.c_style) {
            try stderr.writeAll(incompatible_dump_type_msg);
            return 1;
        }
        print_params.reverse = true;
    }

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

    // initialize the diagnostic (for telling the user where in the source data
    // the program ran into an error)
    var diag = lib.Diagnostic{};

    // handle the special case of the string input
    if (res.args.string) |s| {
        // reverse mode for an input string is not allowed. this is kind of a
        // nonsensical use case
        if (print_params.reverse) {
            try stderr.writeAll(rev_input_string_msg);
            return 1;
        }
        // get a stream into the input string (needed to get a reader)
        var input_string_stream = std.io.fixedBufferStream(s);

        // print the output
        lib.print_output(
            stdout_buf,
            &print_params,
            arena.allocator(),
            input_string_stream.reader(),
        ) catch |err| {
            try stderr.print("xxd-zig: Error dumping - {s}\n", .{@errorName(err)});
            return 1;
        };
        try bw.flush(); // don't forget to flush!
        return 0;
    }

    // get a file handle to the input (stdin or a file)
    const file = blk: {
        if (res.positionals[0]) |path_string| {
            // define the c sytle import name from the file path if it's not
            // set by the user via the "-n" option
            if (print_params.c_style_name.len == 0) {
                print_params.c_style_name = path_string;
            }
            // get the file
            const file = std.fs.cwd().openFile(
                path_string,
                .{ .mode = .read_only },
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
            break :blk file;
        } else {
            const file = std.io.getStdIn();
            break :blk file;
        }
    };
    defer file.close(); // make sure the file closes at the end

    if (print_params.reverse) {
        lib.reverse_input(
            stdout_buf,
            &print_params,
            arena.allocator(),
            file.reader(),
            &diag,
        ) catch |err| {
            switch (err) {
                error.EndOfStream => {
                    try stderr.print("\nxxd-zig: No line break found after reading {d} bytes! Is the input really a hex dump?", .{print_params.page_size});
                },
                error.DumpParseError => {
                    try bw.flush(); // flush stdout before writing to stderr
                    try stderr.print("\nxxd-zig: Parsing error at line {d}.", .{diag.line_number});
                    try stderr.writeAll(rev_modes_msg);
                },
                error.InvalidCharacter => {
                    try bw.flush(); // flush stdout before writing to stderr
                    try stderr.print("\nxxd-zig: Invalid character on line {d}.", .{diag.line_number});
                    try stderr.writeAll(rev_invalid_char_msg);
                },
                error.NothingWritten => {
                    try bw.flush(); // flush stdout before writing to stderr
                    try stderr.writeAll(rev_nothing_printed_msg);
                },
                else => try stderr.print("xxd-zig: Error reversing dump - {s}\n", .{@errorName(err)}),
            }
            return 1;
        };
    } else {
        lib.print_output(
            stdout_buf,
            &print_params,
            arena.allocator(),
            file.reader(),
        ) catch |err| {
            try stderr.print("xxd-zig: Error dumping - {s}\n", .{@errorName(err)});
            return 1;
        };
    }
    try bw.flush(); // don't forget to flush!
    return 0;
}
