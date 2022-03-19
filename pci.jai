
PCI_MAX_BUSES        :: 256;
PCI_MAX_DEVICES      :: 32;
PCI_NUM_FUNCTIONS    :: 8;
PCI_VENDOR_NO_DEVICE :: 0xffff;
PCI_HEADER_TYPE_MULTIFUNCTION_BIT :: 0x80;

Pci_Class_Code :: enum u8 {
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

    // union {
    //     type_0: Pci_Header_Type_0x0;
    //     type_1: Pci_Header_Type_0x1;
    // };
}

Pci_Header_Type_0x0 :: struct {
    base_address_0:   u32;
    base_address_1:   u32;
    base_address_2:   u32;
    base_address_3:   u32;
    base_address_4:   u32;
    base_address_5:   u32;
    cardbus_cis:      u32;
    subsystem_vendor: u16;
    subsystem_id:     u16;
    expansion_rom:    u32;
    capabilities:     u8;
    reserved:         [7] u8;
    interrupt_line:   u8;
    interrupt_pin:    u8;
    min_grant:        u8;
    max_latency:      u8;
}

Pci_Header_Type_0x1 :: struct {
    base_address_0:             u32;
    base_address_1:             u32;
    primary_bus_number:         u8;
    secondary_bus_number:       u8;
    subordinate_bus_number:     u8;
    secondary_latency_timer:    u8;
    io_base:                    u8;
    io_limit:                   u8;
    secondary_status:           u16;
    memory_base:                u16;
    memory_limit:               u16;
    prefetchable_memory_base:   u16;
    prefetchable_memory_limit:  u16;
    prefetchable_base_upper:    u32;
    prefetchable_limit_upper:   u32;

    io_base_upper:              u16;
    io_limit_upper:             u16;
    capability_pointer:         u8;
    reserved:                   [3] u8;
    expansion_rom_base_address: u32;
    interrupt_line:             u8;
    interrupt_pin:              u8;
    bridge_control:             u16;
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
    address: u32;
    address |= function << 8;
    address |= device   << 11;
    address |= bus      << 16;
    address |= 1        << 31;

    using Pci_Port;
    header: Pci_Header = ---;

    for 0..size_of(Pci_Header) / 4 - 1 {
        offset := cast(u32) it * 4;

        out(xx CONFIG_ADDRESS, address | offset);
        register_value := in(xx CONFIG_DATA);

        << (cast(*u32) *header + it) = register_value;
    }
    return header;
}

pci_read_configuration_register :: (info: Pci_Device_Info, reg_index: u32) -> u32 {
    address: u32;
    address |= info.function << 8;
    address |= info.index    << 11;
    address |= info.bus      << 16;
    address |= 1             << 31;

    using Pci_Port;
    offset := reg_index * 4;

    out(xx CONFIG_ADDRESS, address | offset);
    return in(xx CONFIG_DATA);
}

pci_print_device_list :: () {
    if !pci_devices_scanned pci_scan_all_devices();

    ti := type_info(Pci_Class_Code);
    for 0..pci_device_count - 1 {
        device_info := pci_device_info[it];

        print("    PCI device, class ");
        name := ti.names[device_info.header.class_code - 1];
        print(name);
        for 0..15 - name.count print(" ");
        print("subclass ");
        print_hex(device_info.header.subclass);

        print(" | Address ");
        print(device_info.bus);
        print(":");
        print(device_info.index);
        print(":");
        print(device_info.function);
        print("\n");
    }
}



hda_detect :: () {
    assert(pci_devices_scanned);
    for 0..pci_device_info.count-1 {
        info := pci_device_info[it];
        if info.header.class_code == .MULTIMEDIA && info.header.subclass == 0x3 {
            print("\nFound HDA at ");
            print(info.bus);
            print(":");
            print(info.index);
            print(":");
            print(info.function);

            print("\nHeader type: "); print(info.header.header_type);
            print("\n\nConfig registers:\n");

            margin += 2; text_cursor += 2;
            for 0..0xf {
                print_hex(cast(u8) it); print(": ");
                bar := pci_read_configuration_register(info, cast(u32) it);
                print_hex(bar);
                print("\n");
            }
            margin -= 2;
        }
    }
}
