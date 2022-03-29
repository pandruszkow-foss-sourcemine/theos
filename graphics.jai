
USE_VGA :: !ENABLE_VESA;

Vesa :: struct {
    framebuffer: *u32;
    buffer_size: int;
    pixels: int;

    char_width:  int;
    char_height: int;

    cursor: int;
    text_buffer: *u8;

    attribute_count: int;
    attribute_buffer: *Attribute;

    font: Pnm;
}

Attribute :: struct {
    start_position: int;
    color: Color;
    flags: Text_Flags;
}

Text_Flags :: enum_flags u32 {
    
}

vesa: Vesa;

vesa_init :: (boot_data: Boot_Data, font: Pnm) {
    #if !ENABLE_VESA return;

    assert(font.type == .GRAYMAP);

    vesa.pixels = VESA_WIDTH * VESA_HEIGHT;
    vesa.buffer_size = VESA_WIDTH * VESA_HEIGHT * VESA_DEPTH / 8;
    vesa.framebuffer = xx map_memory(vesa.buffer_size, physical_address = boot_data.vesa_framebuffer);

    char_count := 95;
    assert(font.width % 95 == 0);

    vesa.char_width  = font.width / char_count;
    vesa.char_height = font.height;

    vesa.text_buffer = map_memory(0x10_000);
    vesa.attribute_buffer = map_memory(0x10_000);

    vesa.font = font;
    vesa.cursor = 0;

    set_color(theme.foreground);
}

vesa_draw_frame :: () {
    #if !ENABLE_VESA return;

    {
        top_left := 72 + 72 * VESA_WIDTH;

        cursor_x: int;
        cursor_y: int;

        for 0..vesa.cursor - 1 {
            char := vesa.text_buffer[it];
            if char == 0 continue;
            if char == #char "\r" continue;
            if char == #char "\n" {
                cursor_y += 1;
                cursor_x = 0;
                continue;
            }

            source_top_left := vesa.char_width * (char - 0x20);

            for y: 0..vesa.char_height-1 for x: 0..vesa.char_width-1 {
                brightness := cast(u32) vesa.font.data[source_top_left + x + y * vesa.font.width];
                t := cast(float) brightness * theme.shadow / 255;

                line := cursor_y * (vesa.char_height + 2) * VESA_WIDTH;
                column := cursor_x * vesa.char_width;
                source := vesa.framebuffer[line + column + x + y * VESA_WIDTH + top_left];

                r := cast(u32) (cast(float) cast(u8) (source >> 16) * (1 - t) + cast(float) 0x18 * t);
                g := cast(u32) (cast(float) cast(u8) (source >>  8) * (1 - t) + cast(float) 0x18 * t);
                b := cast(u32) (cast(float) cast(u8) (source)       * (1 - t) + cast(float) 0x18 * t);

                blended: u32 = b | (g << 8) | (r << 16);
                vesa.framebuffer[line + column + x + y * VESA_WIDTH + top_left] = blended;
            }

            cursor_x += 1;
            if cursor_x >= 180 {
                cursor_x = 0;
                cursor_y += 1;
            }
        }
    }

    {
        top_left := 70 + 70 * VESA_WIDTH;

        cursor_x: int;
        cursor_y: int;

        attr_cursor: int;
        color := theme.foreground;

        for 0..vesa.cursor - 1 {
            if vesa.attribute_count > attr_cursor {
                attr := vesa.attribute_buffer[attr_cursor];
                while attr.start_position == it && vesa.attribute_count > attr_cursor {
                    color = attr.color;
                    attr_cursor += 1;
                    attr = vesa.attribute_buffer[attr_cursor];
                }
            }

            char := vesa.text_buffer[it];
            if char == 0 continue;
            if char == #char "\r" continue;
            if char == #char "\n" {
                cursor_y += 1;
                cursor_x = 0;
                continue;
            }

            source_top_left := vesa.char_width * (char - 0x20);

            for y: 0..vesa.char_height-1 for x: 0..vesa.char_width-1 {
                line := cursor_y * (vesa.char_height + 2) * VESA_WIDTH;
                column := cursor_x * vesa.char_width;
                source := vesa.framebuffer[line + column + x + y * VESA_WIDTH + top_left];

                brightness := cast(u32) vesa.font.data[source_top_left + x + y * vesa.font.width];
                t := cast(float) brightness / 255;

                r := cast(u32) (cast(float) cast(u8) (source >> 16) * (1 - t) + cast(float) color.r * t);
                g := cast(u32) (cast(float) cast(u8) (source >> 8)  * (1 - t) + cast(float) color.g * t);
                b := cast(u32) (cast(float) cast(u8) (source)       * (1 - t) + cast(float) color.b * t);

                blended: u32 = b | (g << 8) | (r << 16);
                vesa.framebuffer[line + column + x + y * VESA_WIDTH + top_left] = blended;
            }

            cursor_x += 1;
            if cursor_x >= 180 {
                cursor_x = 0;
                cursor_y += 1;
            }
        }
    }
}

