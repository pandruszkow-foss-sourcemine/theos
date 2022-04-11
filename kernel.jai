
Basic :: #import "Basic";

#import "Machine_X64";
#load "elf/elf.jai";
#load "pci.jai";
#load "graphics.jai";
#load "config.jai";
#load "keyboard.jai";

cpu: Cpu_X86;

Boot_Data :: struct {
    vesa_framebuffer: u32;
    boot_drive_number: u8;
}
boot_data: Boot_Data;

#program_export
kernel_entry :: () {
    kernel_context: Context;
    kernel_context.allocator.proc = allocate_memory;
    kernel_context.logger = log;

    push_context kernel_context {
        boot_data = << cast(*type_of(boot_data)) BOOT_DATA_AREA;

        idt_init();
        pic_init();
        cmos_init();

        cpu = get_cpu_info();
        page_table_init();
        enable_simd(cpu);
        enable_ps2_keyboard();

        buffer := map_memory(MAILBAG_SIZE);

        // ata_read(buffer, 0x1d0_000, MAILBAG_SIZE);

        read_zip_file(xx 0x1d0_000);

        font: Pnm;
        flower: Pnm;
        for 0..file_count - 1 {
            file := files[it];

            if file.name == "font.pgm" {
                font = parse_pnm(file.data);
            }

            if file.name == "plant.ppm" {
                flower = parse_pnm(file.data);
            }
        }

        random_seed = xx rdtsc();
        vesa_init(boot_data, font);

        clear_screen();
        print("\n> ");
        vesa_draw_frame();

        while true #asm { hlt; }
    }
}

allocate_memory :: (mode: Allocator_Mode, size: s64, old_size: s64, old_buffer: *void, user_data: *void) -> *void {
    if mode == .FREE {
        return ":-)".data;
    }

    if mode == .RESIZE {
        if size < old_size || size < 4096 {
            return old_buffer;
        }
    }

    return map_memory(size);
}

log :: (message: string, data: *void, info: Log_Info) {
    print(message);
}

crt_memset :: (target: *u8, value: s32, count: u64) -> *void #c_call {
    for 0..count-1 {
        target[it] = cast(u8) value;
    }
    return target;
}

crt_memcpy :: (dest: *u8, src: *u8, $$ count: u64) -> *void #c_call {
    if count % 8 == 0 {
        dest64: *u64 = xx dest;
        src64:  *u64 = xx src;

        for 0..count / 8 - 1 {
            dest64[it] = src64[it];
        }
    } else {
        for 0..count - 1 {
            dest[it] = src[it];
        }
    }
    return dest;
}

crt_memcmp :: (a: *u8, b: *u8, count: u64) -> s32 #c_call {
    for 0..count-1 {
        if a[it] != b[it] {
            return a[it] - b[it];
        }
    }
    return 0;
}

assert :: (condition: bool, message: string = "", call_site := #caller_location) {
    if !condition {
        print("\nAssertion failure!\n  -> ");
        print(call_site.fully_pathed_filename, theme.accent);
        print(":");
        print(call_site.line_number, theme.accent);
        print("\n     ");
        print(message);
        print("\n");

        #if ENABLE_VESA vesa_draw_frame();
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

port_write :: (_port: $P, _value: $V) #no_context {
    port  := cast(u16) _port;
    value := cast(u8)  _value;
    #asm {
        port  === d;
        value === a;
        out.b port, value;
    }
}

port_read :: (_port: $P) -> u8 #no_context {
    port := cast(u16) _port;
    value: u8;
    #asm {
        port  === d;
        value === a;
        in.b value, port;
    }
    return value;
}

io_delay :: () #no_context {
    #asm {
        zero: gpr === a;
        xor zero, zero;
        out.b 0x80, zero;
    }
}

