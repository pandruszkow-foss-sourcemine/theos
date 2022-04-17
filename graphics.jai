
Graphics :: struct {
    screen_buffer: *u32;
    vesa_framebuffer: *u32;

    screen_width: int;
    screen_height: int;
    surfaces: *Screen_Draw_List_Entry;

    draw_list_store: [10] Screen_Draw_List_Entry;
    draw_list_size: int;
}

graphics: Graphics;

Surface :: struct {
    buffer: *u32;
    width: int;
    height: int;
}

create_surface :: (width: int, height: int) -> Surface {
    surface: Surface;
    surface.width = width;
    surface.height = height;
    surface.buffer = map_memory(width * height * size_of(u32));
    return surface;
}

clear_surface_to_color :: (surface: Surface, color: Color) {
    value := (cast(u64) color.as_u32) | ((cast(u64) color.as_u32) << 32);
    pixels := surface.width * surface.height;

    for 0..pixels / 2 - 1 {
        << (cast(*u64) surface.buffer + it) = value;
    }
}

Screen_Draw_List_Entry :: struct {
    surface: *Surface;
    x: int;
    y: int;

    transparency: bool;
    shadow: bool;

    next: *Screen_Draw_List_Entry;
    prev: *Screen_Draw_List_Entry;
}

add_surface_to_screen :: (surface: *Surface, x: int, y: int) -> *Screen_Draw_List_Entry {
    entry := *graphics.draw_list_store[graphics.draw_list_size];
    graphics.draw_list_size += 1;
    entry.surface = surface;
    entry.x = x;
    entry.y = y;

    last_entry := *graphics.surfaces;
    while << last_entry {
        last_entry = *(<< last_entry).next;
    }

    entry.prev = << last_entry;
    << last_entry = entry;

    return entry;
}

blend :: (target: Color, source: Color) -> Color #expand {
    t := cast(float) source.a / 255;
    result: Color;

    result.r = cast(u8) (cast(float) target.r * (1 - t) + cast(float) source.r * t);
    result.g = cast(u8) (cast(float) target.g * (1 - t) + cast(float) source.g * t);
    result.b = cast(u8) (cast(float) target.b * (1 - t) + cast(float) source.b * t);

    return result;
}

paint_screen :: () {
    g := *graphics;

    entry := g.surfaces;
    while entry {
        for 0..entry.surface.height-1 {
            target := g.screen_buffer + entry.x;
            target += entry.y * g.screen_width;
            target += it * g.screen_width;

            source := entry.surface.buffer;
            source += it * entry.surface.width;
            count := entry.surface.width;

            if entry.transparency for 0..count-1 {
                source_color := << cast(*Color) (source + it);
                if source_color.a == 0 continue;
                target_color := << cast(*Color) (target + it);

                target[it] = blend(target_color, source_color).as_u32;

                if entry.shadow {
                    source_color := Color.{ as_u32 = 0x00181818 };
                    source_color.a = xx source[it] >> 24;
                    
                    shadow_target := target + 2 + 2 * g.screen_width;
                    target_color := << cast(*Color) (shadow_target + it);
                    shadow_target[it] = blend(target_color, source_color).as_u32;
                }
            } else {
                crt_memcpy(target, source, cast(u64) count * size_of(u32));
            }
        }
        entry = entry.next;
    }

    screen_size := g.screen_width * g.screen_height * size_of(u32);
    crt_memcpy(g.vesa_framebuffer, g.screen_buffer, xx screen_size);
}

init_graphics :: (boot_data: Boot_Data) {
    g := *graphics;

    g.screen_width = VESA_WIDTH;
    g.screen_height = VESA_HEIGHT;

    screen_buffer_size := g.screen_width * g.screen_height * size_of(u32);

    flags := Page_Flags.READ_WRITE | .PRESENT | .PAGE_SIZE;
    g.vesa_framebuffer = map_memory(screen_buffer_size, physical_address = boot_data.vesa_framebuffer, flags);
    g.screen_buffer = map_memory(screen_buffer_size);
}



Text_Viewer :: struct {
    surface: Surface;
    buffer: *u8;
    size: int;
    used: int;

    font: Pnm;
    char_width: int;
    char_height: int;

    attr_count: int;
    attr_buffer: *Attribute;

    shadow: bool;
}

create_text_viewer :: (font: Pnm, surface: Surface) -> Text_Viewer {
    text: Text_Viewer;
    text.buffer = map_memory(0x4000);
    text.size = 0x4000;
    text.font = font;
    text.surface = surface;

    char_count := 95;
    assert(font.width % 95 == 0);

    text.char_width  = font.width / char_count;
    text.char_height = font.height;

    text.attr_buffer = map_memory(0x1000);
    text.shadow = true;

    return text;
}

