
#import "Machine_X64";
#load "elf/elf.jai";
#load "pci.jai";

cpu: Cpu_X86;

#program_export
kernel_entry :: () {

    //     << cast(*u64) 0xb8000 = 85204958398235235;
    // print("Testing.");
    // while true {}

    idt_init();
    pic_init();
    cmos_init();
    page_table_init();

    pci_scan_all_devices();
    cpu = get_cpu_info();

    vga_hide_cursor();
    vga_attribute(0x10, 3, set = false);
    random_seed = rdtsc();
    enable_ps2_keyboard();

    clear_screen();
    read_zip_files();
    // load_elf(0);
    // print("\nExecuted the program.\n");

    pci_scan_all_devices();
    // pci_print_device_list();
    // welcome_screen();

    print("\n");
    for files {
        contents: string;
        contents.data = it.data;
        contents.count = it.size;
        print(contents);
        
        print("\n\n");
    }
    new_page();
    hda_detect();

    while true {};
    wait(50);
    gol();
}

crt_memset :: (target: *u8, value: s32, count: u64) -> *void #c_call {
    for 0..count-1 {
        target[it] = cast(u8) value;
    }
    return target;
}

crt_memcpy :: (dest: *u8, src: *u8, count: u64) -> *void #c_call {
    for 0..count-1 {
        dest[it] = src[it];
    }
    return dest;
}

assert :: (condition: bool) {
    if !condition {
        print("Assertion failure!\n");
        while true {
            // #asm { hlt; }
        }
    }
}

out :: (port: u16, value: $T) {
    #asm {
        port  === d;
        value === a;
    }
    #if T == u8  #asm { out.b port, value; }
    #if T == u16 #asm { out.w port, value; }
    #if T == u32 #asm { out.d port, value; }
}

in :: (port: u16, $T: Type = u32) -> T {
    value: T;    
    #asm {
        port  === d;
        value === a;
    }
    #if T == u8  #asm { in.b value, port; }
    #if T == u16 #asm { in.w value, port; }
    #if T == u32 #asm { in.d value, port; }
    return value;
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

random_seed: u64;

random :: (state: *u64 = *random_seed) -> u64 {
    x := << state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;

    << state = x;
    return x * 0x2545f4914f6cdd1d;
}

wait :: (time: int = 10) {
    for 1..1000 * time { x := it; }
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
}

idt_desc: struct {
    limit: u16;
    base:  *void #align 2;
}

#assert(size_of(Idt_Entry)          == 16);
#assert(size_of(type_of(idt_desc))  == 10);

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

    if irq >= 8 {
        irq -= 8;
        port = xx SLAVE_DATA;
    }

    mask:  u8 = xx ~(1 << irq);
    value: u8 = port_read(port) & mask;
    port_write(port, value);
}

scan_table         :: "\0#1234567890-=\0\tqwertyuiop[]\0\0asdfghjkl;'`\0\\zxcvbnm,./\0*\0 ";
scan_table_shifted :: "\0#!@#$%^&*()_+\0\0QWERTYUIOP{}\0\0ASDFGHJKL:\"~\0|ZXCVBNM<>?\0*\0 ";

keyboard_isr :: () {
    print("A key has been pressed: '");
    key := port_read(0x60);

    char: string;
    char.data = *scan_table[key];
    char.count = 1;
    print(char);
    print("'\n");
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
END;


welcome_screen :: () {
    clear_screen();

    print("\n\n");
    print(TITLE);
    print("\n");

    old_foreground := theme.normal;
    theme.normal = theme.foreground;
    print("      Hello, sailor.\n");
    print("      Boot time is ");

    print(weekdays[cmos_read(.WEEKDAY) - 1]);
    print(" ");
    print(months[cmos_read(.MONTH) - 1]);
    print(" ");
    print(cmos_read(.DAY_OF_THE_MONTH));
    print(", ");
    print(cmos_read(.YEAR) + 2000);
    print(", ");

    hours := cmos_read(.HOURS);
    if hours < 10 print("0"); print(hours);
    print(":");

    minutes := cmos_read(.MINUTES);
    if minutes < 10 print("0"); print(minutes);
    print(":");

    seconds := cmos_read(.SECONDS);
    if seconds < 10 print("0"); print(seconds);
    print(".\n");

    print("      There are ");
    print(file_count);
    print(" files in the mailbag.\n");

    print("\n");
    theme.normal = old_foreground;

    ti := type_info(x86_Feature_Flag);
    print("      Supported CPU features: -------------------------------------------", theme.foreground);
    flags_on_this_line: int;
    for 0..ti.names.count-1 {
        if check_feature(cpu.feature_leaves, xx ti.values[it]) {
            name := ti.names[it];
            if name.count >= 8 continue;

            if (flags_on_this_line % 7) == 0 print("\n      ");

            print("| ", theme.foreground);
            print(name, theme.highlight);
            for 1..8 - name.count  print(" ");
            flags_on_this_line += 1;
        }
    }
    print("\n      -------------------------------------------------------------------\n", theme.foreground);

    print("      Compiled using ");
    print("Jai ", theme.accent);
    print(COMPILER_VERSION, theme.accent);
    print(".\n");
}



vga_columns :: 80;
vga_rows    :: 25;

indent: int;
margin: int = 2;
text_cursor: int;
vga_screen :: cast(*u8) 0xb8000;

get_attribute :: () -> u8 {
    return cast(u8) theme.normal | (theme.background << 4);
}

new_page :: () {
    furthest: int;

    for y: 0..vga_rows - 1 {
        for x: 0..vga_columns - 1 {
            cell := y * vga_columns + x;
            if vga_screen[cell * 2] != 0 && vga_screen[cell * 2] != #char " " {
                if x > furthest furthest = x;
            }
        }
    }

    for 0..vga_rows-1 {
        cell := it * vga_columns + furthest + 3;
        vga_screen[cell * 2] = 0xba;
    }

    indent = furthest + 4;
    text_cursor = margin;
}