divru :: (dividend: $T, divisor: T) -> T {
    return (dividend + (divisor - 1)) / divisor;
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

enable_simd :: (cpu: Cpu_X86) {
    CR0_MP         ::   1 << 1;
    CR0_EM_CLEAR   :: ~(1 << 2);
    CR4_OSFXSR     ::   1 << 9;
    CR4_OSXMMEXCPT ::   1 << 10;
    CR4_OSXSAVE    ::   1 << 18;

    if check_feature(cpu.feature_leaves, .SSE) #asm {
        get_cr0 cr0:;
        and cr0, CR0_EM_CLEAR;
        or  cr0, CR0_MP;
        set_cr0 cr0;

        get_cr4 cr4:;
        or  cr4, CR4_OSFXSR;
        or  cr4, CR4_OSXMMEXCPT;
        set_cr4 cr4;
    }

    return;
    if check_feature(cpu.feature_leaves, .OSXSAVE) #asm {
        get_cr4 cr4:;
        or  cr4, CR4_OSXSAVE;
        set_cr4 cr4;
    }

    if check_feature(cpu.feature_leaves, .AVX) #asm XSAVE {
        index: gpr === c;
        xor index, index;

        xgetbv xcr0_h:, xcr0_l:, index;
        or xcr0_l, 7;
        xsetbv xcr0_h, xcr0_l, index;
    }
}

BochsBreak :: () #expand {
    #asm {
        bx: gpr === b;
        xchg.w bx, bx;
    }
}



Interrupt_Stack_Frame :: struct {
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

idt: [0x100] Idt_Entry #align 0x1000;

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
    idt_add_handler(xx page_fault_handler, 0x0e);
    idt_add_handler(xx syscall,            0x80);

    address := *idt_desc;
    #asm {
        lidt [address];
    }
}

Interrupts :: #foreign_library,no_dll ".build/interrupt";

interrupt_wrapper :: () #c_call #foreign Interrupts;

#program_export
handle_interrupt :: () #c_call {
    timer_ticks_elapsed += 10000;
}

syscall :: () #no_call {
    #asm {
        cli;
    }

    syscall_print :: () #c_call {
        message := << cast(*string) (0x400_000 - size_of(string));
        push_context .{} {
            print(message);
        }
    }

    syscall_print();

    #asm {
        sti;
        iret.q;
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

PIC_BASE_OFFSET :: 0x20;

PIC_ICW4_uPM  :: 0x1;
PIC_ICW4_AEOI :: 0x2;
PIC_ICW4_M_S  :: 0x4;
PIC_ICW4_BUF  :: 0x8;
PIC_ICW4_SFMN :: 0x10;

pic_end_of_interrupt :: (irq: u8) #c_call {
    using Pic_Port;
    using Pic_Command;

    if irq >= 8 {
        port_write(SLAVE_CMD, END_OF_INTERRUPT);
    }
    port_write(MASTER_CMD, END_OF_INTERRUPT);
}

pic_init :: () {
    using Pic_Port;
    using Pic_Command;

    SLAVE_ADDRESS :: 0b0000_0100;

    mask: u8 = port_read(MASTER_CMD);

    port_write(MASTER_CMD,  INITIALIZE);
    port_write(MASTER_DATA, PIC_BASE_OFFSET);
    port_write(MASTER_DATA, SLAVE_ADDRESS);
    port_write(MASTER_DATA, PIC_ICW4_uPM);
    port_write(MASTER_DATA, mask);
    port_write(MASTER_DATA, 0xff);

    mask = port_read(SLAVE_CMD);

    port_write(SLAVE_CMD,  INITIALIZE);
    port_write(SLAVE_DATA, PIC_BASE_OFFSET + 0x8);
    port_write(SLAVE_DATA, 0x2);
    port_write(SLAVE_DATA, PIC_ICW4_uPM);
    port_write(SLAVE_DATA, mask);
    port_write(SLAVE_DATA, 0xff);

    pic_enable_irq(0x2);

    #asm { sti; }
}

pic_enable_irq :: (irq: u8) {
    using Pic_Port;
    port := MASTER_DATA;

    if irq >= 8 {
        irq -= 8;
        port = SLAVE_DATA;
    }

    mask:  u8 = xx ~(1 << irq);
    value: u8 = port_read(port) & mask;
    port_write(port, value);
}


