
ENTRY(kernel_entry)

SECTIONS {
    . = 0x100000;
    .rodata : { * (.rodata);  }
    .data   : { * (.data);  }
    .text   : { * (.text);  }
    .bss   : { * (.bss);  }
}
