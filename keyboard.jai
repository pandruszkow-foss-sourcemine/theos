
scan_table         :: "\0#1234567890-=\0\tqwertyuiop[]\0\0asdfghjkl;'`\0\\zxcvbnm,./\0*\0 ";
scan_table_shifted :: "\0#!@#$%^&*()_+\0\0QWERTYUIOP{}\0\0ASDFGHJKL:\"~\0|ZXCVBNM<>?\0*\0 ";

keyboard_state: struct {
    shift: bool;
    color: Color;
}

key_buffer: struct {
    size :: 32;
    buffer: [size] Keyboard_Scan_Code;
    read_index: int;
    write_index: int;
}

read_key_buffer :: () -> Keyboard_Scan_Code {
    using key_buffer;
    if read_index == write_index return .NONE;

    key := buffer[read_index];

    read_index += 1;
    read_index %= size;

    return key;
}

write_key_buffer :: (key: Keyboard_Scan_Code) #no_context {
    using key_buffer;

    buffer[write_index] = key;

    write_index += 1;
    write_index %= size;
}

#program_export
ps2_interrupt :: () #c_call {
    defer pic_end_of_interrupt(0x1);
    key := port_read(0x60);
    write_key_buffer(cast(Keyboard_Scan_Code) key);
}

scroll_position: int;
handle_keyboard_events :: () {
    while true {
        scan_code := read_key_buffer();
        if scan_code == .NONE return;
        key := cast(u8) scan_code;

        if key >= 0x80 {
            scan_code -= xx 0x80;
            if scan_code == .LSHIFT {
                keyboard_state.shift = false;
            }
            continue;
        }

        if scan_code == .LSHIFT {
            keyboard_state.shift = true;
        }

        else if scan_code == .W {
            scroll_position += 1;
        }

        else if scan_code == .S {
            scroll_position -= 1;
        }

        else if scan_code == .ENTER {
            // message: string;
            // message.data = vesa.text_viewer + vesa.cursor - vesa.cursor_x + 2;
            // message.count = vesa.cursor_x - 2;
            // print("\n");
            // run_command(message);
            // print("> ");
            // keyboard_state.color = theme.primary;
        }

        else if scan_code == .BACKSPACE {
            text_viewer_backspace(*shell.text);
        }

        else {
            char: string;
            if keyboard_state.shift {
                char.data = *scan_table_shifted[key];
            } else {
                char.data = *scan_table[key];
            }
            char.count = 1;
            if << char.data == #char " " keyboard_state.color = theme.accent;
            print(char, keyboard_state.color);
        }

        paint_screen();
    }
}

Shell :: struct {
    text: Text_Viewer;
    command_text: Text_Viewer;
    command_buffer: [128] u8;
    command_buffer_size: int;
    background: Solid_Color;
}

shell: Shell;
init_shell :: (font: Pnm) {
    shell.background.color = theme.background;
    shell.background.draw.width = graphics.screen_width;
    shell.background.draw.height = graphics.screen_height;
    add_screen_draw_list_entry(*shell.background, 0, 0);

    shell.text         = create_text_viewer(font);
    // shell.command_text = create_text_viewer(font);

    add_screen_draw_list_entry(*shell.text, 70, 70);
    shell.text.draw.width = 700;
    shell.text.draw.height = graphics.screen_height - 2 * 70;

    // add_screen_draw_list_entry(*shell.command_text, 70, 70);
    // shell.command_text.draw.width = 700;
    // shell.command_text.draw.height = graphics.screen_height - 2 * 70;
}

shell_run_command :: (command_string: string) {
    if !command_string.count return;

    is_whitespace :: (char: u8) -> bool {
        return char == #char " " || char == #char "\n" || char == 0;
    }

    name: string;
    name.data = command_string.data;
    while is_whitespace(<< name.data) {
        name.data += 1;
    }

    while !is_whitespace(command_string[name.count]) {
        name.count += 1;
    }

    if name == {
      case "theos";
        clear_screen();
        welcome_screen();
      case "clear";
        clear_screen();
      case "pci.list";
        print("\n");
        pci_print_device_list();
        print("\n");
      case "pci.scan";
        print("Scanning PCI devices...\n");
        pci_scan_all_devices();
        print("Found "); print(pci_device_count); print(".\n\n");
      case "fs.list";
        print("\n");
        print_file_list();
        print("\n");
      case "wait";
        wait_for_seconds(1);
      case "fs.read";
        filename: string;
        filename.count = command_string.count - name.count - 1;
        filename.data = command_string.data + name.count + 1;

        for 0..file_count - 1 {
            file := files[it];
            if file.name == filename {
                    content: string;
                    content.data = file.data;
                    content.count = file.size;
                if file.type == .TEXT {
                    print("\n");
                    print(content);
                    print("\n");
                }
                break;
            }
        }
      case "trace";
        print("\n");
        print_stack_trace();
      case "random";
        print_hex(random());
        print("\n");
      case "time";
        print("\n");
        calendar := cmos_get_calendar_time();
        print(Basic.calendar_to_string(calendar));
        print(".\n\n");
      case "exec";
        for 0..file_count - 1 {
            file := files[it];
            filename: string;
            filename.count = command_string.count - name.count - 1;
            filename.data = command_string.data + name.count + 1;

            if file.name == filename {
                load_elf(it);
                print("\n");
                break;
            }

            if it == file_count - 1 {
                print("Program not found: "); print(filename); print("\n");
            }
        }
      case;
        print("command not found: \"");
        print(name);
        print("\"\n");
    }
}

enable_ps2_keyboard :: () {
    pic_enable_irq(0x1);
    keyboard_state.color = theme.primary;
}






Keyboard_Scan_Code :: enum u8 {
    NONE;
    ESC;
    NUM1;
    NUM2;
    NUM3;
    NUM4;
    NUM5;
    NUM6;
    NUM7;
    NUM8;
    NUM9;
    NUM0;
    DASH;
    EQUAL;
    BACKSPACE;
    TAB;
    Q;
    W;
    E;
    R;
    T;
    Y;
    U;
    I;
    O;
    P;
    OPEN_BRACKET;
    CLOSED_BRACKET;
    ENTER;
    CTRL;
    A;
    S;
    D;
    F;
    G;
    H;
    J;
    K;
    L;
    SEMICOLON;
    APOSTROPHE;
    BACKTICK;
    LSHIFT;
    BACKSLASH;
    Z;
    X;
    C;
    V;
    B;
    N;
    M;
    COMMA;
    PERIOD;
    FORWARDSLASH;
    RSHIFT;
    ASTERISK;
    ALT;
    SPACE;
    CAPSLOCK;
    F1;
    F2;
    F3;
    F4;
    F5;
    F6;
    F7;
    F8;
    F9;
    F10;
    NUMLOCK;
}
