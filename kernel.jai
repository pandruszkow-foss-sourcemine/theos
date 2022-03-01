
#program_export
kernel_entry :: () {
    hide_cursor();
    clear_screen();
    vga_attribute(0x10, 3, set = false);

    print(TITLE);
    while true {};
}

port_write :: (port: u16, value: u8) {
    #asm {
        port  === d;
        value === a;
        out.b port, value;
    }
}

port_read :: (port: u16) -> u8 {
    value: u8;
    #asm {
        port  === d;
        value === a;
        in.b value, port;
    }
    return value;
}

TITLE :: #string END
                     /##                             /##      /######   /###### 
                    | ##                            | ##     /##__  ## /##__  ##
  /######   /#######| #######   /######   /####### /######  | ##  \ ##| ##  \__/
 |____  ## /##_____/| ##__  ## /##__  ## /##_____/|_  ##_/  | ##  | ##|  ###### 
  /#######|  ###### | ##  \ ##| ########|  ######   | ##    | ##  | ## \____  ##
 /##__  ## \____  ##| ##  | ##| ##_____/ \____  ##  | ## /##| ##  | ## /##  \ ##
|  ####### /#######/| #######/|  ####### /#######/  | ####/ |  ######/|  ######/
 \______/ |_______/ |_______/  \_______/|_______/    \___/   \______/  \______/
===================< The Jai operating system | Select file >===================
END;

vga_columns :: 80;
vga_rows    :: 25;

cursor: int;
screen_color := cast(u8) Vga_Color.YELLOW | (Vga_Color.GRAY << 4);

print :: (text: string) {
    vga_screen := cast(*u8) 0xb8000;

    for cast([] u8) text {
        if it == 10 {
            distance := cursor % vga_columns;
            if distance > 0 cursor += vga_columns - distance;
            continue;
        }

        if it == 13 continue;

        i := cursor;
        vga_screen[i * 2]     = it;
        vga_screen[i * 2 + 1] = screen_color;

        cursor += 1;
    }
}

clear_screen :: () {
    vga_screen := cast(*u8) 0xb8000;
    for 0..vga_columns * vga_rows - 1 {
        vga_screen[it * 2 + 1] = screen_color;
    }
}

hide_cursor :: () {
    port_write(0x3d4, 0x0a);
    port_write(0x3d5, 0x20);
}

Vga_Ports :: enum u16 {
    INPUT_STATUS      :: 0x3da;
    ATTRIBUTE_ADDRESS :: 0x3c0;
    DATA_READ         :: 0x3c1;
}

vga_attribute :: (register_name: u8, bit: u8, set: bool = true) {
    using Vga_Ports;

    PAS:  u8 = 1 << 5;
    mask: u8 = xx 1 << bit;

    port_read(xx INPUT_STATUS);
    address := port_read(xx ATTRIBUTE_ADDRESS);
    port_write(xx ATTRIBUTE_ADDRESS, register_name | PAS);

    data := port_read(xx DATA_READ);
    if set data |=  mask;
    else   data &= ~mask;

    port_write(xx ATTRIBUTE_ADDRESS, data);
    port_write(xx ATTRIBUTE_ADDRESS, address);
}

Vga_Color :: enum u8 {
    BLACK         :: 0x00;
    BLUE          :: 0x01;
    GREEN         :: 0x02;
    CYAN          :: 0x03;
    RED           :: 0x04;
    MAGENTA       :: 0x05;
    BROWN         :: 0x06;
    WHITE         :: 0x07;
    GRAY          :: 0x08;
    LIGHT_BLUE    :: 0x09;
    LIGHT_GREEN   :: 0x0A;
    LIGHT_CYAN    :: 0x0B;
    LIGHT_RED     :: 0x0C;
    LIGHT_MAGENTA :: 0x0D;
    YELLOW        :: 0x0E;
    BRIGHT_WHITE  :: 0x0F;
}
