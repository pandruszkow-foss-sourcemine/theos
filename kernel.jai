
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

#program_export
kernel_entry :: () {
    vga_screen := cast(*u8) 0xb8000;
    for cast([] u8) "This is a fun test" {
        vga_screen[it_index * 2]     = it;
        vga_screen[it_index * 2 + 1] = 0xfa;
    }

    while true {};
}