print :: (text: string, foreground: Vga_Color = 255, background: Vga_Color = 255) {
    fg := ifx foreground == 255 then theme.normal else xx foreground;
    bg := ifx background == 255 then theme.background else xx background;

    for cast([] u8) text {
        if it == 10 {
            distance := text_cursor % vga_columns;
            text_cursor += vga_columns - distance;
            text_cursor += margin;
            continue;
        }

        if it == 13 continue;

        i := text_cursor + indent;
        if (i+1) % vga_columns == 0 {
            text_cursor += indent + margin + margin;
        }

        vga_screen[i * 2]     = it;
        vga_screen[i * 2 + 1] = cast(u8) fg | (bg << 4);

        text_cursor += 1;
    }
}

print :: (number: int, color: Vga_Color = 255) {
    c := color;
    if c == 255 c = theme.foreground;

    negative: bool;
    buffer: [30] u8 = ---;

    _number := number;
    if number < 0 _number *= -1;

    for 0..buffer.count - 1 {
        rem := _number % 10;
        buffer[29 - it] =  #char "0" + cast(u8) rem;
        _number /= 10;

        if _number == 0 {
            result: string = ---;
            result.data = buffer.data + 29 - it;
            result.count = it + 1;
            print(result, color);
            return;
        }
    }
}

print_hex :: (number: $T, decorate := true) {
    #assert type_info(T).type == .INTEGER;
    size := #run type_info(T).runtime_size;

    if decorate print("0x");

    table := "0123456789abcdef";
    for 0..size * 2 - 1 {
        index := number >> (it * 4);
        index &= 0xf;

        cur := (text_cursor + indent + size * 2 - it - 1) * 2;
        vga_screen[cur] = table[index];
        vga_screen[cur + 1] = get_attribute();
    }
    text_cursor += size * 2;
}

debug :: (message: string, number: int, hex := false) {
    print(message);
    print(": ");
    if hex print_hex(number);
    else print(number);
    print("\n");
}

clear_screen :: () {
    for 0..vga_columns * vga_rows - 1 {
        vga_screen[it * 2]     = 0;
        vga_screen[it * 2 + 1] = get_attribute();
    }
    text_cursor = 0;
}

theme: struct {
    background : Vga_Color = .BLACK;
    foreground : Vga_Color = .WHITE;
    normal     : Vga_Color = .CYAN;
    highlight  : Vga_Color = .LIGHT_CYAN;
    accent     : Vga_Color = .RED;
}

