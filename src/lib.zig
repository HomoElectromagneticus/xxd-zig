const std = @import("std");

const Color = enum {
    green,
    yellow,
    white,
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
    //                                              bold ---\   green --\
    if (color == Color.green) try writer.writeAll("\u{001b}[1m\u{001b}[32m");
    //                                              bold ----\  yellow --\
    if (color == Color.yellow) try writer.writeAll("\u{001b}[1m\u{001b}[33m");
    //                                              bold ----\  white --\
    if (color == Color.white) try writer.writeAll("\u{001b}[1m\u{001b}[37m");
}

// tell the terminal to go back to standard color
fn uncolor(writer: anytype) !void {
    try writer.writeAll("\u{001b}[0m");
}

fn print_columns(writer: anytype, params: *printParams, input: []const u8) !usize {
    // number of printed characters of translated input (not including the
    // index markers on the left!)
    var num_printed_chars: usize = 0;
    // number of spaces for lining up the ascii characters in the final row
    var num_spaces: usize = 0;

    // split the input into groups, where size is given by the print parameters
    var groups_iterator = std.mem.window(
        u8,
        input,
        params.group_size,
        params.group_size,
    );

    while (groups_iterator.next()) |group| {
        // if the last group for a little-endian dump is not full, add
        // extra spaces for perfect alignment
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
                        // non-printable ASCII should be yellow
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

    // if it's the last part of the input, we need to line up the ascii text
    // with the previous columns
    if (input.len < params.num_columns) {
        num_spaces += params.line_length -| num_printed_chars;

        // when the number of columns is not evenly divisible by the group
        // size, we need an extra space or the ASCII won't line up right
        if (params.num_columns % params.group_size != 0) num_spaces += 1;

        for (0..num_spaces) |_| {
            try writer.writeAll(" ");
        }
    }
    // add an extra space to copy xxd
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

// for the ascii output on the right-hand-side
fn print_ascii(writer: anytype, params: *printParams, input: []const u8) !void {
    for (input) |raw_char| {
        // handle color
        if (params.colorize) {
            switch (raw_char) {
                0 => try colorize(writer, Color.white),
                32...126 => try colorize(writer, Color.green),
                else => try colorize(writer, Color.yellow),
            }
        }
        // actual character output (with non-printable characters as '.')
        if (raw_char >= 32 and raw_char <= 126) {
            try writer.print("{c}", .{raw_char});
        } else {
            try writer.writeAll(".");
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

pub fn print_output(writer: anytype, params: *printParams, input: []const u8) !void {
    // keep a local copy of the autoskip flag in order to turn it off for the
    // very last line. otherwise autoskip could mask how big the file is
    var autoskip: bool = params.autoskip;

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

    // we'll use this variable to count the number of null lines in the output
    // for the autoskip option
    var num_zero_lines: usize = 0;

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

        // TODO: is there a faster way to do this?
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
}

fn convert_hex_strings(input: []const u8) !u8 {
    // the hex representation of u8 is always two chacters long!
    if (input.len != 2) return error.TypeError;

    var value: u8 = 0;
    value += switch (input[1]) {
        '0'...'9' => input[1] - 48,
        'A'...'F' => input[1] - 55,
        'a'...'f' => input[1] - 87,
        // this should probably error if we get a different character
        else => 0,
    };
    value += switch (input[0]) {
        '0'...'9' => (input[0] - 48) << 4,
        'A'...'F' => (input[0] - 55) << 4,
        'a'...'f' => (input[0] - 87) << 4,
        // this should probably error if we get a different character
        else => 0,
    };
    return value;
}

test "test hex coverter on a normal ASCII character (lower-case hex)" {
    const test_array = [_]u8{ '4', 'b' };
    try std.testing.expectEqual('K', convert_hex_strings(test_array));
}

test "test hex coverter on the line feed byte (upper-case hex)" {
    const test_array = [_]u8{ '0', 'A' };
    try std.testing.expectEqual('\n', convert_hex_strings(test_array));
}

test "test hex coverter on a byte that's beyond ASCII (lower-case hex)" {
    const test_array = [_]u8{ 'f', '9' };
    try std.testing.expectEqual(249, convert_hex_strings(test_array));
}

pub fn reverse_input(writer: anytype, params: *printParams, input: []const u8) !void {
    // a little warning message while this feature is in development
    if (params.binary or params.autoskip) {
        try writer.writeAll("We're not ready for that, check again later!\n");
        return;
    }

    // the original can't reverse little-endian or c-inlude style dumps either
    if (params.little_endian or params.c_style) {
        try writer.writeAll("zig-xxd: Sorry, cannot revert this type of hexdump\n");
    }

    var input_iterator = std.mem.window(
        u8,
        input,
        2,
        1,
    );

    // iterate over the lines
    var ready: bool = false;
    if (params.postscript) ready = true;
    while (input_iterator.next()) |slice| {
        // skip through the line until you find a ": " slice. this jumps
        // passed the index at the beginning of each line. we may not be able
        // to guarantee the format of the input data, so this is the safest way
        if ((params.postscript == false) and (ready == false)) {
            if (std.mem.eql(u8, slice, ": ")) {
                ready = true;
                _ = input_iterator.next();
            }
            continue;
        }

        // in xxd (and this version of xxd), a regular dump is separated from
        // the ASCII representation by two spaces. this provides us with a hint
        if (std.mem.eql(u8, slice, "  ")) {
            ready = false;
            continue;
        }

        // this bit lets us deal with arbitrary byte groupings
        if (slice[0] == ' ') {
            continue;
        }

        // very helpful for "plain" postscript dumps
        if (slice[0] == '\n') {
            continue;
        }

        try writer.writeByte(try convert_hex_strings(slice));
        _ = input_iterator.next();
    }
}