set_text_color :: (text: *Text_Viewer, color: Color) {
    attribute: Attribute;
    attribute.start_position = text.used;
    attribute.color = color;
    text.attr_buffer[text.attr_count] = attribute;
    text.attr_count += 1;
}

write_to_text_viewer :: (text: *Text_Viewer, message: string) {
    write_to_text_viewer(text, message, theme.foreground);
}

write_to_text_viewer :: (text: *Text_Viewer, message: string, color: Color) {
    assert(text.used + message.count < text.size, "Text buffer overflow");

    crt_memcpy(text.buffer + text.used, message.data, xx message.count);

    set_text_color(text, color);
    text.used += message.count;
}

clear_text_viewer :: (text: *Text_Viewer) {
    text.used = 0;
    text.attr_count = 0;
}

text_viewer_backspace :: (text: *Text_Viewer) {
    if text.used == 0 return;
    text.used -= 1;
    text.buffer[shell.text.used] = 0;
}

render_text_viewer :: (text: *Text_Viewer) {
    surface := *text.surface;
    clear_surface_to_color(surface, .{ as_u32 = 0 });

    cursor_y: int;
    cursor_x: int;

    color := theme.foreground;

    attr_cursor: int;

    for 0..text.used - 1 {
        if text.attr_count > attr_cursor {
            attr := text.attr_buffer[attr_cursor];
            while attr.start_position == it && text.attr_count > attr_cursor {
                color = attr.color;
                attr_cursor += 1;
                attr = text.attr_buffer[attr_cursor];
            }
        }

        char := text.buffer[it];

        if char == 0 continue;
        if char == #char "\r" continue;
        if char == #char "\n" {
            cursor_y += 1;
            cursor_x = 0;
            continue;
        }

        source_top_left := text.char_width * (char - 0x20);
        for y: 0..text.char_height - 1 for x: 0..text.char_width - 1 {
            line := cursor_y * (text.char_height + 2) * surface.width;
            column := cursor_x * text.char_width;

            pixel := line + column + x + y * surface.width;

            if char == 0 surface.buffer[pixel] = 0;
            else {
                index := source_top_left + x + y * text.font.width;
                color.a = cast(u8) text.font.data[index];
                surface.buffer[pixel] = color.as_u32;
            }
        }

        cursor_x += 1;
        if (cursor_x + 1) * text.char_width >= surface.width {
            cursor_x = 0;
            cursor_y += 1;
        }
    }
}












USE_VGA :: !ENABLE_VESA;

Attribute :: struct {
    start_position: int;
    color: Color;
    flags: Text_Flags;
}

Text_Flags :: enum_flags u32 {

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


#if ENABLE_VESA {

    clear_screen :: () {
        shell.text.used = 0;
    }

    theme: Theme;
    Theme :: struct {
        background:  Color = .{ as_u32 = 0xff603038 };
        foreground:  Color = .{ as_u32 = 0xfff8f8f8 };
        primary:     Color = .{ as_u32 = 0xffebbcbc };
        highlight:   Color = .{ as_u32 = 0xffebbcbc };
        accent:      Color = .{ as_u32 = 0xff81c44b };

        shadow: float = 1.0;
    }

    Color :: union {
        as_u32: u32;
        struct {
            b: u8;
            g: u8;
            r: u8;
            a: u8;
        }
    }
    #assert(size_of(Color) == size_of(u32));

    print :: (text: string) {
        print(text, theme.foreground);
    }

    print :: (text: string, color: Color) {
        write_to_text_viewer(*shell.text, text, color);
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

    get_attribute :: () -> u8 #c_call {
        if !USE_VGA return 0;
        return cast(u8) theme.primary | (theme.background << 4);
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

    print :: (text: string, foreground: Color = 255) #c_call {
        if !USE_VGA return;
        fg := ifx foreground == 255 then theme.primary else xx foreground;

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

    print :: (number: int, color: Color = 255) #c_call {
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

    print_hex :: (number: $T, color: Color = 0, decorate := true) #c_call {
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
        background : Color = .BLACK;
        foreground : Color = .WHITE;
        primary    : Color = .CYAN;
        highlight  : Color = .LIGHT_CYAN;
        accent     : Color = .RED;
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

    Color :: enum u8 {
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

    print("\n");
    print(TITLE, theme.primary);
    print("\n\n");

    print("Hello, sailor.\n");

    print("Boot time is ");
    calendar := cmos_get_calendar_time();
    print(Basic.calendar_to_string(calendar));
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
    print(".\n\n");
    print_stack_trace();
}