pit_init :: () {
    idt_add_handler(xx interrupt_wrapper, 0x20);
    pic_enable_irq(0x0);
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
    SECONDS_ALARM    :: 0x01;
    MINUTES          :: 0x02;
    MINUTES_ALARM    :: 0x03;
    HOURS            :: 0x04;
    HOURS_ALARM      :: 0x05;
    WEEKDAY          :: 0x06;
    DAY_OF_THE_MONTH :: 0x07;
    MONTH            :: 0x08;
    YEAR             :: 0x09;
    CENTURY          :: 0x32;
    STATUS_REG_A     :: 0x0a;
    STATUS_REG_B     :: 0x0b;
    STATUS_REG_C     :: 0x0c;
}

Cmos_Status_B :: enum_flags u8 {
    _24H_CLOCK                :: 0x01;
    BCD_MODE                  :: 0x02;
    INTERRUPT_UPDATE_COMPLETE :: 0x10;
    INTERRUPT_ALARM           :: 0x20;
    INTERRUPT_PERIODIC        :: 0x40;
}

cmos_init :: () {
    using Cmos_Status_B;
    idt_add_handler(xx interrupt_wrapper, 0x28);

    status := cmos_read(.STATUS_REG_B);
    cmos_format.bcd_mode      = status & xx BCD_MODE   > 0;
    cmos_format.twenty_four_h = status & xx _24H_CLOCK > 0;
}

cmos_read :: ($register: Cmos_Register) -> u8 #c_call {
    using Cmos_Port;

    port_write(ADDRESS, register);
    io_delay();
    result := port_read(DATA);

    #if register < .STATUS_REG_A {
        if cmos_format.bcd_mode {
            result = (result & 0xf) + (result / 16) * 10;
        }
    }

    return result;
}

cmos_write :: ($register: Cmos_Register, value: u8) {
    using Cmos_Port;

    port_write(ADDRESS, register);
    io_delay();
    port_write(DATA, value);
}

cmos_enable_irq :: (periodic: bool, alarm := false, update := false) {
    using Cmos_Port;
    using Cmos_Register;

    pic_enable_irq(0x8);

    #asm { cli; }
    port_write(ADDRESS, STATUS_REG_B | 0x80);
    cmos_b := port_read(Cmos_Port.DATA);

    using Cmos_Status_B;
    if periodic  cmos_b |= xx INTERRUPT_PERIODIC;
    if update    cmos_b |= xx INTERRUPT_UPDATE_COMPLETE;
    if alarm     cmos_b |= xx INTERRUPT_ALARM;

    port_write(ADDRESS, STATUS_REG_B | 0x80);
    port_write(DATA, cmos_b);

    #asm { sti; }
    cmos_read(.STATUS_REG_C);
}

cmos_set_frequency :: (rate: u8) {
    using Cmos_Port;
    using Cmos_Register;
    assert((rate & 0xf) == rate);

    #asm { cli; }
    port_write(ADDRESS, STATUS_REG_A | 0x80);
    cmos_a := port_read(Cmos_Port.DATA);

    port_write(ADDRESS, STATUS_REG_A | 0x80);
    port_write(DATA, (cmos_a & 0xf0) | rate);
    #asm { sti; }
}

