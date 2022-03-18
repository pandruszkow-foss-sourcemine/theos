
ENTRY(entry)

SECTIONS {
    . = 0x300000;
    .text   : { * (.text);  }
    .rodata : { * (.rodata);  }
    .data   : { * (.data);  }
    .bss    : { * (.bss);  }
}
