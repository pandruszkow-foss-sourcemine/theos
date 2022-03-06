
#program_export
kernel_entry :: () {
    hide_vga_cursor();
    vga_attribute(0x10, 3, set = false);

    random_seed = rdtsc();

    // vga_set_palette_entry(xx Vga_Color.CYAN, 0xff, 0xff, 0xff);

    screen_color = cast(u8) Vga_Color.LIGHT_CYAN | (Vga_Color.BLACK << 4);
    clear_screen();
    print(TITLE);

    idt_init();
    pic_init();
    enable_ps2_keyboard();

    gol();
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

io_delay :: () {
    #asm {
        zero: gpr === a;
        xor zero, zero;
        out.b 0x80, zero;
    }
}

rdtsc :: () -> u64 {
    upper, lower: u64;
    #asm {
        upper === d;
        lower === a;
        rdtsc upper, lower;
    }
    return lower | (upper << 32);
}

random_seed: u64;

random :: (state: *u64) -> u64 {
    x := << state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;

    << state = x;
    return x * 0x2545F4914F6CDD1D;
}

wait :: (time: int = 10) {
    for 1..1000000 * time { x := it; }
}



Isr_Stack_Frame :: struct {
    ip:    u64;
    cs:    u64;
    flags: u64;
    sp:    u64;
    ss:    u64;
}

Idt_Entry :: struct {
    offset_1: u16;
    selector: u16;
    ist:      u8;
    flags:    u8;
    offset_2: u16;
    offset_3: u32;
    reserved: u32;
} #no_padding

idt_desc: struct {
    limit: u16;
    base:  *void #align 2;
}

idt: [0x100] Idt_Entry;

idt_add_handler :: (address: *void, index: int) {
    _address := cast(u64) address;

    entry: Idt_Entry = ---;
    entry.offset_1  = xx  _address        & 0xffff;
    entry.offset_2  = xx (_address >> 16) & 0xffff;
    entry.offset_3  = xx (_address >> 32) & 0xffffffff;
    entry.selector  = 0b00001000;
    entry.ist       = 0x0;
    entry.flags     = 0x8e;
    entry.reserved  = 0x0;

    idt[index] = entry;
}

idt_init :: () {
    idt_desc.limit = 0x100 * size_of(Idt_Entry);
    idt_desc.base = *idt;

    register_generated_isrs();

    address := *idt_desc;
    #asm {
        lidt [address];
    }
}



Pic_Port :: enum u16 {
    MASTER_CMD  :: 0x20;
    MASTER_DATA :: 0x21;
    SLAVE_CMD   :: 0xa0;
    SLAVE_DATA  :: 0xa1;
}

Pic_Command :: enum u8 {
    INITIALIZE       :: 0x11;
    END_OF_INTERRUPT :: 0x20;
}

pic_init :: () {
    using Pic_Port;
    using Pic_Command;

    mask: u8 = port_read(xx MASTER_CMD);

    port_write(xx MASTER_CMD, xx INITIALIZE);
    port_write(xx MASTER_DATA, 0x20);
    port_write(xx MASTER_DATA, 0x4);
    port_write(xx MASTER_DATA, 1);
    port_write(xx MASTER_DATA, mask);
    port_write(xx MASTER_DATA, 0xff);

    mask = port_read(xx SLAVE_CMD);

    port_write(xx SLAVE_CMD, xx INITIALIZE);
    port_write(xx SLAVE_DATA, 0x28);
    port_write(xx SLAVE_DATA, 0x2);
    port_write(xx SLAVE_DATA, 1);
    port_write(xx SLAVE_DATA, mask);
    port_write(xx SLAVE_DATA, 0xff);

    #asm { sti; }
}

pic_enable_irq :: (irq: u8) {
    using Pic_Port;
    port: u8 = xx MASTER_DATA;

    if irq > 7 {
        irq -= 8;
        port = xx SLAVE_DATA;
    }

    mask: u8 = xx ~(1 << irq);
    value: u8 = port_read(port) & mask;

    port_write(port, value);
}



keyboard_isr :: () {
    print("A key has been pressed.");
    while true {}
}

enable_ps2_keyboard :: () {
    idt_add_handler(xx keyboard_isr, 0x21);
    pic_enable_irq(0x1);
}



TITLE :: #string END
                 /##     /##                                                  
                | ##    | ##                                                  
               /######  | #######   /######   /######   /#######              
              |_  ##_/  | ##__  ## /##__  ## /##__  ## /##_____/              
                | ##    | ##  \ ##| ########| ##  \ ##|  ######               
                | ## /##| ##  | ##| ##_____/| ##  | ## \____  ##              
                |  ####/| ##  | ##|  #######|  ######/ /#######/              
                 \___/  |__/  |__/ \_______/ \______/ |_______/               
              
================================================================================
END;

vga_columns :: 80;
vga_rows    :: 25;

text_cursor: int;
screen_color := cast(u8) Vga_Color.YELLOW | (Vga_Color.GRAY << 4);
vga_screen :: cast(*u8) 0xb8000;

print :: (text: string) {
    for cast([] u8) text {
        if it == 10 {
            distance := text_cursor % vga_columns;
            text_cursor += vga_columns - distance;
            continue;
        }

        if it == 13 continue;

        i := text_cursor;
        vga_screen[i * 2]     = it;
        vga_screen[i * 2 + 1] = screen_color;

        text_cursor += 1;
    }
}

