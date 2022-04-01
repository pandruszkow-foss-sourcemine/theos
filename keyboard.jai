
scan_table         :: "\0#1234567890-=\0\tqwertyuiop[]\0\0asdfghjkl;'`\0\\zxcvbnm,./\0*\0 ";
scan_table_shifted :: "\0#!@#$%^&*()_+\0\0QWERTYUIOP{}\0\0ASDFGHJKL:\"~\0|ZXCVBNM<>?\0*\0 ";

keyboard_state: struct {
    shift: bool;
    color: Color;
}

kbd :: () #c_call {
    PushAll();
    push_context .{} {
        defer pic_end_of_interrupt(0x1);

        key := port_read(0x60);

        if key < 0x80 {
            if key == xx Keyboard_Scan_Code.LSHIFT {
                keyboard_state.shift = true;
            }

            else if scan_table[key - 1] == #char "]" {
                message: string;
                message.data = vesa.text_buffer + vesa.cursor - vesa.cursor_x + 2;
                message.count = vesa.cursor_x - 2;
                print("\n");
                run_command(message);
                print("> ");
                keyboard_state.color = theme.primary;
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

            vesa_draw_frame();
        } else {
            key -= 0x80;
            if key == xx Keyboard_Scan_Code.LSHIFT {
                keyboard_state.shift = false;
            }
        }
    }
    PopAll();
}

run_command :: (command_string: string) {
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
                    print(content);
                } else {
                    vesa_blit(parse_pnm(content.data));
                }
                break;
            }
        }
      case "time";
        print_cmos_datetime_string();
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

keyboard_isr :: () #no_call {
    #asm {
        cli;
    }

    kbd();

    #asm {
        sti;
        iret.q;
    }
}

enable_ps2_keyboard :: () {
    idt_add_handler(xx keyboard_isr, 0x21);
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
