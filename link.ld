
ENTRY(kernel_entry)

SECTIONS {
    . = 0x100000;
    .rodata : { * (.rodata);  }
    . = 0x105000;
    .data   : { * (.data);  }
    . = 0x107000;
    .text   : { * (.text);  }
    . = 0x110000;
    .bss   : { * (.bss);  }
}
