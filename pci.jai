
PCI_MAX_BUSES        :: 256;
PCI_MAX_DEVICES      :: 32;
PCI_NUM_FUNCTIONS    :: 8;
PCI_VENDOR_NO_DEVICE :: 0xffff;
PCI_HEADER_TYPE_MULTIFUNCTION_BIT :: 0x80;

Pci_Class_Code :: enum u8 {
    UNCLASSIFIED             :: 0x0;
    MASS_STORAGE             :: 0x1;
    NETWORK                  :: 0x2;
    DISPLAY_DEVICE           :: 0x3;
    MULTIMEDIA               :: 0x4;
    MEMORY_CONTROLLER        :: 0x5;
    BRIDGE                   :: 0x6;
    COMMUNICATION            :: 0x7;
    SYSTEM_PERIPHERAL        :: 0x8;
    INPUT_DEVICE             :: 0x9;
    DOCKING_STATION          :: 0xa;
    PROCESSOR                :: 0xb;
    SERIAL_BUS               :: 0xc;
    WIRELESS_CONTROLLER      :: 0xd;
}

Pci_Status :: enum_flags u16 {
    INTERRUPT_STATUS         :: 1 << 3;
    CAPABILITIES_LIST        :: 1 << 4;
    _66_MHZ_CAPABLE          :: 1 << 5;
    FAST_BACK_TO_BACK        :: 1 << 7;
    MASTER_DATA_PARITY_ERROR :: 1 << 8;
    DEVSEL_TIMING_A          :: 1 << 9;
    DEVSEL_TIMING_B          :: 1 << 10;
    SIGNALLED_TARGET_ABORT   :: 1 << 11;
    RECEIVED_TARGET_ABORT    :: 1 << 12;
    RECEIVED_MASTER_ABORT    :: 1 << 13;
    SIGNALLED_SYSTEM_ERROR   :: 1 << 14;
    DETECTED_PARITY_ERROR    :: 1 << 15;
}

Pci_Command :: enum_flags u16 {
    IO_SPACE                    :: 1 << 0;
    MEMORY_SPACE                :: 1 << 1;
    BUS_MASTER                  :: 1 << 2;
    SPECIAL_CYCLES              :: 1 << 3;
    MEMORY_WRITE_AND_INVALIDATE :: 1 << 4;
    VGA_PALETTE_SNOOP           :: 1 << 5;
    PARITY_ERROR_RESPONSE       :: 1 << 6;
    S_ERR_ENABLE                :: 1 << 8;
    FAST_BACK_TO_BACK_ENABLE    :: 1 << 9;
    INTERRUPT_DISABLE           :: 1 << 10;
}

Pci_Port :: enum {
    CONFIG_ADDRESS :: 0xcf8;
    CONFIG_DATA    :: 0xcfc;
}

Pci_Header :: struct {
    vendor_id:       u16;
    device_id:       u16;
    status:          Pci_Status;
    command:         Pci_Command;
    revision_id:     u8;
    prog_if:         u8;
    subclass:        u8;
    class_code:      Pci_Class_Code;
    cache_line_size: u8;
    latency_timer:   u8;
    header_type:     u8;
    bist:            u8;
}

pci_device_info: [PCI_MAX_BUSES * PCI_MAX_DEVICES] Pci_Device_Info;
pci_device_count: int;
pci_devices_scanned: bool;

Pci_Device_Info :: struct {
    bus: u32;
    index: u32;
    function: u32;
    header: Pci_Header;
}

pci_scan_all_devices :: () {
    if pci_devices_scanned return;

    AddDevice :: (function: int) #expand {
        device: Pci_Device_Info = ---;
        device.bus       = xx `bus;
        device.index     = xx `index;
        device.function  = xx function;
        device.header    = `header; // `

        pci_device_info[pci_device_count] = device;
        pci_device_count += 1;
    }

    for bus: 0..PCI_MAX_BUSES-1 {
        for index: 0..PCI_MAX_DEVICES-1 {
            header := pci_read_header(xx bus, xx index, 0);
            if header.vendor_id == PCI_VENDOR_NO_DEVICE continue;

            AddDevice(0);

            if (header.header_type & PCI_HEADER_TYPE_MULTIFUNCTION_BIT) {
                for function: 1..PCI_NUM_FUNCTIONS - 1 {
                    header := pci_read_header(xx bus, xx index, xx function);
                    if header.vendor_id == PCI_VENDOR_NO_DEVICE continue;

                    AddDevice(function);
                }
            }
        }
    }

    pci_devices_scanned = true;
}

pci_read_header :: (bus: u32, device: u32, function: u32) -> Pci_Header {
    pci_address: u32;
    pci_address |= function << 8;
    pci_address |= device   << 11;
    pci_address |= bus      << 16;
    pci_address |= 1        << 31;

    using Pci_Port;
    header: Pci_Header = ---;

    for 0..size_of(Pci_Header) / 4 - 1 {
        offset := cast(u32) it * 4;

        out(xx CONFIG_ADDRESS, pci_address | offset);
        register_value := in(xx CONFIG_DATA);

        << (cast(*u32) *header + it) = register_value;
    }
    return header;
}

