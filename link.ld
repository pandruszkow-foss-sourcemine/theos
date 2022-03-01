
ENTRY(kernel_entry)

SECTIONS {
    . = 0x100000;
    .rodata : { * (.rodata);  }
    . = 0x107000;
    .data   : { * (.data);  }
    . = 0x10e000;
    .text   : { * (.text);  }
    . = 0x110000;
    .bss   : { * (.bss);  }
}