Vga_Register :: enum u16 {
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

vga_hide_cursor :: () {
    using Vga_Register;

    port_write(xx CRT_CONTROL_INDEX, 0x0a);
    port_write(xx CRT_CONTROL_DATA,  0x20);
}

vga_set_palette_entry :: (index: u8, red: u8, green: u8, blue: u8) {
    using Vga_Register;

    port_write(xx DAC_PALETTE_MASK, 0xff);
    port_write(xx DAC_ADDRESS_WRITE, index);
    port_write(xx DAC_DATA, red);
    port_write(xx DAC_DATA, green);
    port_write(xx DAC_DATA, blue);
}

vga_attribute :: (register_name: u8, bit: u8, set: bool = true) {
    using Vga_Register;

    PAS : u8 :    1 << 5;
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



cmos_format: struct {
    bcd_mode: bool;
    twenty_four_h: bool;
}

Cmos_Port :: enum u16 {
    ADDRESS :: 0x70;
    DATA    :: 0x71;
}

Cmos_Register :: enum u8 {
    SECONDS          :: 0x00;
    MINUTES          :: 0x02;
    HOURS            :: 0x04;
    WEEKDAY          :: 0x06;
    DAY_OF_THE_MONTH :: 0x07;
    MONTH            :: 0x08;
    YEAR             :: 0x09;
    CENTURY          :: 0x32;
    STATUS_REG_A     :: 0x0a;
    STATUS_REG_B     :: 0x0b;
    STATUS_REG_C     :: 0x0c;
}

cmos_init :: () {
    status := cmos_read(.STATUS_REG_B);
    cmos_format.bcd_mode      = status & 0b10 > 0;
    cmos_format.twenty_four_h = status & 0b01 > 0;
}

cmos_read :: ($register: Cmos_Register) -> u8 {
    using Cmos_Port;

    port_write(xx ADDRESS, xx register);
    io_delay();
    result := port_read(xx DATA);

    #if register < .STATUS_REG_A {
        if cmos_format.bcd_mode {
            result = (result & 0xf) + (result / 16) * 10;
        }
    }

    return result;
}

months :: string.[
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];

weekdays :: string.[
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
];

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
    buffer_a: *u8 = xx 0x130000;
    buffer_b: *u8 = buffer_a + count;

    for 0..count - 1 {
        c := vga_screen[it * 2];
        buffer_a[it] = xx (c != 0 && c != #char " ");
        if buffer_a[it] > 0 vga_screen[it * 2 + 1] = 0x0f;
        else                vga_screen[it * 2 + 1] = 0xf0;

        wait(3);
    }
    wait(10000);

    read :: (x: int, y: int) -> bool #expand {
        if y < 0        y += height;
        if y > height-1 y -= height;
        if x < 0        x += width;
        if x > width-1  x -= width;

        return buffer_a[x + y * width] > 0;
    }

    write :: (x: int, y: int, value: bool) #expand {
        index := x + y * width;
        if value buffer_b[index] = 1;
        else buffer_b[index] = 0;
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
            if buffer_b[it] > 0 vga_screen[it * 2 + 1] = 0x0f;
            else                vga_screen[it * 2 + 1] = 0xf0;
        }

        temp := buffer_a;
        buffer_a = buffer_b;
        buffer_b = temp;
        wait(600);
    }
}



page_table: [0x200] u64 #align 0x1000;
page_dir:   [0x200] u64 #align 0x1000;
pdpt:       [0x200] u64 #align 0x1000;
pml4:       [0x200] u64 #align 0x1000;

Page_Table_Flags :: enum_flags u64 {
    PRESENT         :: 1 << 0;
    READ_WRITE      :: 1 << 1;
    USER_SUPERVISOR :: 1 << 2;
    WRITE_THROUGH   :: 1 << 3;
    CACHE_DISABLE   :: 1 << 4;
    ACCESSED        :: 1 << 5;
    AVAILABLE       :: 1 << 6;
    PAGE_SIZE       :: 1 << 7;
    EXECUTE_DISABLE :: 1 << 63;
}

page_table_init :: () {
    using Page_Table_Flags;
    pml4    [0] = cast(u64) (xx pdpt.data)       | PRESENT | READ_WRITE;
    pdpt    [0] = cast(u64) (xx page_dir.data)   | PRESENT | READ_WRITE;
    page_dir[0] = cast(u64) (xx page_table.data) | PRESENT | READ_WRITE;

    for 0..page_table.count - 1 {
        page_table[it] = xx (it * 0x1000);
    }
}



Ata_Status :: enum_flags u8 {
    ERROR               :: 0x1;
    INDEX               :: 0x2;
    CORRECTED_DATA      :: 0x4;
    TRANSFER_REQUESTED  :: 0x8;
    SEEK_COMPLETE       :: 0x10;
    DEVICE_FAULT        :: 0x20;
    READY               :: 0x40;
    BUSY                :: 0x80;
}

Ata_Error :: enum_flags {
    ADDRESS_MARK_NOT_FOUND :: 0x1;
    TRACK_ZERO_NOT_FOUND   :: 0x2;
    ABORTED                :: 0x4;
    MEDIA_CHANGE_REQUEST   :: 0x8;
    ID_NOT_FOUND           :: 0x10;
    MEDIA_CHANGED          :: 0x20;
    DATA_ERROR             :: 0x40;
    BAD_BLOCK              :: 0x80;
}

Ata_Port :: enum u16 {
    DATA          :: 0x1f0;
    FEATURE       :: 0x1f1;
    SECTOR_COUNT  :: 0x1f2;
    LBA_LOW       :: 0x1f3;
    LBA_MID       :: 0x1f4;
    LBA_HIGH      :: 0x1f5;
    DRIVE_HEADER  :: 0x1f6;
    COMMAND       :: 0x1f7;

    IN_ERROR  :: 0x1f1;
    IN_STATUS :: 0x1f7;
}