get_cmos_datetime_string :: () -> string {
    weekday := weekdays[cmos_read(.WEEKDAY) - 1];
    month   := months[cmos_read(.MONTH) - 1];
    day     := cmos_read(.DAY_OF_THE_MONTH);
    year    := cmos_read(.YEAR) + 2000;

    hours   := cmos_read(.HOURS);
    minutes := cmos_read(.MINUTES);
    seconds := cmos_read(.SECONDS);

    return Basic.sprint("% % %, %, %:%:%", weekday, month, day, year, hours, minutes, seconds);
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



timer_ticks_elapsed: u64;
timer_ticks_target: u64;

wait_for_seconds :: (seconds: float) {
    timer_ticks_elapsed = 0;
    timer_ticks_target = cast(u64) (seconds * 18.2065);

    while true {
        #asm { hlt; }
        if timer_ticks_elapsed >= timer_ticks_target {
            break;
        }
    }
}



IDENTITY_MAP_SIZE :: 0x400_000;
PAGE_TABLE_RANGE :: 0x200_000;

PAGE_TABLE_COUNT :: (IDENTITY_MAP_SIZE) / PAGE_TABLE_RANGE;
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

VIRTUAL_MIRROR : u64 : 0xffff_ffff_ffff_ffff - ONE_GB + 1;
mirror_pdpt: [0x200] u64 #align 0x1000;
mirror_pd:   [0x200] u64 #align 0x1000;

ONE_GB : u64 : 0x4000_0000;

page_table_init :: () {
    using Page_Flags;

    pml4[0x1ff]        = cast(u64) (xx mirror_pdpt.data) | PRESENT | READ_WRITE;
    mirror_pdpt[0x1ff] = cast(u64) (xx mirror_pd.data)   | PRESENT | READ_WRITE;
    for 0..0x200-1 {
        address := it * PAGE_TABLE_RANGE;
        mirror_pd[it] = cast(u64) (xx address) | PRESENT | READ_WRITE | PAGE_SIZE;
    }

    pml4[0] = cast(u64) (xx pdpt.data)     | PRESENT | READ_WRITE;
    pdpt[0] = cast(u64) (xx page_dir.data) | PRESENT | READ_WRITE;

    page_tables_in_identity_map :: IDENTITY_MAP_SIZE / PAGE_TABLE_RANGE;

    for t: 0..page_tables_in_identity_map - 1 {
        table: [] u64;
        table.data = page_tables[t].data;
        table.count = 0x200;

        page_dir[t] = cast(u64) (xx table.data)  | PRESENT | READ_WRITE;
        for page: 0..0x200 - 1 {
            address := page * 0x1000 + t * PAGE_TABLE_RANGE;
            table[page] = cast(u64) (xx address) | PRESENT | READ_WRITE;
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

    IA32_PAT :: 0x277;
    mask: u64 = ~0xf;
    #asm {
        msr_name: gpr === c;
        mov msr_name, IA32_PAT;
        rdmsr high:, low:, msr_name;
        and high, mask;
        or high, 0x1;
        wrmsr high, low, msr_name;
    }
}

get_or_create_page_table :: (table: *u64, entry: u64) -> *u64 {
    using Page_Flags;

    if table[entry] & xx PRESENT {
        phys := table[entry] & (~0xfff);
        return xx (xx phys + VIRTUAL_MIRROR);
    }

    phys := get_new_page_frame();
    table[entry] = phys | xx PRESENT | READ_WRITE;
    return cast(*u64) (xx phys + VIRTUAL_MIRROR);
}

map_memory :: (size_bytes: int, virtual_address: u64 = xx,no_check -1, physical_address: u64 = xx,no_check -1, flags := Page_Flags.PRESENT | .READ_WRITE, loc := #caller_location) -> *void {
    page_count := (size_bytes + (0x1000 - 1)) / 0x1000;

    target := physical_address;
    if target == xx,no_check -1 {
        target = get_new_page_frame(page_count);
    }

    source := virtual_address;
    if source == xx,no_check -1 {
        source = get_new_virtual_page(page_count);
    }

    assert(address_is_page(target), "Not a page", loc);
    assert(address_is_page(source), "Not a page", loc);

    for 0..page_count-1 {
        offset := cast(u64) it * 4096;
        map_page(source + offset, target + offset, flags, loc);
    }

    return xx source;
}

map_page :: (virtual_address: u64, physical_address: u64, flags := Page_Flags.PRESENT | .READ_WRITE, loc := #caller_location) {
    using Page_Flags;

    mask: u64 = 0b111111111;
    pml4_offset := (virtual_address >> 39) & mask;
    pdpt_offset := (virtual_address >> 30) & mask;
    pd\ _offset := (virtual_address >> 21) & mask;
    pt\ _offset := (virtual_address >> 12) & mask;

    pdpt := get_or_create_page_table(pml4.data, pml4_offset);
    pd   := get_or_create_page_table(pdpt,      pdpt_offset);
    pt   := get_or_create_page_table(pd,        pd_offset);
    assert(!(pt[pt_offset] & xx PRESENT), "Attempting to map a virtual page that is already present", loc);

    pt[pt_offset] = physical_address | cast(u64) flags;
}

PAGE_FRAME_BASE :: IDENTITY_MAP_SIZE;
page_frame_watermark: int;

get_new_page_frame :: (count: int = 1) -> u64 {
    address := page_frame_watermark * 0x1000 + PAGE_FRAME_BASE;
    page_frame_watermark += count;
    memset(xx (xx address + VIRTUAL_MIRROR), 0, 0x1000);
    return xx address;
}

address_is_page :: (address: u64) -> bool {
    if (address >> 48 != 0xffff) && (address >> 48 != 0x0) return false;
    return address % 0x1000 == 0;
}

VIRTUAL_PAGE_BASE :: IDENTITY_MAP_SIZE;
virtual_page_watermark: int;

get_new_virtual_page :: (count: int = 1) -> u64 {
    address := virtual_page_watermark * 0x1000 + VIRTUAL_PAGE_BASE;
    virtual_page_watermark += count;
    return xx address;
}


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

        table := cast(*u64) (table_address & (~0xfff) + VIRTUAL_MIRROR);
        return table[index];
    }

    pml4e := pml4[pml4_offset];

    pdpte := ReadTableEntry(pdpt_offset, pml4e);
    if pdpte & xx PAGE_SIZE {
        assert(check_feature(cpu.feature_leaves, .PDPE1GB));
        page_offset := x & 0x3fff_ffff;
        return (pdpte & ~0xfff) + page_offset, true;
    }

    pde   := ReadTableEntry(pd_offset, pdpte);
    if pde & xx PAGE_SIZE {
        page_offset := x & 0x1f_ffff;
        return (pde & ~0xfff) + page_offset, true;
    }

    pte   := ReadTableEntry(pt_offset, pde);
    return (pte & ~0xfff) + page_offset, true;
}

