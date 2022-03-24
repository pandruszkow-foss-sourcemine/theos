
#import "Machine_X64";
#load "elf/elf.jai";
#load "pci.jai";
#load "vga.jai";
#load "config.jai";

cpu: Cpu_X86;

boot_data: struct {
    vesa_framebuffer: u32;
}

USE_VGA :: !ENABLE_VESA;

#program_export
kernel_entry :: () {
    boot_data = << cast(*type_of(boot_data)) BOOT_DATA_AREA;

    idt_init();

    cpu = get_cpu_info();

    clear_screen();
    page_table_init();

    map_page(0xf00_000, 0x7000);
    print_hex(get_physical_address(xx (0xf00_000)));
    print("\nDoing stuff\n");
    print_hex(<< cast(*u16) (0xf00_000 + 0xc00 + 0x1fe));

    pic_init();
    cmos_init();

    // print("Scanning pci devices");
    // pci_scan_all_devices();
    // print("Done");

    vga_hide_cursor();
    // vga_attribute(0x10, 3, set = false);
    // enable_ps2_keyboard();

    // clear_screen();
    buffer := cast(*void) 0x200_000;
    ata_pio_read(xx buffer, (MAILBAG_LOCATION + 0x100) / 0x200, (MAILBAG_SIZE + 0x100) / 0x200);

    x: string;
    x.data = xx buffer;
    x.count = vga_rows * vga_columns;
    print(x);
    while true {}

    read_zip_files(buffer);

    print("Doing stuff.\n");
    for 0..file_count {
        file := files[it];
        ti := type_info(File_Type);
        print(file.name);
        print(": ");
        print(ti.names[file.type]);
        print("\n");
    }
    // load_elf(0);
    // print("\nExecuted the program.\n");

    // pci_print_device_list();
    // welcome_screen();

    // hda_detect();

    // page_table_init();

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

assert :: (condition: bool, message: string = "", call_site := #caller_location) {
    if !condition {
        print("Assertion failure!\n -> ");
        print(call_site.fully_pathed_filename);
        print(":");
        print(call_site.line_number);
        print("\n");
        print(message);
        print("\n");

        while true {
            #asm { hlt; }
        }
    }
}

out :: (port: u16, value: $T) {
    #asm {
        port  === d;
        value === a;
    }

    #if      T == u8  #asm { out.b port, value; }
    else #if T == u16 #asm { out.w port, value; }
    else #if T == u32 #asm { out.d port, value; }
    else #assert(false);
}

in :: (port: u16, $T: Type = u32) -> T {
    value: T;    
    #asm {
        port  === d;
        value === a;
    }

    #if      T == u8  #asm { in.b value, port; }
    else #if T == u16 #asm { in.w value, port; }
    else #if T == u32 #asm { in.d value, port; }
    else #assert(false);

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



/* Memory map:

4Mb is identity mapped.

0Mb -> 1Mb: Bootloader, BIOS
1Mb -> 2Mb: Kernel code + data

4Mb -> 12Mb: Video

*/

VIDEO_MEMORY_BASE :: IDENTITY_MAP_SIZE;
VIDEO_MEMORY_SIZE :: 0x400_000;
IDENTITY_MAP_SIZE :: 0x800_000;
PAGE_TABLE_RANGE :: 0x200_000;

PAGE_TABLE_COUNT :: (VIDEO_MEMORY_SIZE + IDENTITY_MAP_SIZE) / PAGE_TABLE_RANGE;
#assert (PAGE_TABLE_COUNT <= 0x200);

page_tables: [PAGE_TABLE_COUNT][0x200] u64 #align 0x1000;
page_dir: [0x200] u64 #align 0x1000;
pdpt:     [0x200] u64 #align 0x1000;
pml4:     [0x200] u64 #align 0x1000;