Ata_Command :: enum u8 {
    READ    :: 0x20;
    WRITE   :: 0x30;
}

ata_await_transfer_request :: () {
    while true {
        status: Ata_Status = xx port_read(xx Ata_Port.IN_STATUS);
        if status & Ata_Status.TRANSFER_REQUESTED  break;
    }
}

ata_get_error :: () -> Ata_Error {
    return xx port_read(xx Ata_Port.IN_ERROR);
}

ata_pio_start :: (start_sector: u32, sector_count: u8) {
    LBA_MODE :: 0b11100000;

    using Ata_Port;
    port_write(xx DRIVE_HEADER, cast(u8) (start_sector >> 24) | LBA_MODE);
    port_write(xx SECTOR_COUNT, sector_count);

    port_write(xx LBA_LOW,  cast(u8) (start_sector));
    port_write(xx LBA_MID,  cast(u8) (start_sector >> 8));
    port_write(xx LBA_HIGH, cast(u8) (start_sector >> 16));
}

ata_pio_read :: (buffer: *u16, start_sector: u32, sector_count: u8) -> Ata_Error {
    using Ata_Port;

    ata_pio_start(start_sector, sector_count);
    port_write(xx COMMAND, xx Ata_Command.READ);
    ata_await_transfer_request();

    for 0..sector_count * 0x100-1 {
        buffer[it] = in(xx DATA, u16);
    }
    return ata_get_error();
}

ata_pio_write :: (buffer: *u16, start_sector: u32, sector_count: u8) -> Ata_Error {
    using Ata_Port;

    ata_pio_start(start_sector, sector_count);
    port_write(xx COMMAND, xx Ata_Command.WRITE);
    ata_await_transfer_request();

    for 0..sector_count * 0x100-1 {
        out(xx DATA, buffer[it]);
    }
    return ata_get_error();
}



Zip_Entry :: struct {
    signature:           u32 #align 2;
    version_made_by:     u16 #align 2;
    version_needed:      u16 #align 2;
    bit_flag:            u16 #align 2;
    compression_type:    u16 #align 2;
    modification_time:   u16 #align 2;
    modification_date:   u16 #align 2;
    crc:                 u32 #align 2;
    compressed_len:      u32 #align 2;
    chunk_len:           u32 #align 2;
    name_len:            u16 #align 2;
    extra_field_len:     u16 #align 2;
    file_comment_len:    u16 #align 2;
    disk_number:         u16 #align 2;
    internal_attributes: u16 #align 2;
    external_attributes: u32 #align 2;
    chunk_offset:        u32 #align 2;
} #no_padding

File_Desc :: struct {
    name: string;
    data: *u8;
    size: int;
}

files: [10] File_Desc;
file_count: int;

ZIP_EOCD_SIGNATURE :: 0x06054b50;
ZIP_CD\ _SIGNATURE :: 0x02014b50;
ZIP_LOCAL_HEADER_SIZE :: 0x1e;

read_zip_files :: () {
    cursor: int;
    for 0..MAILBAG_SIZE - 1 {
        cursor = MAILBAG_SIZE + 0x200_000 - it;
        if << cast(*u32) cursor == ZIP_EOCD_SIGNATURE {
            break;
        }
    }

    cursor += 10;
    entry_count := << cast(*u16) cursor;

    cursor += 6;
    directory_location := << cast(*u32) cursor;

    cursor = directory_location + 0x200_000;
    for 0..entry_count - 1 {
        header := << cast(*Zip_Entry) cursor;
        assert(header.signature == ZIP_CD_SIGNATURE);

        file: File_Desc;
        file.name.data = xx (cursor + 46);
        file.name.count = header.name_len;

        file.size = header.compressed_len;
        file.data = xx (0x200_000 + header.chunk_offset + ZIP_LOCAL_HEADER_SIZE + header.name_len);

        files[file_count] = file;
        file_count += 1;
        cursor += size_of(Zip_Entry) + header.name_len + header.extra_field_len + header.file_comment_len;
    }
}



load_elf :: (file_index: int) {
    file := files[file_index];
    elf := cast(*Elf64_Ehdr) file.data;

    for 0..elf.e_phnum - 1 {
        base := file.data + elf.e_phoff;
        base += it        * elf.e_phentsize;
        header := cast(*Elf64_Phdr) base;

        if header.p_type != PT_LOAD  continue;
        assert(header.p_vaddr >= 0x300_000 && header.p_vaddr < 0x400_000);

        target := cast(*u8) header.p_vaddr;

        for 0..header.p_filesz-1 {
            target[it] = file.data[header.p_offset + it];
        }

        for header.p_filesz..header.p_memsz-1 {
            target[it] = 0;
        }
    }

    entry_point := << cast(*()) *elf.e_entry;
    entry_point();
}