pci_read_config_register :: (info: Pci_Device_Info, reg_index: u32) -> u32 {
    pci_address: u32;
    pci_address |= info.function << 8;
    pci_address |= info.index    << 11;
    pci_address |= info.bus      << 16;
    pci_address |= 1             << 31;

    using Pci_Port;
    offset := reg_index * 4;

    out(xx CONFIG_ADDRESS, pci_address | offset);
    return in(xx CONFIG_DATA);
}

pci_write_config_register :: (info: Pci_Device_Info, reg_index: u32, value: u32) {
    pci_address: u32;
    pci_address |= info.function << 8;
    pci_address |= info.index    << 11;
    pci_address |= info.bus      << 16;
    pci_address |= 1             << 31;

    using Pci_Port;
    offset := reg_index * 4;

    out(xx CONFIG_ADDRESS, pci_address | offset);
    out(xx CONFIG_DATA, value);
}

Pci_Base_Address_Type :: enum {
    MEMORY_32;
    MEMORY_64;
    IO;
}

pci_get_base_address :: (info: Pci_Device_Info, bar: u32) -> base: u64, limit: u32, io_space: bool {
    assert(info.header.header_type != 0x2);

    bar0 := pci_read_config_register(info, bar + 0x4);

    io_space := cast(bool) (bar0 & 0b001);
    _64bit := !io_space && (bar0 & 0b100);

    mask: u64;
    if io_space mask = 0xfffffffc;
    else        mask = 0xfffffff0;

    base: u64 = bar0 & mask;
    if _64bit {
        bar1 := pci_read_config_register(info, bar + 0x5);
        base |= bar1 << 32;
    }

    pci_write_config_register(info, bar + 0x4, 0xffffffff);
    limit := pci_read_config_register(info, bar + 0x4);

    pci_write_config_register(info, bar + 0x4, bar0);

    limit = cast(u32) ~(limit & mask) + 1;
    return base, limit, io_space;
}

pci_print_device_list :: () {
    // if !pci_devices_scanned pci_scan_all_devices();

    ti := type_info(Pci_Class_Code);

    print("\n|      Class      |        Subclass        |   Bus   |\n");
    print("------------------------------------------------------\n", theme.primary);
    for 0..pci_device_count - 1 {
        device_info := pci_device_info[it];

        print("| ");
        class := device_info.header.class_code;
        name := ti.names[class];
        print(name);
        for 0..15 - name.count print(" ");

        print("| ");
        subclass := device_info.header.subclass;
        if subclass == 0x80 name = "Other";
        else name = PCI_SUBCLASSES[class][subclass];

        if name.count > 22 name.count = 22;
        print(name);
        for 0..21 - name.count print(" ");

        print(" |   ");
        print(device_info.bus);
        print(":");
        print(device_info.index);
        print(":");
        print(device_info.function);
        print(" |\n");
    }
    print("\n");
}



Hda :: struct {
    pci_info: Pci_Device_Info;
    mm: *u8;
    codec_bitmap: u16;
    command_buffer: *u32;
}

hda_read :: (hda: *Hda, reg: Hda_Register, $T: Type = u32) -> T {
    return << cast(*T) (hda.mm + cast(int) reg);
}

hda_write :: (hda: *Hda, reg: Hda_Register, value: $T) {
    << cast(*T) (hda.mm + cast(int) reg) = value;
}

hda_set_bit :: (hda: *Hda, reg: Hda_Register, bit: int) {
    register := cast(*u32) (hda.mm + cast(int) reg);
    << register |= xx (1 << bit);
}

hda_unset_bit :: (hda: *Hda, reg: Hda_Register, bit: int) {
    register := cast(*u32) (hda.mm + cast(int) reg);
    << register &= xx ~(1 << bit);
}

hda_discover :: () -> Pci_Device_Info, bool {
    assert(pci_devices_scanned);

    for 0..pci_device_count-1 {
        info := pci_device_info[it];
        if info.header.class_code == .MULTIMEDIA && info.header.subclass == 0x3 {
            return info, true;
        }
    }

    return .{}, false;
}

Hda_Register :: enum {
    GCTL      :: 0x08;
    WAKEEN    :: 0x0c;
    STATESTS  :: 0x0e;

    CORBLBASE :: 0x40;
    CORBUBASE :: 0x44;
    CORBWP    :: 0x48;
    CORBRP    :: 0x4a;
    CORBCTL   :: 0x4c;
    CORBSIZE  :: 0x4e;

    RIRBLBASE :: 0x50;
    RIRBUBASE :: 0x54;
    RIRBWP    :: 0x58;
    RIRBRP    :: 0x5a;
    RIRBCTL   :: 0x5c;
    RIRBSIZE  :: 0x5e;
}

