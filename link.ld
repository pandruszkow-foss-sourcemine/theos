
ENTRY(kernel_entry)

SECTIONS {
    . = 0x100000;
    .text   : { * (.text);  }
    .rodata : { * (.rodata);  }
    .data   : { * (.data);  }
    .bss    : { * (.bss);  }
}
