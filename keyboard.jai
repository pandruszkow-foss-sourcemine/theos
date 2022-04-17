
scan_table         :: "\0#1234567890-=\0\tqwertyuiop[]\0\0asdfghjkl;'`\0\\zxcvbnm,./\0*\0 ";
scan_table_shifted :: "\0#!@#$%^&*()_+\0\0QWERTYUIOP{}\0\0ASDFGHJKL:\"~\0|ZXCVBNM<>?\0*\0 ";

Key_Buffer :: struct {
    size :: 32;
    buffer: [size] Keyboard_Scan_Code;
    read_index: int;
    write_index: int;
}

read_key_buffer :: (key_buffer: *Key_Buffer) -> Keyboard_Scan_Code {
    using key_buffer;
    if read_index == write_index return .NONE;

    key := buffer[read_index];

    read_index += 1;
    read_index %= size;

    return key;
}

write_key_buffer :: (key_buffer: *Key_Buffer, key: Keyboard_Scan_Code) #no_context {
    using key_buffer;

    buffer[write_index] = key;

    write_index += 1;
    write_index %= size;
}

input_key_buffer: Key_Buffer;

#program_export
ps2_interrupt :: () #c_call {
    defer pic_end_of_interrupt(0x1);
    key := port_read(0x60);
    write_key_buffer(*input_key_buffer, cast(Keyboard_Scan_Code) key);
}

handle_keyboard_events :: () {
    while true {
        scan_code := read_key_buffer(*input_key_buffer);
        if scan_code == .NONE return;
        write_key_buffer(*shell.key_buffer, scan_code);
    }
}

Shell :: struct {
    text: Text_Viewer;
    command_text: Text_Viewer;
    command_buffer: [128] u8;
    command_buffer_size: int;
    background: Solid_Color;

    key_buffer: Key_Buffer;
    shift_held: bool;
}

shell: Shell;
init_shell :: (font: Pnm) {
    shell.background.color = theme.background;
    shell.background.draw.width = graphics.screen_width;
    shell.background.draw.height = graphics.screen_height;
    add_screen_draw_list_entry(*shell.background, 0, 0);

    shell.text         = create_text_viewer(font);
    shell.command_text = create_text_viewer(font);

    add_screen_draw_list_entry(*shell.text, 70, 70);
    shell.text.draw.width = 700;
    shell.text.draw.height = graphics.screen_height - 2 * 70 - 50;

    add_screen_draw_list_entry(*shell.command_text, 70, graphics.screen_height - 50);
    shell.command_text.draw.width = 700;
    shell.command_text.draw.height = graphics.screen_height - 2 * 70;
    write_to_text_viewer(*shell.command_text, "> ");
}

update_shell :: () {
    shell_handle_keypress();
    time := cmos_get_calendar_time();
    if xx (time.second % 2) == shell.command_text.point {
        shell.command_text.point = !shell.command_text.point;
        paint_screen();
    }
}

shell_handle_keypress :: () -> bool {
    scan_code := read_key_buffer(*shell.key_buffer);
    if scan_code == .NONE return false;

    while true {
        key := cast(u8) scan_code;

        if key >= 0x80 {
            scan_code -= xx 0x80;
            if scan_code == .LSHIFT {
                shell.shift_held = false;
            }
        }

        else if scan_code == .LSHIFT {
            shell.shift_held = true;
        }

        else if scan_code == .ENTER {
            message: string;
            message.data = shell.command_text.buffer + 2;
            message.count = shell.command_text.used - 2;
            shell.command_text.buffer[shell.command_text.used] = 0;
            shell_run_command(message);
            clear_text_viewer(*shell.command_text);
            write_to_text_viewer(*shell.command_text, "> ");
        }

        else if scan_code == .BACKSPACE {
            if shell.command_text.used > 2 {
                text_viewer_backspace(*shell.command_text);
            }
        }

        else {
            char: string;
            if shell.shift_held {
                char.data = *scan_table_shifted[key];
            } else {
                char.data = *scan_table[key];
            }
            char.count = 1;
            write_to_text_viewer(*shell.command_text, char);
        }

        scan_code = read_key_buffer(*shell.key_buffer);
        if scan_code == .NONE break;
    }
    paint_screen();
    return true;
}

shell_run_command :: (command_string: string) {
    if !command_string.count return;

    name: string;
    name.data = command_string.data;
    name.count = command_string.count;

    if name == {
      case "theos";
        welcome_screen();
      case "quit";
        shutdown_emulator();
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
        print("Command length was: "); print(name.count);
        print("\n");
    }
}

enable_ps2_keyboard :: () {
    pic_enable_irq(0x1);
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
