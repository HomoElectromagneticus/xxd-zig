const std = @import("std");

pub const Diagnostic = struct {
    line_number: usize = undefined,
};

const Color = enum {
    green,
    yellow,
    white,
    red,
};

pub const printParams = struct {
    autoskip: bool = false,
    binary: bool = false,
    c_style_capitalise: bool = false,
    num_columns: usize = 16,
    decimal: bool = false,
    little_endian: bool = false,
    group_size: usize = 2,
    c_style: bool = false,
    stop_after: usize = undefined,
    c_style_name: []const u8 = undefined,
    position_offset: usize = 0,
    postscript: bool = false,
    reverse: bool = false,
    start_at: usize = 0,
    upper_case: bool = false,
    line_length: usize = undefined,
    colorize: bool = true,
    page_size: usize = undefined,
};

// look-up-tables for byte-to-hex conversion
const hexCharsetUpper = "0123456789ABCDEF";
const hexCharsetLower = "0123456789abcdef";

// use a look-up-table to convert the input data into hex (is much faster than
// the zig standard library's format function)
fn byte_to_hex_string(input: u8, params: *printParams) [2]u8 {
    var output_string: [2]u8 = undefined;
    // pick the LUT depending on the user's choice of upper or lower case
    if (params.upper_case) {
        output_string[0] = hexCharsetUpper[@as(usize, input >> 4) & 0x0F];
        output_string[1] = hexCharsetUpper[@as(usize, input) & 0x0F];
    } else {
        output_string[0] = hexCharsetLower[@as(usize, input >> 4) & 0x0F];
        output_string[1] = hexCharsetLower[@as(usize, input) & 0x0F];
    }
    return output_string;
}

test "confirm upper case hex convertion works" {
    const test_char = 'L';
    var print_params = printParams{ .upper_case = true };
    try std.testing.expect(std.mem.eql(
        u8,
        &byte_to_hex_string(test_char, &print_params),
        "4C",
    ));
}

test "confirm lower case hex convertion works" {
    const test_char = 'm';
    var print_params = printParams{ .upper_case = false };
    try std.testing.expect(std.mem.eql(
        u8,
        &byte_to_hex_string(test_char, &print_params),
        "6d",
    ));
}

// look-up-table for the byte-to-binary conversion (built during compilation)
const binCharset: [256][]const u8 = blk: {
    var temp: [256][]const u8 = undefined;
    for (0..256) |value| {
        temp[value] = std.fmt.comptimePrint("{b:0>8}", .{value});
    }
    break :blk temp;
};

test "confirm binary string LUT is correct for zero" {
    const test_value: u8 = 0;
    try std.testing.expectEqualStrings(
        "00000000",
        binCharset[test_value],
    );
}

test "confirm binary string LUT is correct for 0x10" {
    const test_value: u8 = 0x10;
    try std.testing.expectEqualStrings(
        "00010000",
        binCharset[test_value],
    );
}

test "confirm binary string LUT is correct for 0xff" {
    const test_value: u8 = 0xff;
    try std.testing.expectEqualStrings(
        "11111111",
        binCharset[test_value],
    );
}

// colorize the terminal output
fn colorize(writer: anytype, color: Color) !void {
    switch (color) {
        //                                   bold ----\  green --\
        Color.green => try writer.writeAll("\u{001b}[1m\u{001b}[32m"),
        //                                   bold -----\ yellow --\
        Color.yellow => try writer.writeAll("\u{001b}[1m\u{001b}[33m"),
        //                                   bold ----\  white --\
        Color.white => try writer.writeAll("\u{001b}[1m\u{001b}[37m"),
        //                                   bold --\    red --\
        Color.red => try writer.writeAll("\u{001b}[1m\u{001b}[31m"),
    }
}

// tell the terminal to go back to standard color
fn uncolor(writer: anytype) !void {
    try writer.writeAll("\u{001b}[0m");
}