Page_Flags :: enum_flags u64 {
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

VIRTUAL_OFFSET :: 0xffff_ff80_0000_0000;
offset_pdpt: [0x200] u64 #align 0x1000;

ONE_GB :: 0x4000_0000;

page_table_init :: () {
    using Page_Flags;

    assert(check_feature(cpu.feature_leaves, .PDPE1GB), "For the present, this OS requires 1GB pages to be supported");

    pml4[0x1ff] = cast(u64) (xx offset_pdpt.data) | PRESENT | READ_WRITE;
    for 0..0x200-1 {
        address := it * ONE_GB;
        offset_pdpt[it] = cast(u64) (xx address)  | PRESENT | READ_WRITE | PAGE_SIZE;
    }

    pml4[0]     = cast(u64) (xx pdpt.data)        | PRESENT | READ_WRITE;
    pdpt[0]     = cast(u64) (xx page_dir.data)    | PRESENT | READ_WRITE;

    page_tables_in_identity_map :: IDENTITY_MAP_SIZE / PAGE_TABLE_RANGE;

    for t: 0..page_tables_in_identity_map - 1 {
        table: [] u64;
        table.data = page_tables[t].data;
        table.count = 0x200;

        page_dir[t] = cast(u64) (xx table.data)   | PRESENT | READ_WRITE;
        for page: 0..0x200 - 1 {
            address := page * 0x1000 + t * PAGE_TABLE_RANGE;
            table[page] = cast(u64) (xx address)  | PRESENT | READ_WRITE;
        }
    }

    pml4_base := pml4.data;
    PAGE_SIZE_BIT :: 1 << 4;
    #asm {
        get_cr4 cr4:;
        or cr4, PAGE_SIZE_BIT;
        set_cr4 cr4;

        set_cr3 pml4_base;
    }

    #if ENABLE_VESA {
        page_tables_for_video_memory :: VIDEO_MEMORY_SIZE / PAGE_TABLE_RANGE;
        for 0..page_tables_for_video_memory - 1 {
            index := it + page_tables_in_identity_map;
    
            table: [] u64;
            table.data = page_tables[index].data;
            table.count = 0x200;
    
            page_dir[index] = cast(u64) (xx table.data) | PRESENT | READ_WRITE;
            for page: 0..0x200 - 1 {
                address := page * 0x1000 + it * PAGE_TABLE_RANGE + boot_data.vesa_framebuffer;
                table[page] = cast(u64) (xx address)    | PRESENT | READ_WRITE;
            }
        }
    }
}

get_or_create_page_table_entry :: (table: *u64, entry: u64) -> *u64 {
    using Page_Flags;

    if table[entry] & xx PRESENT {
        phys := table[entry] & (~0xfff);
        return xx (phys + VIRTUAL_OFFSET);
    }

    phys := get_new_page_frame();
    table[entry] = phys | cast(u64) (PRESENT | READ_WRITE);
    return cast(*u64) (phys + VIRTUAL_OFFSET);
}

map_page :: (virtual_address: u64, physical_address: u64, loc := #caller_location) -> bool {
    using Page_Flags;

    mask: u64 = 0b111111111;
    pml4_offset := (virtual_address >> 39) & mask;
    pdpt_offset := (virtual_address >> 30) & mask;
    pd\ _offset := (virtual_address >> 21) & mask;
    pt\ _offset := (virtual_address >> 12) & mask;

    pdpt := get_or_create_page_table_entry(pml4.data, pml4_offset);
    pd   := get_or_create_page_table_entry(pdpt,      pdpt_offset);
    pt   := get_or_create_page_table_entry(pd,        pd_offset);
    assert(!(pt[pt_offset] & xx PRESENT), "Attempting to map a page that is already mapped", loc);

    pt[pt_offset] = physical_address | cast(u64) (PRESENT | READ_WRITE);

    // #asm {
    //     get_cr3 cr3:;
    //     set_cr3 cr3;
    // }
    return true;
}

PAGE_FRAME_BASE :: 0xd00_000;
page_frame_watermark: int;

get_new_page_frame :: (count: int = 1) -> u64 {
    address := page_frame_watermark * 0x1000 + PAGE_FRAME_BASE;
    page_frame_watermark += count;
    memset(xx (address + VIRTUAL_OFFSET), 0, 0x1000);
    return xx address;
}