hda_init :: (pci: Pci_Device_Info) {
    hda: Hda;

    base, limit, io_space := pci_get_base_address(pci, 0);
    assert(!io_space);
    assert(base > 0);
    assert(limit > 0);

    hda.mm = cast(*u8) map_memory(limit, physical_address = base);
    hda.command_buffer = map_memory(0x1000, flags = Page_Flags.PRESENT | .READ_WRITE | .CACHE_DISABLE);

    hda_set_bit(*hda, .GCTL, 1);
    gctl := hda_read(*hda, .GCTL);
    assert(!gctl);

    hda_set_bit(*hda, .GCTL, 0);
    while !gctl {
        gctl = hda_read(*hda, .GCTL);
    }

    wait(100000);
    hda.codec_bitmap = hda_read(*hda, .STATESTS, u16);
    assert(hda.codec_bitmap > 0, "No codecs enumerated");

    {
        hda_unset_bit(*hda, .CORBCTL, 1);

        corbsize := hda_read(*hda, .CORBSIZE, u8);
        assert(corbsize >> 4 == 0b0100, "Large CORB size not supported");
        hda_set_bit(*hda, .CORBSIZE, 1);

        corb_base := hda.command_buffer;
        hda_write(*hda, .CORBLBASE, cast(u32)            corb_base);
        hda_write(*hda, .CORBUBASE, cast(u32) (cast(u64) corb_base) >> 32);

        hda_set_bit(*hda, .CORBRP, 15);
        hda_write(*hda, .CORBWP, cast(u16) 0);

        hda_set_bit(*hda, .CORBCTL, 1);
    }

    {
        hda_unset_bit(*hda, .RIRBCTL, 1);

        rirbsize := hda_read(*hda, .RIRBSIZE, u8);
        assert(rirbsize >> 4 == 0b0100, "Large RIRB size not supported");
        hda_set_bit(*hda, .RIRBSIZE, 1);

        rirb_base := hda.command_buffer + 256;
        hda_write(*hda, .RIRBLBASE, cast(u32)            rirb_base);
        hda_write(*hda, .RIRBUBASE, cast(u32) (cast(u64) rirb_base) >> 32);

        hda_set_bit(*hda, .RIRBWP, 15);
        hda_set_bit(*hda, .RIRBCTL, 1);
    }
}



PCI_SUBCLASSES :: ([] string).[
    .[
        "Non VGA Compatible Unclassified",
        "VGA Compatible Unclassified"
    ],
    .[
        "SCSI Bus Controller",
        "IDE Controller",
        "Floppy Disk Controller",
        "IPI Bus Controller",
        "RAID Controller",
        "ATA Controller",
        "Serial ATA Controller",
        "Serial Attached SCSI Controller",
        "Non-Volatile Memory Controller",
    ],
    .[
        "Ethernet Controller",
        "Token Ring Controller",
        "FFDI Controller",
        "ATM Controller",
        "ISDN Controller",
        "WorldFip Controller",
        "PICMG 2.14 Multi Computing Controller",
        "Infiniband Controller",
        "Fabric Controller",
    ],
    .[
        "VGA Compatible Controller",
        "XGA Controller",
        "3D Controller",
    ],
    .[
        "Multimedia Video Controller",
        "Multimedia Audio Controller",
        "Computer Telephony Device",
        "Audio Device",
    ],
    .[
        "RAM Controller",
        "Flash Controller",
    ],
    .[
        "Host Bridge",
        "ISA Bridge",
        "EISA Bridge",
        "MCA Bridge",
        "PCI-to-PCI Bridge",
        "PCMCIA Bridge",
        "NuBus Bridge",
        "CardBus Bridge",
        "RACEway Bridge",
        "PCI-to-PCI Bridge (Semi Transparent)",
        "InfiniBand-to-PCI Host Bridge",
    ],
    .[
        "Serial Controller",
        "Parallel Controller",
        "Multiport Serial Controller",
        "Modem",
        "IEEE 488.1/2 (GPIB) Controller",
        "Smart Card Controller",
    ],
    .[
        "Programmable Interrupt Controller",
        "DMA Controller",
        "Timer",
        "RTC Controller",
        "PCI Hot-Plug Controller",
        "SD Host Controller",
        "IOMMU",
    ],
    .[
        "Keyboard Controller",
        "Digitizer Pen",
        "Mouse Controller",
        "Scanner Controller",
        "Gameport Controller",
    ],
    .[
        "Generic",
    ],
    .[
        "386 Processor",
        "486 Processor",
        "Pentium",
        "Pentium Pro",
    ],
    .[
        "FireWire (IEEE 1394) Controller",
        "ACCESS Bus Controller",
        "SSA",
        "USB Controller",
        "Fibre Channel",
        "SMBus Controller",
        "InfiniBand Controller",
        "IPMI Interface",
        "SERCOS Interface (IEC 61491)",
        "CANbus Controller",
    ],
    .[
        "iRDA Compatible Controller",
        "Consumer IR Controller",
        "RF Controller",
        "Bluetooth Controller",
        "Broadband Controller",
        "Ethernet Controller (802.1a)",
        "Ethernet Controller (802.1b)",
    ],
    .[
        "I20",
    ],
    .[
        "Satellite TV Controller",
        "Satellite Audio Controller",
        "Satellite Voice Controller",
        "Satellite Data Controller",
    ],
    .[
        "Network and Computing Encryption/Decryption",
    ],
    .[
        "DPIO Modules",
        "Performance Counters",
    ],            
];