fn print_columns(writer: anytype, params: *printParams, input: []const u8) !usize {
    // number of printed characters of dumped input (not including the index
    // markers on the left!)
    var num_printed_chars: usize = 0;
    // number of spaces for lining up the ASCII characters in the final row
    var num_spaces: usize = 0;

    // split the input into groups, where size is given by the print parameters
    var groups_iterator = std.mem.window(
        u8,
        input,
        params.group_size,
        params.group_size,
    );

    while (groups_iterator.next()) |group| {
        // if the last group for a little-endian dump is not full, add extra
        // spaces for perfect alignment
        if ((params.little_endian) and (group.len < params.group_size)) {
            const delta: usize = 2 * (params.group_size - group.len);
            for (0..delta) |_| {
                num_printed_chars += try writer.write(" ");
            }
        }
        for (0..group.len) |idx| {
            var i: usize = idx;
            // if we are doing a little-endian dump, we need to print the
            // values in the group backwards
            if (params.little_endian) i = group.len - (idx + 1);

            if (params.binary) {
                // no color for binary ouput - this is what xxd does as well
                num_printed_chars += try writer.write(binCharset[group[i]]);
            } else {
                if (params.colorize) {
                    switch (group[i]) {
                        // null bytes should be white
                        0 => try colorize(writer, Color.white),
                        // printable ASCII characters should be green
                        32...126 => try colorize(writer, Color.green),
                        // values over 0x7F should be red
                        127...255 => try colorize(writer, Color.red),
                        // everything else should be yellow
                        else => try colorize(writer, Color.yellow),
                    }
                }
                // print the hex value of the character (no need for print()'s
                // formatting, we can write directly to stdout or the file)
                num_printed_chars += try writer.write(&byte_to_hex_string(group[i], params));
            }
        }
        // at the end of a group, add a space
        num_printed_chars += try writer.write(" ");
    }

    // if it's the last part of the input, we need to line up the ASCII text
    // with the previous columns
    if (input.len < params.num_columns) {
        num_spaces += params.line_length -| num_printed_chars;

        // when the number of columns is not evenly divisible by the group
        // size, we need an extra space or the ASCII won't line up right
        if (params.num_columns % params.group_size != 0) num_spaces += 1;

        for (0..num_spaces) |_| try writer.writeAll(" ");
    }
    // add an extra space to copy xxd (also helps decoding reverse dumps)
    try writer.writeAll(" ");
    return input.len;
}

test "validate non-colorised lower-case hex output" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    var print_params = printParams{
        .colorize = false,
        .upper_case = false,
        .num_columns = 4,
    };
    const test_input = [_]u8{ 'A', 0, '0', '*' };
    _ = try print_columns(
        list.writer(),
        &print_params,
        &test_input,
    );
    //                         extra space added in order to match xxd ----\
    //                                    space from the end of a group --\\
    try std.testing.expect(std.mem.eql(u8, list.items, "4100 302a  "));
}

test "validate non-colorised upper-case hex output" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    var print_params = printParams{
        .colorize = false,
        .upper_case = true,
        .num_columns = 4,
    };
    const test_input = [_]u8{ '-', 127, '1', '*' };
    _ = try print_columns(
        list.writer(),
        &print_params,
        &test_input,
    );
    //                         extra space added in order to match xxd ----\
    //                                    space from the end of a group --\\
    try std.testing.expect(std.mem.eql(u8, list.items, "2D7F 312A  "));
}

test "validate non-colorised little-endian lower-case hex output" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    var print_params = printParams{
        .colorize = false,
        .num_columns = 4,
        .little_endian = true,
    };
    const test_input = [_]u8{ '-', 127, '1', '*' };
    _ = try print_columns(
        list.writer(),
        &print_params,
        &test_input,
    );
    //                         extra space added in order to match xxd ----\
    //                                    space from the end of a group --\\
    try std.testing.expect(std.mem.eql(u8, list.items, "7f2d 2a31  "));
}

// for the ASCII output on the right-hand-side
fn print_ascii(writer: anytype, params: *printParams, input: []const u8) !void {
    for (input) |raw_char| {
        // handle color
        if (params.colorize) {
            switch (raw_char) {
                0 => try colorize(writer, Color.white),
                32...126 => try colorize(writer, Color.green),
                127...255 => try colorize(writer, Color.red),
                else => try colorize(writer, Color.yellow),
            }
        }
        // actual character output (with non-printable characters as '.')
        switch (raw_char) {
            32...126 => try writer.writeByte(raw_char),
            else => try writer.writeByte('.'),
        }
    }
}

test "validate non-colorised ASCII output" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    var print_params = printParams{ .colorize = false };
    const test_input = [_]u8{ 'A', 'b', '0', '1', 16, '$', 250 };
    try print_ascii(
        list.writer(),
        &print_params,
        &test_input,
    );
    try std.testing.expect(std.mem.eql(u8, list.items, "Ab01.$."));
}