vesa_blit :: (image: Pnm) {
    assert(image.type == .PIXMAP);
    size := image.width * image.height;

    cursor: int;
    for y: 0..image.height-1 for x: 0..image.width-1 {
        if x + y * VESA_WIDTH >= vesa.pixels break;

        r := cast(u32) image.data[cursor];
        g := cast(u32) image.data[cursor + 1];
        b := cast(u32) image.data[cursor + 2];
        vesa.framebuffer[(VESA_WIDTH - 1) - x + y * VESA_WIDTH] = (r << 16) | (g << 8) | b;
        cursor += 3;

    }
}



Pnm :: struct {
    width: int;
    height: int;

    type: enum {
        UNINITIALIZED :: 0;
        ASCII_BITMAP;
        ASCII_GRAYMAP;
        ASCII_PIXMAP;
        BITMAP;
        GRAYMAP;
        PIXMAP;
    }

    data: *u8;
}

parse_pnm :: (buffer: *u8) -> Pnm {
    assert(buffer[0] == #char "P");

    pnm: Pnm;
    pnm.type = xx (buffer[1] - #char "0");
    assert(pnm.type == .GRAYMAP || pnm.type == .PIXMAP);

    is_whitespace :: (char: u8) -> bool {
        return char == 0x20
            || char == 0x09
            || char == 0x0a
            || char == 0x0b
            || char == 0x0c
            || char == 0x0d
            || char == #char "#";
    }

    ConsumeWhitespaceAndComments :: () #expand {
        while is_whitespace(buffer[`cursor]) {
            if buffer[`cursor] == #char "#" {
                while buffer[`cursor] != 0xa `cursor += 1;
            }
            cursor += 1;
        }
    }

    ParseInt :: () -> int #expand {
        digit := buffer[`cursor]; //`
        result: int;

        while !is_whitespace(digit) {
            assert(digit >= #char "0" && digit <= #char "9");
            result *= 10;
            result += digit - #char "0";
            `cursor += 1;
            digit = buffer[`cursor];
        }
        return result;
    }

    cursor := 2;
    ConsumeWhitespaceAndComments();
    pnm.width = ParseInt();

    ConsumeWhitespaceAndComments();
    pnm.height = ParseInt();

    ConsumeWhitespaceAndComments();
    max_value := ParseInt();
    assert(max_value == 255);

    ConsumeWhitespaceAndComments();
    pnm.data = buffer + cursor;

    return pnm;
}



TITLE :: #string END
   /##     /##                                                  
  | ##    | ##                                                  
 /######  | #######   /######   /######   /#######              
|_  ##_/  | ##__  ## /##__  ## /##__  ## /##_____/              
  | ##    | ##  \ ##| ########| ##  \ ##|  ######               
  | ## /##| ##  | ##| ##_____/| ##  | ## \____  ##              
  |  ####/| ##  | ##|  #######|  ######/ /#######/              
   \___/  |__/  |__/ \_______/ \______/ |_______/               
END;


welcome_screen :: () {

#if USE_VGA {
    margin = 0;
    indent = 0;
}

    print(TITLE, theme.primary);
    print("\n\n");

    print("Hello, sailor.\n");
    print("Boot time is ");

    print(weekdays[cmos_read(.WEEKDAY) - 1]);
    print(" ");
    print(months[cmos_read(.MONTH) - 1]);
    print(" ");
    print(cmos_read(.DAY_OF_THE_MONTH));
    print(", ");
    print(cmos_read(.YEAR) + 2000);
    print(", ");

    hours := cmos_read(.HOURS);
    if hours < 10 print("0"); print(hours);
    print(":");

    minutes := cmos_read(.MINUTES);
    if minutes < 10 print("0"); print(minutes);
    print(":");

    seconds := cmos_read(.SECONDS);
    if seconds < 10 print("0"); print(seconds);
    print(".\n");

    print("There are ");
    print(file_count);
    print(" files in the mailbag.\n");

    print("\n");

    ti := type_info(x86_Feature_Flag);
    print("Supported CPU features: -------------------------------------------", theme.foreground);
    flags_on_this_line: int;
    for 0..ti.names.count-1 {
        if check_feature(cpu.feature_leaves, xx ti.values[it]) {
            name := ti.names[it];
            if name.count >= 8 continue;

            if (flags_on_this_line % 7) == 0 print("\n");

            print("| ", theme.foreground);
            print(name, theme.highlight);
            for 1..8 - name.count  print(" ");
            flags_on_this_line += 1;
        }
    }
    print("\n-------------------------------------------------------------------\n", theme.foreground);

    print("Compiled using ", theme.primary);
    print("Jai ", theme.accent);
    print(COMPILER_VERSION, theme.accent);
    print(".\n");
}