page_fault_handler :: () #no_call {
    #asm {
        rsp: gpr === sp;
        sub rsp, 0x200;
        cli;
    }

    error_code: *u64;
    stack_data: *Interrupt_Stack_Frame;

    #asm {
        mov stack:, rsp;
        add stack, 0x200;
        mov error_code, stack;
        add stack, 0x8;
        mov stack_data, stack;
    }

    push_context Context.{} {
        print("\n\nAn exception has occurred:  ");
        print("Page fault\n\n", theme.accent);

        cr2: u64;
        #asm {
            get_cr2 cr2;
        }
        print("CR2 contains       "); print_hex(cr2); print(".\n");
        print("VESA buffer        "); print_hex(cast(u64) vesa.framebuffer); print(".\n\n");

        phys, present := get_physical_address(xx cr2);
        if present {
            print("The page is present.\nIt is mapped to    "); print_hex(phys); print(".\n\n");
        } else {
            print("The page is not present.\n\n");
        }

        print("The error code is  "); print_hex(cast(u8) << error_code); print(".\n");
        print("\nInterrupt frame:\n");
        print("RIP:    "); print_hex(stack_data.ip);    print("\n");
        print("CS:     "); print_hex(stack_data.cs);    print("\n");
        print("FLAGS:  "); print_hex(stack_data.flags); print("\n");
        print("SP:     "); print_hex(stack_data.sp);    print("\n");
        print("SS:     "); print_hex(stack_data.ss);    print("\n");
        vesa_draw_frame();
    }

    #asm {
        sti;
        add rsp, 0x200;
    }

    while true #asm { hlt; }
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
    NONE                   :: 0x0;
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
    DRIVE_SELECT  :: 0x1f6;
    COMMAND       :: 0x1f7;
    CONTROL       :: 0x3f6;

    IN_ERROR  :: 0x1f1;
    IN_STATUS :: 0x1f7;

}

Ata_Command :: enum u8 {
    READ     :: 0x20;
    WRITE    :: 0x30;
    IDENTIFY :: 0xec;
}

ata_await_transfer_request :: () {
    using Ata_Status;

    wait();

    while true {
        status := cast(Ata_Status) port_read(xx Ata_Port.IN_STATUS);

        trq := status & TRANSFER_REQUESTED;
        bsy := status & BUSY;

        if trq && !bsy {
            break;
        }
    }
}