fn print_plain_dump(writer: anytype, params: *printParams, input: []const u8) !void {
    for (input, 1..) |character, index| {
        if (params.binary) {
            try writer.writeAll(binCharset[character]);
        } else {
            try writer.writeAll(&byte_to_hex_string(character, params));
        }
        if (index % params.num_columns == 0) {
            if (index != input.len) try writer.writeByte('\n');
        }
    }
    try writer.writeAll("\n");
}

test "validate plain hex dump for correct hex translation" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    var print_params = printParams{ .colorize = false };
    const test_input = [_]u8{ 'L', 'o', 'r', 'e', 'm' };
    try print_plain_dump(
        list.writer(),
        &print_params,
        &test_input,
    );
    try std.testing.expect(std.mem.eql(u8, list.items, "4c6f72656d\n"));
}

test "validate plain hex dump for correct length" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    var print_params = printParams{
        .colorize = false,
        .num_columns = 8,
    };
    const test_input = [_]u8{ 'L', 'o', 'r', 'e', 'm', ' ', 'i', 'p', 's' };
    try print_plain_dump(
        list.writer(),
        &print_params,
        &test_input,
    );
    try std.testing.expect(list.items.len == 20);
}

test "validate plain binary dump for correct binary translation" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    var print_params = printParams{
        .colorize = false,
        .binary = true,
        .num_columns = 2,
    };
    const test_input = [_]u8{ 'L', 'o' };
    try print_plain_dump(list.writer(), &print_params, &test_input);
    try std.testing.expect(std.mem.eql(u8, list.items, "0100110001101111\n"));
}

test "validate plain binary dump for correct length" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    var print_params = printParams{
        .colorize = false,
        .binary = true,
        .num_columns = 3,
    };
    const test_input = [_]u8{ 'L', 'o', 0, '%' };
    try print_plain_dump(list.writer(), &print_params, &test_input);
    try std.testing.expect(list.items.len == 34);
}

fn print_c_inc_style(writer: anytype, params: *printParams, input: []const u8) !void {
    if (params.c_style_name.len != 0) {
        if (params.c_style_capitalise) {
            try writer.writeAll("unsigned char ");
            for (params.c_style_name) |char| {
                try writer.writeByte(std.ascii.toUpper(char));
            }
            try writer.writeAll("[] = {\n  ");
        } else {
            try writer.print("unsigned char {s}[] = {{\n  ", .{params.c_style_name});
        }
    } else {
        try writer.writeAll("  ");
    }
    for (input, 0..) |character, index| {
        // handle linebreaks and the indenting to look like xxd
        if (index % (params.num_columns) == 0 and index != 0) {
            try writer.writeAll("\n  ");
        }
        if (params.binary) {
            try writer.writeAll("0b");
            try writer.writeAll(binCharset[character]);
            if (index != (input.len - 1)) try writer.writeAll(", ");
        } else {
            try writer.writeAll("0x");
            try writer.writeAll(&byte_to_hex_string(character, params));
            if (index != (input.len - 1)) try writer.writeAll(", ");
        }
    }
    if (params.c_style_name.len != 0) {
        if (params.c_style_capitalise) {
            try writer.writeAll("\n};\nunsigned int ");
            for (params.c_style_name) |char| {
                try writer.writeByte(std.ascii.toUpper(char));
            }
            try writer.print("_LEN = {d};\n", .{input.len});
        } else {
            try writer.print("\n}};\nunsigned int {s}_len = {d};\n", .{ params.c_style_name, input.len });
        }
    } else {
        try writer.writeAll("\n");
    }
}