#if ENABLE_VESA {
    clear_screen :: () {
        for 0..vesa.pixels / 2 - 1 {
            << (cast(*u64) vesa.framebuffer + it) = (cast(u64) theme.background.as_u32) | ((cast(u64) theme.background.as_u32) << 32);
        }
    }

    theme: Theme;
    Theme :: struct {
        background:  Color = .{ as_u32 = 0x00603038 };
        foreground:  Color = .{ as_u32 = 0x00f8f8f8 };
        primary:     Color = .{ as_u32 = 0x00ebbcbc };
        highlight:   Color = .{ as_u32 = 0x00ebbcbc };
        accent:      Color = .{ as_u32 = 0x0081c44b };

        shadow: float = 1.0;
    }

    Color :: union {
        as_u32: u32;
        struct {
            b: u8;
            g: u8;
            r: u8;
            _: u8;
        }
    }
    #assert(size_of(Color) == size_of(u32));
    COLOR_NONE :: Color.{ _ = 123 };

    set_color :: (color: Color) {
        attribute: Attribute;
        attribute.start_position = vesa.cursor;
        attribute.color = color;
        vesa.attribute_buffer[vesa.attribute_count] = attribute;
        vesa.attribute_count += 1;
    }

    print :: (text: string) {
        print(text, theme.foreground);
    }

    print :: (text: string, color: Color) {
        if !text.count return;
        old_color := vesa.attribute_buffer[vesa.attribute_count].color;
        set_color(color);

        crt_memcpy(vesa.text_buffer + vesa.cursor, text.data, xx text.count);
        vesa.cursor += text.count;

        set_color(old_color);
    }

    print :: (number: int) {
        print(number, theme.foreground);
    }

    print :: (number: int, color: Color) {
        negative: bool;
        buffer: [30] u8 = ---;

        _number := number;
        if number < 0 _number *= -1;

        for 0..buffer.count - 1 {
            rem := _number % 10;
            buffer[29 - it] =  #char "0" + cast(u8) rem;
            _number /= 10;

            if _number == 0 {
                result: string = ---;
                result.data = buffer.data + 29 - it;
                result.count = it + 1;
                print(result, color);
                return;
            }
        }
    }

    print_hex :: (number: $T, decorate := true) {
        print_hex(number, theme.foreground, decorate);
    }
    
    print_hex :: (number: $T, color: Color, decorate := true) {
        #assert type_info(T).type == .INTEGER;
        size :: size_of(T);

        if decorate print("0x", color);

        result: [size*2] u8;

        table := "0123456789abcdef";
        for 0..size * 2 {
            index := number >> (it * 4);
            index &= 0xf;

            result[size*2 - it - 1] = table[index];
        }
        print(cast(string) result, color);
    }
}



