/*
virtual_watermark: int;
map_physical_region :: (physical_base: u64, limit: u64) -> *void {
    VIRTUAL_WATERMARK_BASE :: VIDEO_MEMORY_BASE + VIDEO_MEMORY_SIZE;
    address := virtual_watermark * 0x1000 + VIRTUAL_WATERMARK_BASE;

    assert(limit % 0x1000 == 0);
    pages_required := limit / 0x1000;

    for 0..pages_required - 1 {

        address += 0x1000;
    }

}
*/

get_physical_address :: (virtual_address: *void) -> u64, present: bool {
    using Page_Flags;
    x := cast(u64) virtual_address;

    mask: u64 = 0b111111111;

    pml4_offset := (x >> 39) & mask;
    pdpt_offset := (x >> 30) & mask;
    pd\ _offset := (x >> 21) & mask;
    pt\ _offset := (x >> 12) & mask;
    page_offset := x & 0xfff;

    ReadTableEntry :: (index: u64, table_address: u64) -> entry: u64 #expand {
        if !((xx table_address) & PRESENT) `return 0, false; //`

        table := cast(*u64) (table_address & (~0xfff) + VIRTUAL_OFFSET);
        return table[index];
    }

    pml4e := pml4[pml4_offset];
    pdpte := ReadTableEntry(pdpt_offset, pml4e);
    if pdpte & xx PAGE_SIZE {
        page_offset := x & 0x3fff_ffff;
        return (pdpte & ~0xfff) + page_offset, true;
    }

    pde   := ReadTableEntry(pd\ _offset, pdpte);
    pte   := ReadTableEntry(pt\ _offset, pde);

    return (pte & ~0xfff) + page_offset, true;
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

    for 0..sector_count - 1 {
        ata_await_transfer_request();

        for 0..0x100 - 1 {
            buffer[it] = in(xx DATA, u16);
        }
    }
    return ata_get_error();
}

ata_pio_write :: (buffer: *u16, start_sector: u32, sector_count: u8) -> Ata_Error {
    using Ata_Port;

    ata_pio_start(start_sector, sector_count);
    port_write(xx COMMAND, xx Ata_Command.WRITE);

    for 0..sector_count - 1 {
        ata_await_transfer_request();

        for 0..0x100 - 1 {
            out(xx DATA, buffer[it]);
        }
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

File_Type :: enum {
    UNKNOWN;
    TEXT;
    BINARY_EXECUTABLE;
    BINARY_DATA;
    PICTURE;
    SOUND;
}

File_Desc :: struct {
    name: string;
    data: *u8;
    size: int;
    type: File_Type;
}

files: [10] File_Desc;
file_count: int;

ZIP_EOCD_SIGNATURE :: 0x06054b50;
ZIP_CD\ _SIGNATURE :: 0x02014b50;
ZIP_LOCAL_HEADER_SIZE :: 0x1e;

read_zip_files :: (buffer: *void) {
    cursor: int;
    for 0..MAILBAG_SIZE - 1 {
        cursor = MAILBAG_SIZE + xx buffer - it;
        if << cast(*u32) cursor == ZIP_EOCD_SIGNATURE {
            break;
        }
    }

    cursor += 10;
    entry_count := << cast(*u16) cursor;

    cursor += 6;
    directory_location := << cast(*u32) cursor;
    print_hex(directory_location);
    while true {}
    cursor = directory_location + xx buffer;
    for 0..entry_count - 1 {
        header := << cast(*Zip_Entry) cursor;
        assert(header.signature == ZIP_CD_SIGNATURE, "Attempted to read zip file, not valid.");

        file: File_Desc;
        file.name.data = xx (cursor + 46);
        file.name.count = header.name_len;

        file.size = header.compressed_len;
        file.data = xx (xx buffer + header.chunk_offset + ZIP_LOCAL_HEADER_SIZE + header.name_len);

        if file.name.count > 4 {
            extension: string;
            extension.count = 4;
            extension.data = *file.name[file.name.count - 5];
            if extension == ".txt" file.type = .TEXT;
            else if extension == ".pgm" file.type = .PICTURE;
        }

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