pub fn print_output(
    writer: anytype,
    params: *printParams,
    allocator: std.mem.Allocator,
    reader: anytype,
) !void {
    // allocate memory for the input buffer
    var input_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer input_buffer.deinit(allocator);
    _ = try input_buffer.addManyAsSlice(allocator, (params.page_size + (params.num_columns - 1)));

    // keep a local copy of the autoskip flag in order to turn it off for the
    // very last line. otherwise autoskip could mask how big the file is
    var autoskip: bool = params.autoskip;

    // define how much of the input to print
    var length = input_buffer.items.len;
    if (params.stop_after != 0) length = params.stop_after;

    // this variable is used to print the file position information for a row
    var file_pos: usize = params.position_offset + params.start_at;

    var tail_len: usize = 0; // how many bytes are carried over

    while (true) {
        // read into our buffer exactly one page
        const n_read = try reader.read(input_buffer.items[tail_len..(tail_len + params.page_size)]);

        // if we read nothing from the file and there is no "tail" left, we are
        // at the end of the file
        if (n_read == 0 and tail_len == 0) break;

        const input_buffer_slice = input_buffer.items[0..(tail_len + n_read)];

        // if the user asked for plain dump, just dump everything no formatting
        if (params.postscript) {
            try print_plain_dump(
                writer,
                params,
                input_buffer_slice,
            );
            continue;
        }

        // if the user asked for a c import style ouput, use that function
        if (params.c_style) {
            try print_c_inc_style(
                writer,
                params,
                input_buffer_slice,
            );
            continue;
        }

        // we'll use this variable to count the number of null lines in the
        // output for the autoskip option
        var num_zero_lines: usize = 0;

        // split the buffer into segments based on the number of columns /
        // bytes specified via the command line arguments (default 16)
        var input_iterator = std.mem.window(
            u8,
            input_buffer_slice,
            params.num_columns,
            params.num_columns,
        );

        // loop through the buffer and print the bytes in chunks of the columns
        while (input_iterator.next()) |slice| {
            // if the window is not full, we need to ask the filesystem for the
            // next chunk of the input
            if (slice.len < params.num_columns) {
                tail_len = slice.len;
                // if the window is not full AND we have just read some bytes
                // into the buffer, then we need to break out of this and
                // carry over what is left before the next read
                if (n_read > 0) break;
            }

            // turn off autoskip for the last line. this prevents the last line
            // from being skipped, which would end up hiding the file size
            if (input_iterator.index == null) autoskip = false;

            // if the segment is all zeros, count it. otherwise reset the count
            if (std.mem.allEqual(u8, slice, 0)) {
                num_zero_lines +|= 1;
            } else {
                num_zero_lines = 0;
            }

            // if the user has selected autoskip mode and the number of all-null
            // segments is two or more, skip the segment
            if (autoskip and num_zero_lines == 2) {
                try writer.writeAll("*\n");
                file_pos += slice.len;
                continue;
            } else if (autoskip and num_zero_lines > 2) {
                file_pos += slice.len;
                continue;
            }

            // print the file position in hex (default) or decimal
            if (params.decimal) {
                try writer.print("{d:0>8}: ", .{file_pos});
            } else {
                try writer.print("{x:0>8}: ", .{file_pos});
            }
            file_pos += try print_columns(writer, params, slice);
            try print_ascii(writer, params, slice);
            try writer.writeAll("\n");
            if (params.colorize) try uncolor(writer); //reset color for next line

        }

        // copy the remaining bytes to the front of the buffer in anticipation
        // of the next page read
        if (tail_len > 0) {
            std.mem.copyForwards(
                u8,
                input_buffer.items[0..tail_len],
                input_buffer_slice[(input_buffer_slice.len - tail_len)..input_buffer_slice.len],
            );
        }
        if (n_read == 0) break; // reached EOF, processed everything
    }
}

fn convert_hex_strings(input: []const u8) !u8 {
    // the hex representation of u8 is always two chacters long!
    if (input.len != 2) return error.TypeError;

    var value: u8 = 0;
    value += switch (input[1]) {
        '0'...'9' => input[1] - 48,
        'A'...'F' => input[1] - 55,
        'a'...'f' => input[1] - 87,
        else => return error.InvalidCharacter,
    };
    value += switch (input[0]) {
        '0'...'9' => (input[0] - 48) << 4,
        'A'...'F' => (input[0] - 55) << 4,
        'a'...'f' => (input[0] - 87) << 4,
        else => return error.InvalidCharacter,
    };
    return value;
}

test "test hex string coverter on the line feed byte (upper-case hex)" {
    const test_array = [_]u8{ '0', 'A' };
    try std.testing.expectEqual('\n', convert_hex_strings(&test_array));
}

test "test hex string coverter on a byte that's beyond ASCII (lower-case hex)" {
    const test_array = [_]u8{ 'f', '9' };
    try std.testing.expectEqual(249, convert_hex_strings(&test_array));
}

fn convert_bin_strings(input: []const u8) !u8 {
    // the binary representation of a u8 is always eight characters long!
    if (input.len != 8) return error.TypeError;

    var value: u8 = 0;
    var input_index: u3 = 0; // must be a u3 for the bitshift operation below

    for (input) |character| {
        switch (character) {
            '0' => {},
            '1' => value +|= @as(u8, 1) << (7 - input_index),
            else => return error.InvalidCharacter,
        }
        input_index +|= 1;
    }

    return value;
}

