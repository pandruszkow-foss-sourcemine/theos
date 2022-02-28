
port_write_8 :: (port: u16, value: u8) {
    #asm {
        port  === d;
        value === a;
        out.b port, value;
    }
}

port_write_16 :: (port: u16, value: u16) {
    #asm {
        port  === d;
        value === a;
        out.w port, value;
    }
}

cursor: int;

print :: (text: string) {
    vga_screen := cast(*u8) 0xb8000;
    vga_screen += cursor * 2;

    for cast([] u8) text {
        vga_screen[it_index * 2]     = it;
        vga_screen[it_index * 2 + 1] = 0x05;
    }

    cursor += text.count;
}

#program_export
kernel_entry :: () {
    port_write_8(0x3d4, 0x0a);
    port_write_8(0x3d5, 0x20);

    print("Hello, sailor");
    while true {};
}
