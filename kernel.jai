
#program_export
kernel_entry :: () #c_call {
    vga_screen := cast(*u8) 0xb8000;
    for cast([] u8) "This is a fun test" {
        vga_screen[it_index * 2]     = it;
        vga_screen[it_index * 2 + 1] = 0xfa;
    }

    while true {};
}

dummy_entry :: () {
    kernel_entry();
}