print_hex :: (number: $T) {
    #assert type_info(T).type == .INTEGER;
    size := #run type_info(T).runtime_size;

    print("0x");

    table := "0123456789abcdef";
    for 0..size * 2 {
        index := number >> (it * 4);
        index &= 0xf;

        vga_screen[(text_cursor + size * 2 - it) * 2] = table[index];
    }
    text_cursor += size * 2;
    text_cursor += 1;
}

set_colors :: (foreground: Vga_Color, background: Vga_Color) {
    for 0..vga_columns * vga_rows - 1 {
    }
}

clear_screen :: () {
    for 0..vga_columns * vga_rows - 1 {
        vga_screen[it * 2]     = 0;
        vga_screen[it * 2 + 1] = screen_color;
    }
    text_cursor = 0;
}

Vga_Registers :: enum u16 {
    ATTRIBUTE_ADDRESS :: 0x3c0;
    DATA_READ         :: 0x3c1;
    DAC_PALETTE_MASK  :: 0x3c6;
    DAC_STATE         :: 0x3c7;
    DAC_ADDRESS_READ  :: 0x3c7;
    DAC_ADDRESS_WRITE :: 0x3c8;
    DAC_DATA          :: 0x3c9;
    CRT_CONTROL_INDEX :: 0x3d4;
    CRT_CONTROL_DATA  :: 0x3d5;
    INPUT_STATUS      :: 0x3da;
}

hide_vga_cursor :: () {
    using Vga_Registers;

    port_write(xx CRT_CONTROL_INDEX, 0x0a);
    port_write(xx CRT_CONTROL_DATA,  0x20);
}

vga_set_palette_entry :: (index: u8, red: u8, green: u8, blue: u8) {
    using Vga_Registers;

    port_write(xx DAC_PALETTE_MASK, 0xff);
    port_write(xx DAC_ADDRESS_WRITE, index);
    port_write(xx DAC_DATA, red);
    port_write(xx DAC_DATA, green);
    port_write(xx DAC_DATA, blue);
}

vga_attribute :: (register_name: u8, bit: u8, set: bool = true) {
    using Vga_Registers;

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
    LIGHT_GREEN   :: 0x0a;
    LIGHT_CYAN    :: 0x0b;
    LIGHT_RED     :: 0x0c;
    LIGHT_MAGENTA :: 0x0d;
    YELLOW        :: 0x0e;
    BRIGHT_WHITE  :: 0x0f;
}














/*
p :: (value: u64) -> bool {
    return (random(*seed) % value) == 0;
}

width := 640;
height := 480;

funky :: () {
    range: u8 = 72;
    base:  u8 = 0x20;
    count: u8 = 5;

    for 0..width * height - 1 {
        vga_screen[it] = 0;
    }

    for 0..10000000 for 0..width * height * 2 - 1 {
        if !p(1)  continue;
        color := vga_screen[it];

        if color == 0 && p(2000) {
            vga_screen[it] = (base + cast(u8) random(*seed) % 10) * 3;
        }
        else if color >= base && color < base + range + range {

            if p(1) {
                x := random(cast(*s64) *seed) % 2;
                y := random(cast(*s64) *seed) % 2;
                other := vga_screen[it + x + y * width]; // = vga_screen[it];
                if (other % 2) != (color % 2)  vga_screen[it] = other;
                else vga_screen[it + x + y * width] = vga_screen[it];
            }

            if p(3) vga_screen[it] += range;
        }
        else vga_screen[it] = 0;
    }
}
*/


gol :: () {
    width := vga_columns;
    height := vga_rows;

    count := width * height;
    buffer_a: *u8 = xx 0x110000;
    buffer_b: *u8 = buffer_a + count;
    for 0..count-1 buffer_a[it] = 0;

    for 0..TITLE.count - 1 {
        // buffer_a[it] = xx (random(*random_seed) & 1);
        buffer_a[it + width * 10] = xx ifx TITLE[it] == #char "#" then 1 else 0;
    }

    for 0..count - 1 {
        if buffer_a[it] > 0 vga_screen[it * 2 + 1] = 0xff;
        else                vga_screen[it * 2 + 1] = 0x00;
    }
    wait(20);

    read :: (x: int, y: int) -> bool #expand {
        if y < 0 || y > height-1 || x < 0 || x > width-1 return false;
        return `buffer_a[x + y * width] > 0; // `
    }

    write :: (x: int, y: int, value: bool) #expand {
        index := x + y * width;
        if value `buffer_b[index] = 1;
        else `buffer_b[index] = 0;
    }

    while true {
        for y: 0..height-1 for x: 0..width-1 {
            sum: int;
            sum += xx read(x-1, y-1);
            sum += xx read(x-1, y  );
            sum += xx read(x-1, y+1);
            sum += xx read(x  , y-1);

            sum += xx read(x  , y+1);
            sum += xx read(x+1, y-1);
            sum += xx read(x+1, y  );
            sum += xx read(x+1, y+1);
            if sum < 2 write(x, y, false);
            else if sum > 3 write(x, y, false);
            else if sum == 3 write(x, y, true);
            else write(x, y, read(x, y));
        }

        for 0..count - 1 {
            if buffer_b[it] > 0 vga_screen[it * 2 + 1] = 0xff;
            else                vga_screen[it * 2 + 1] = 0x00;
        }

        temp := buffer_a;
        buffer_a = buffer_b;
        buffer_b = temp;
        wait(2);
    }
}
