
USE_VGA :: !ENABLE_VESA;

Vesa :: struct {
    framebuffer: *u32;
    buffer_size: int;
    pixels: int;

    char_width:  int;
    char_height: int;

    text_buffer: *u8;
    font: Pnm;
}

vesa_init :: (vesa: *Vesa, boot_data: Boot_Data, font: Pnm) {
    // #if !ENABLE_VESA return;

    assert(font.type == .GRAYMAP);

    vesa.buffer_size = VESA_WIDTH * VESA_HEIGHT * VESA_DEPTH / 8;
    vesa.pixels = VESA_WIDTH * VESA_HEIGHT;
    vesa.framebuffer = xx map_memory(vesa.buffer_size, physical_address = boot_data.vesa_framebuffer);

    char_count := 95;
    assert(font.width % 95 == 0);

    vesa.char_width  = font.width / char_count;
    vesa.char_height = font.height;

    vesa.text_buffer = map_memory(0x1000);
    vesa.font = font;
}

vesa_set_pixel :: inline (vesa: *Vesa, x: int, y: int, color: u32) {
    vesa.framebuffer[x + y * VESA_WIDTH] = color;
}

vesa_draw_frame :: (vesa: *Vesa) {
    // #if !ENABLE_VESA return;

    if simd_enabled {
        c: u64 = 0x0060303800603038;
        #asm SSE {
            movq color:, c;
            punpckldq color, color;
        }

        assert(vesa.buffer_size % 4 == 0);
        for 0..vesa.pixels / 4 - 1 {
            target := *vesa.framebuffer[it * 4] #align 16;
            #asm SSE {
                movdqa [target], color;
            }
        }
    } else {
        for 0..vesa.pixels / 2 - 1 {
            << (cast(*u64) vesa.framebuffer + it) = 0x0060303800603038;
        }
    }

    bg: u32 = 0x00603038;
    for 0..0x100 - 1 {
        if vesa.text_buffer[it] == 0 continue;
        start := vesa.char_width * (vesa.text_buffer[it] - 0x20);

        for y: 0..vesa.char_height-1 for x: 0..vesa.char_width-1 {
            print_hex(start + x + y * 95 * vesa.char_width); print("\n");
            print_hex(cast(u64) vesa.font.data);
            brightness2 := cast(u32) vesa.font.data[0];
            while true {}
            brightness := cast(u32) vesa.font.data[start + x + y * 95 * vesa.char_width];
            t := cast(float) brightness / 255;

            r := cast(u32) (cast(float) 0x60 * (1 - t) + cast(float) 0xff * t);
            g := cast(u32) (cast(float) 0x30 * (1 - t) + cast(float) 0xff * t);
            b := cast(u32) (cast(float) 0x38 * (1 - t) + cast(float) 0xff * t);

            blended: u32 = b | (g << 8) | (r << 16);
            vesa.framebuffer[(it / 80) * vesa.char_height * VESA_HEIGHT + it * vesa.char_width + x + y * VESA_WIDTH] = blended;
        }
    }
}



Pnm :: struct {
    width: int;
    height: int;

    type: enum {
        UNINITIALIZED :: 0;
        BITMAP;
        GRAYMAP;
        PIXMAP;
    }

    data: *u8;
}

parse_pnm :: (buffer: *u8) -> Pnm {
    assert(buffer[0] == #char "P");

    pnm: Pnm;
    pnm.type = xx (buffer[1] - #char "0" - 3);
    assert(pnm.type == .GRAYMAP);

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
    max_gray_value := ParseInt();
    assert(max_gray_value < 256);

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
    if !USE_VGA return;
    margin = 0;
    indent = 0;
    clear_screen();

    print("\n\n");
    print(TITLE);
    print("\n");

    old_foreground := theme.normal;
    theme.normal = theme.foreground;
    print("      Hello, sailor.\n");
    print("      Boot time is ");

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

    print("      There are ");
    print(file_count);
    print(" files in the mailbag.\n");

    print("\n");
    theme.normal = old_foreground;

    ti := type_info(x86_Feature_Flag);
    print("      Supported CPU features: -------------------------------------------", theme.foreground);
    flags_on_this_line: int;
    for 0..ti.names.count-1 {
        if check_feature(cpu.feature_leaves, xx ti.values[it]) {
            name := ti.names[it];
            if name.count >= 8 continue;

            if (flags_on_this_line % 7) == 0 print("\n      ");

            print("| ", theme.foreground);
            print(name, theme.highlight);
            for 1..8 - name.count  print(" ");
            flags_on_this_line += 1;
        }
    }
    print("\n      -------------------------------------------------------------------\n", theme.foreground);

    print("      Compiled using ");
    print("Jai ", theme.accent);
    print(COMPILER_VERSION, theme.accent);
    print(".\n");
}



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

print :: (text: string, foreground: Vga_Color = 255, background: Vga_Color = 255) {
    if !USE_VGA return;
    fg := ifx foreground == 255 then theme.normal else xx foreground;
    bg := ifx background == 255 then theme.background else xx background;

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
        vga_screen[i * 2 + 1] = cast(u8) fg | (bg << 4);

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
    #if USE_VGA {
        for 0..vga_columns * vga_rows - 1 {
            vga_screen[it * 2]     = 0;
            vga_screen[it * 2 + 1] = get_attribute();
        }
        text_cursor = indent;
    } else {
        // for 0..vesa.buffer_size / 2 - 1 {
        //     << (cast(*u64) vesa.framebuffer + it) = 0x0060303800603038;
        // }
    }
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