test "test binary string converter on an ASCII character" {
    const test_string = "01011010";
    try std.testing.expectEqual('Z', convert_bin_strings(test_string));
}

test "test binary string converter outside the ASCII range" {
    const test_string = "11111111";
    try std.testing.expectEqual(0xff, convert_bin_strings(test_string));
}

fn find_first_char(target_slice: []const u8, char: u8) !usize {
    for (0..(target_slice.len - 1)) |index| {
        if (target_slice[index] == char) return index;
    } else {
        return error.EndOfStream;
    }
}

pub fn reverse_input(
    writer: anytype,
    params: *printParams,
    allocator: std.mem.Allocator,
    reader: anytype,
    diagnostic: *Diagnostic,
) !void {
    // we use a window iterator to move through the data, where the window size
    // depends on if we are reversing a hex or binary dump
    const window_size: u8 = switch (params.binary) {
        true => 8,
        false => 2,
    };

    // how many bytes we have reversed (useful for error catching and keeping
    // track of where we are in the input across buffers)
    var bytes_written: usize = 0;

    diagnostic.line_number = 0; // for error handling

    // need some parameters to handle data dumped with autoskip
    const index_base: u8 = switch (params.decimal) {
        true => 10,
        false => 16,
    };
    var last_data_index: usize = 0;
    var new_data_index: usize = 0;
    var skipping: bool = false; // managing state

    // setup iteration. first, we need an arraylist
    var input_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer input_buffer.deinit(allocator);
    // allocate a whole page of bytes
    _ = try input_buffer.addManyAsSlice(allocator, params.page_size);
    // try to read a whole page from the input (stdin, a file, or a string)
    // this variable will store how many bytes reader (useful below)
    var n_read = try reader.read(input_buffer.items);
    // determine how long a line is in this dataset
    const normal_line_length = try find_first_char(input_buffer.items, '\n');
    // in order to handle data with breaks in the middle of lines, we need the
    // buffer to be the size of a page + the length of a line minus one byte
    _ = try input_buffer.addManyAsSlice(allocator, normal_line_length - 1);

    var tail_len: usize = 0; // how many bytes carried over

    // iterate over the data
    while (true) {
        // grab a slice of the valid data within the buffer. any data "outside"
        // this slice would be undefined or from previous file reads
        const input_buffer_slice = input_buffer.items[0..(tail_len + n_read)];

        // split the buffer up on newlines so we can iterate line-by-line
        var input_buffer_line_iter = std.mem.splitScalar(u8, input_buffer_slice, '\n');

        // iterate over the lines
        while (input_buffer_line_iter.next()) |line| {

            // if the current line is shorter than a normal line, we need to
            // check what is going on
            if (line.len < normal_line_length) {
                // if the current line is empty, then we may be at the end
                if (line.len == 0) {
                    tail_len = 0;
                    break;
                }
                if (line[0] == '*') { // check if we are skipping
                    last_data_index = new_data_index;
                    skipping = true;
                    diagnostic.line_number += 1;
                    continue;
                } else if (n_read > 0) { // check if we last read any data in
                    tail_len = line.len;
                    break;
                }
            }

            diagnostic.line_number += 1;

            // TODO: enable support for "plain" postscript dump reversal
            // setup window iterator for the line
            var running_over_index: bool = undefined;
            if (params.postscript) {
                running_over_index = false; // lines always start with an index
            } else {
                running_over_index = true;
            }
            var colon_position: usize = undefined;
            var line_iter = std.mem.window(
                u8,
                line,
                window_size,
                1,
            );

            // iterate and process the line
            // TODO: consider breaking this out into a function
            while (line_iter.next()) |slice| {
                // look for the ": " sequence in order to grab the line's index
                if (running_over_index) {
                    if (std.mem.eql(u8, slice[0..(slice.len - (window_size - 2))], ": ")) {
                        if (line_iter.index) |index| colon_position = index;
                        if (std.fmt.parseUnsigned(
                            usize,
                            line[0..(colon_position - 1)],
                            index_base,
                        )) |value| {
                            new_data_index = value;
                            _ = line_iter.next();
                        } else |err| switch (err) {
                            error.InvalidCharacter => return error.DumpParseError,
                            else => return err,
                        }
                        running_over_index = false;
                    }
                } else {
                    // if we have been skipping, we need to fill in the right
                    // amount of null bytes
                    if (skipping) {
                        for (0..(new_data_index - last_data_index - params.num_columns)) |_| {
                            try writer.writeByte(0);
                            bytes_written += 1;
                        }
                        skipping = false;
                    }
                    // if we find the "  " sequence, we've hit the ASCII
                    // representation part of the dump and can skip to the next
                    // line
                    if (std.mem.eql(u8, slice[0..(slice.len - (window_size - 2))], "  ")) {
                        break;
                    }

                    if (slice[0] == ' ') continue; // handle arbitrary byte groupings

                    // parse the data
                    if (params.binary) {
                        if (convert_bin_strings(slice)) |value| {
                            try writer.writeByte(value);
                            bytes_written += 1;
                            inline for (0..7) |_| _ = line_iter.next();
                        } else |err| switch (err) {
                            error.InvalidCharacter => return err,
                            else => return err,
                        }
                    } else {
                        if (convert_hex_strings(slice)) |value| {
                            try writer.writeByte(value);
                            bytes_written += 1;
                            _ = line_iter.next();
                        } else |err| switch (err) {
                            error.InvalidCharacter => return err,
                            else => |other_err| return other_err,
                        }
                    }
                }
            }
        }
        // copy the remaining bytes to the front of the buffer in anticipation
        // of the next page read
        if (tail_len > 0) {
            std.mem.copyForwards(
                u8,
                input_buffer.items[0..tail_len],
                input_buffer.items[(input_buffer_slice.len - tail_len)..input_buffer_slice.len],
            );
        }
        if (n_read == 0) break; // reached EOF, processed everything

        // read into the buffer exactly one page
        n_read = try reader.read(input_buffer.items[tail_len..(tail_len + params.page_size)]);

        // if we read nothing from the file and there is no "tail" left, we are
        // at the end of the file
        if (n_read == 0 and tail_len == 0) break;
    }
    if (bytes_written <= 0) return error.NothingWritten;
}