#if USE_VGA {
    vga_columns :: 80;
    vga_rows    :: 25;

    indent: int;
    margin: int = 2;
    ceiling: int = 5;

    text_cursor: int = 2;
    vga_screen :: cast(*u8) 0xb8000;

    get_attribute :: () -> u8 {
        if !USE_VGA return 0;
        return cast(u8) theme.normal | (theme.background << 4);
    }

    vertical_divide :: () {
        if !USE_VGA return;
        furthest: int;

        for y: 0..vga_rows - 1 {
            for x: 0..vga_columns - 1 {
                cell := y * vga_columns + x;
                if vga_screen[cell * 2] != 0 && vga_screen[cell * 2] != #char " " {
                    if x > furthest furthest = x;
                }
            }
        }

        for 0..vga_rows-1 {
            cell := it * vga_columns + furthest + 3;
            vga_screen[cell * 2] = 0xba;
        }

        indent = furthest + 4;
        text_cursor = margin;
    }

    print :: (text: string, foreground: Vga_Color = 255) {
        if !USE_VGA return;
        fg := ifx foreground == 255 then theme.normal else xx foreground;

        for cast([] u8) text {
            if it == 10 {
                distance := text_cursor % vga_columns;
                text_cursor += vga_columns - distance;
                text_cursor += margin;
                continue;
            }

            if it == 13 continue;

            i := text_cursor + indent;
            if (i+1) % vga_columns == 0 {
                text_cursor += indent + margin + margin;
            }

            vga_screen[i * 2]     = it;
            vga_screen[i * 2 + 1] = cast(u8) fg | (theme.background << 4);

            text_cursor += 1;
        }
    }

    print :: (number: int, color: Vga_Color = 255) {
        if !USE_VGA return;
        c := color;
        if c == 255 c = theme.foreground;

        negative: bool;
        buffer: [30] u8 = ---;

        _number := number;
        if number < 0 _number *= -1;

        for 0..buffer.count - 1 {
            rem := _number % 10;
            buffer[29 - it] =  #char "0" + cast(u8) rem;
            _number /= 10;

            if _number == 0 {
                result: string = ---;
                result.data = buffer.data + 29 - it;
                result.count = it + 1;
                print(result, color);
                return;
            }
        }
    }

    print_hex :: (number: $T, decorate := true) {
        if !USE_VGA return;
        #assert type_info(T).type == .INTEGER;
        size := #run type_info(T).runtime_size;

        if decorate print("0x");

        table := "0123456789abcdef";
        for 0..size * 2 - 1 {
            index := number >> (it * 4);
            index &= 0xf;

            cur := (text_cursor + indent + size * 2 - it - 1) * 2;
            vga_screen[cur] = table[index];
            vga_screen[cur + 1] = get_attribute();
        }
        text_cursor += size * 2;
    }

    debug :: (variable: string) #expand {
        print(variable);
        print(": ");

        value :=
        #insert variable
        ;
        print_hex(cast(u64) value); //`
        // else print(number);
        print("\n");
    }

    clear_screen :: () {
        for 0..vga_columns * vga_rows - 1 {
            vga_screen[it * 2]     = 0;
            vga_screen[it * 2 + 1] = get_attribute();
        }
        text_cursor = indent;
    }

    theme: struct {
        background : Vga_Color = .BLACK;
        foreground : Vga_Color = .WHITE;
        normal     : Vga_Color = .CYAN;
        highlight  : Vga_Color = .LIGHT_CYAN;
        accent     : Vga_Color = .RED;
    }

    Vga_Register :: enum u16 {
        ATTRIBUTE_ADDRESS :: 0x3c0;
        DATA_READ         :: 0x3c1;
        DAC_PALETTE_MASK  :: 0x3c6;
        DAC_STATE         :: 0x3c7;
        DAC_ADDRESS_READ  :: 0x3c7;
        DAC_ADDRESS_WRITE :: 0x3c8;
        DAC_DATA          :: 0x3c9;
        CRT_CONTROL_INDEX :: 0x3d4;
        CRT_CONTROL_DATA  :: 0x3d5;
        INPUT_STATUS      :: 0x3da;
    }

    vga_hide_cursor :: () {
        if !USE_VGA return;
        using Vga_Register;

        port_write(xx CRT_CONTROL_INDEX, 0x0a);
        port_write(xx CRT_CONTROL_DATA,  0x20);
    }

    vga_set_palette_entry :: (index: u8, red: u8, green: u8, blue: u8) {
        if !USE_VGA return;
        using Vga_Register;

        port_write(xx DAC_PALETTE_MASK, 0xff);
        port_write(xx DAC_ADDRESS_WRITE, index);
        port_write(xx DAC_DATA, red);
        port_write(xx DAC_DATA, green);
        port_write(xx DAC_DATA, blue);
    }

    vga_attribute :: (register_name: u8, bit: u8, set: bool = true) {
        if !USE_VGA return;
        using Vga_Register;

        PAS : u8 :    1 << 5;
        mask: u8 = xx 1 << bit;

        port_read(xx INPUT_STATUS);
        address := port_read(xx ATTRIBUTE_ADDRESS);
        port_write(xx ATTRIBUTE_ADDRESS, register_name | PAS);

        data := port_read(xx DATA_READ);
        if set data |=  mask;
        else   data &= ~mask;

        port_write(xx ATTRIBUTE_ADDRESS, data);
        port_write(xx ATTRIBUTE_ADDRESS, address);
    }

    Vga_Color :: enum u8 {
        BLACK         :: 0x00;
        BLUE          :: 0x01;
        GREEN         :: 0x02;
        CYAN          :: 0x03;
        RED           :: 0x04;
        MAGENTA       :: 0x05;
        BROWN         :: 0x06;
        WHITE         :: 0x07;
        GRAY          :: 0x08;
        LIGHT_BLUE    :: 0x09;
        LIGHT_GREEN   :: 0x0a;
        LIGHT_CYAN    :: 0x0b;
        LIGHT_RED     :: 0x0c;
        LIGHT_MAGENTA :: 0x0d;
        YELLOW        :: 0x0e;
        BRIGHT_WHITE  :: 0x0f;
    }
}