ata_get_error :: () -> Ata_Error {
    return xx port_read(xx Ata_Port.IN_ERROR);
}

ata_pio_start :: (start_sector: u32, sector_count: u8) {
    using Ata_Port;

    port_write(DRIVE_SELECT, cast(u8) (start_sector >> 24) | 0xE0);
    port_write(FEATURE, 0x00);
    port_write(SECTOR_COUNT, sector_count);

    port_write(LBA_LOW,  cast(u8) (start_sector));
    port_write(LBA_MID,  cast(u8) (start_sector >> 8));
    port_write(LBA_HIGH, cast(u8) (start_sector >> 16));
}

ata_pio_read :: (buffer: *u16, start_sector: u32, sector_count: u8) -> Ata_Error {
    using Ata_Port;

    ata_pio_start(start_sector, sector_count);
    port_write(COMMAND, Ata_Command.READ);

    count := ifx sector_count == 0 then 256 else sector_count;
    for sector: 0..count - 1 {
        ata_await_transfer_request();

        for 0..0x100 - 1 {
            buffer[it + 0x100 * sector] = in(xx DATA, u16);
        }
    }
    return ata_get_error();
}

ata_read :: (buffer: *u8, start_address: int, size_bytes: int) {
    sector_count := (size_bytes    + 0x1ff) / 0x200;
    start_lba    := (start_address + 0x1ff) / 0x200;

    num_reads_required := sector_count / 256;
    num_sectors_left   := sector_count % 256;

    for 0..num_reads_required-1 {
        lba_offset := 0x100 * it;
        ata_pio_read(xx (buffer + 0x200 * lba_offset), cast(u32) (start_lba + lba_offset), 0);
    }

    lba := 0x100 * num_reads_required;
    ata_pio_read(xx (buffer + 0x200 * lba), cast(u32) (start_lba + lba), xx num_sectors_left);
}

ata_pio_write :: (buffer: *u16, start_sector: u32, sector_count: u8) -> Ata_Error {
    using Ata_Port;

    ata_pio_start(start_sector, sector_count);
    port_write(COMMAND, Ata_Command.WRITE);

    count := ifx sector_count == 0 then 256 else sector_count;
    for sector: 0..count - 1 {
        ata_await_transfer_request();

        for 0..0x100 - 1 {
            out(xx DATA, buffer[it + 0x100 * sector]);
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
    EXECUTABLE;
    BIN_DATA;
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

print_file_list :: () {
    ti := type_info(File_Type);

    print("|      Name      |    Size    |    Type    |\n");
    print("--------------------------------------------\n", theme.foreground);
    for 0..file_count - 1 {
        file := files[it];
        print("| ");
        print(file.name);
        for 0..14 - file.name.count print(" ");
        print("| ");
        print_hex(cast(u32) file.size);

        print(" | ");
        type := ti.names[file.type];
        for 0..9 - type.count print(" ");
        print(type);
        print(" |\n");
    }
}

read_zip_file :: (buffer: *void) {
    cursor: int;
    for 0..MAILBAG_SIZE - 1 {
        cursor = MAILBAG_SIZE + xx buffer - it;
        if << cast(*u32) cursor == ZIP_EOCD_SIGNATURE {
            break;
        }
    }
    assert(cursor > xx buffer + 1, "No zip header found.");

    cursor += 10;
    entry_count := << cast(*u16) cursor;

    cursor += 6;
    directory_location := << cast(*u32) cursor;

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
            extension.data = *file.name[file.name.count - 4];
            if extension == ".txt" file.type = .TEXT;
            else if extension == ".pgm" file.type = .PICTURE;
            else if extension == ".ppm" file.type = .PICTURE;
        }

        if file.type == .UNKNOWN && file.size > size_of(Elf64_Ehdr) {
            if file.data[0] == 0x7f && file.data[1] == 0x45 && file.data[2] == 0x4c && file.data[3] == 0x46 {
                file.type = .EXECUTABLE;
            }
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

dont :: () #expand {
    while true {
        #asm {
            hlt;
        }
    }
}