test "bad index in reverse mode" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var params = printParams{ .reverse = true, .page_size = std.heap.pageSize() };
    var diag = Diagnostic{};
    const malformed_input = "0000zxcv: 4c6f  Lo\n";
    var malformed_input_fbs = std.io.fixedBufferStream(malformed_input);
    try std.testing.expectError(error.DumpParseError, reverse_input(
        buffer.writer(),
        &params,
        std.testing.allocator,
        malformed_input_fbs.reader(),
        &diag,
    ));
}

test "invalid hex character found in reverse mode" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var params = printParams{ .reverse = true, .page_size = std.heap.pageSize() };
    var diag = Diagnostic{};
    const malformed_input = "00000000: 4c6z  L.\n";
    var malformed_input_fbs = std.io.fixedBufferStream(malformed_input);
    try std.testing.expectError(error.InvalidCharacter, reverse_input(
        buffer.writer(),
        &params,
        std.testing.allocator,
        malformed_input_fbs.reader(),
        &diag,
    ));
}

test "invalid binary character found in reverse mode" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var params = printParams{ .reverse = true, .binary = true, .page_size = std.heap.pageSize() };
    var diag = Diagnostic{};
    const malformed_input = "00000000: 01001100 abcdefgh  L.\n";
    var malformed_input_fbs = std.io.fixedBufferStream(malformed_input);
    try std.testing.expectError(error.InvalidCharacter, reverse_input(
        buffer.writer(),
        &params,
        std.testing.allocator,
        malformed_input_fbs.reader(),
        &diag,
    ));
}

test "writing nothing because of malformed reverse input" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var params = printParams{ .reverse = true, .page_size = std.heap.pageSize() };
    var diag = Diagnostic{};
    const malformed_input = "ghijklmnopqrstuv.$\n";
    var malformed_input_fbs = std.io.fixedBufferStream(malformed_input);
    try std.testing.expectError(error.NothingWritten, reverse_input(
        buffer.writer(),
        &params,
        std.testing.allocator,
        malformed_input_fbs.reader(),
        &diag,
    ));
}

test "missing newline after reading many bytes errors out" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    var params = printParams{ .reverse = true, .page_size = std.heap.pageSize() };
    var diag = Diagnostic{};
    const malformed_input = "ghijklmnopqrstuv.$ long input";
    var malformed_input_fbs = std.io.fixedBufferStream(malformed_input);
    try std.testing.expectError(error.EndOfStream, reverse_input(
        buffer.writer(),
        &params,
        std.testing.allocator,
        malformed_input_fbs.reader(),
        &diag,
    ));
}
