
#load "modules/Nasm.jai";
#load "elf/elf.jai";

#if OS == .WINDOWS {
    generate_elf_bindings :: () {
        #import "Bindings_Generator";

        options: Generate_Bindings_Options;
        options.generate_compile_time_struct_checks = false;
        array_add(*options.source_files, "elf/elf.h");
        builder := generate_bindings(options);

        write_entire_file("elf/elf.jai", builder_to_string(*builder));
    }
}


ISR_DECLARATION :: #string ISR
isr_slot_0x% :: () {

    frame: *Isr_Stack_Frame;
    text_cursor = 0;

    print("\n\n    AN EXCEPTION HAS OCCURED:\n=== % ===\n");
    print("Interrupt frame: ====================\n");
    print("RIP:   "); print_hex(frame.ip);    print("\n");
    print("CS:    "); print_hex(frame.cs);    print("\n");
    print("FLAGS: "); print_hex(frame.flags); print("\n");
    print("SP:    "); print_hex(frame.sp);    print("\n");
    print("SS:    "); print_hex(frame.ss);    print("\n");
    print("=====================================\n");

    while true {}
}
ISR;

interrupts: [] struct { message: string; slot: int; } = .[
    .{ "Division by zero",                 0x00 },
    .{ "Debug exception",                  0x01 },
    .{ "Non-maskable interrupt exception", 0x02 },
    .{ "Breakpoint exception",             0x03 },
    .{ "Overflow exception",               0x04 },
    .{ "Bound range exceeded exception",   0x05 },
    .{ "Invalid opcode exception",         0x06 },
    .{ "Device not available exception",   0x07 },
    .{ "Double Fault",                     0x08 },
    .{ "Invalid TSS",                      0x0a },
    .{ "Segment not present",              0x0b },
    .{ "Stack segment fault",              0x0c },
    .{ "General protection fault",         0x0d },
    .{ "Page fault",                       0x0e },
    .{ "Floating point exception",         0x10 },
    .{ "Alignment check fault",            0x11 },
    .{ "Machine check fault",              0x12 },
    .{ "SIMD Float exception fault",       0x13 },
    .{ "Virtualization exception fault",   0x14 },
    .{ "Security exception fault",         0x1e },
];

#run {
    set_build_options_dc(.{do_output = false});
    user_args, compiler_args := compiler_get_command_line_arguments();
    for user_args {
        if it == "assemble" {
            assemble();
            return;
        }

        #if OS == .WINDOWS if it == "generate_bindings" {
            generate_elf_bindings();
        }
    }
    #if OS != .LINUX return;

    write_string("\n=== Compiling Kernel ===\n");
    {
        w := compiler_create_workspace("Kernel");
        options := get_build_options(w);
        options.output_executable_name = "kernel_elf";
        options.output_path = ".build/";
        options.output_type = .EXECUTABLE;
        options.entry_point_name = "kernel_entry";

        options.stack_trace = false;
        options.array_bounds_check = .OFF;
        options.cast\_bounds_check = .OFF;
        options.math\_bounds_check = .OFF;
        options.null_pointer_check = .OFF;

        options.additional_linker_arguments = .["-T", "link.ld"];

        set_build_options(options, w);

        compiler_begin_intercept(w);
        add_build_file("kernel.jai", w);

        {
            isr_code: String_Builder;
            for interrupts {
                append(*isr_code, tprint(ISR_DECLARATION, formatInt(it.slot, base=16), it.message));
                append(*isr_code, "\n");
            }

            append(*isr_code, "register_generated_isrs :: () {\n");
            for interrupts {
                append(*isr_code, tprint("    idt_add_handler(xx isr_slot_0x%, 0x%1);\n", formatInt(it.slot, base=16)));
            }
            append(*isr_code, "}\n");

            add_build_string(builder_to_string(*isr_code), w);
        }

        add_build_string(tprint("COMPILER_VERSION :: \"%\";", compiler_get_version_info(null)), w);

        for all_messages {
            if it.kind == .ERROR {
                write_string("Kernel Compilation Failure!\n");
                return;
            }
        }
        compiler_end_intercept(w);

        objdump_command := string.["objdump", "-x", ".build/kernel_elf", "-d"];
        success, error_code, stdout, stderr := os_run_command(.. objdump_command, capture_and_return_output = true);
        if !success || error_code != 0 {
            write_string("objdump failed to run!\n");
        }
        else write_entire_file(".build/kernel_elf.objdump.txt", stdout);
    }

    write_string("\n=== Reading ELF ===\n");
    {
        header_printer := context;
        header_printer.print_style.default_format_int.base = 16;
        header_printer.print_style.default_format_struct.use_newlines_if_long_form = true;

        push_context header_printer {
            elf := read_entire_file(".build/kernel_elf");
            using elf_header := cast(*Elf64_Ehdr) elf.data;

            print("Elf header: %\n\n", << elf_header);

            PAGE_TABLE_ADDRESS   :: 0x8000;
            PAGE_TABLE_SIZE      :: 0x4000;
            KERNEL_START_ADDRESS :: PAGE_TABLE_ADDRESS + PAGE_TABLE_SIZE;

            generated_asm: String_Builder;
            append(*generated_asm, "\n");
            append(*generated_asm, tprint("kernel_entry_point    equ 0x%\n", elf_header.e_entry));
            append(*generated_asm, tprint("kernel_start_address  equ 0x%\n", KERNEL_START_ADDRESS));
            append(*generated_asm, tprint("page_table_address    equ 0x%\n", PAGE_TABLE_ADDRESS));

            append(*generated_asm, "\nkernel_section_table:\n");
            kernel_binary: String_Builder;

            kernel_offset := KERNEL_START_ADDRESS;
            count: int;
            for 0..elf_header.e_phnum - 1 {
                base := elf.data + elf_header.e_phoff;
                base += it       * elf_header.e_phentsize;
                header := cast(*Elf64_Phdr) base;

                if header.p_type != PT_LOAD  continue;
                count += 1;

                append(*generated_asm, tprint("  .section_%:\n", count));
                append(*generated_asm, tprint("    dd 0x%\t\t; Target address (VMA)\n", header.p_vaddr));
                append(*generated_asm, tprint("    dd 0x%\t\t; Source address (LMA)\n", kernel_offset));
                append(*generated_asm, tprint("    dd 0x%\t\t; Qwords to zero clear\n", header.p_memsz  / 8));
                append(*generated_asm, tprint("    dd 0x%\t\t; Qwords to copy\n",       header.p_filesz / 8));

                // print("Header:\n%\n", << header);
                append(*kernel_binary, elf.data + header.p_offset, xx header.p_filesz);
                kernel_offset += xx header.p_filesz;
            }
            kernel_size := builder_string_length(*kernel_binary);
            write_entire_file(".build/kernel.bin", builder_to_string(*kernel_binary));

            append(*generated_asm, tprint("  .count: dd 0x%\n\n", count));
            append(*generated_asm, tprint("kernel_sectors equ 0x%\n", kernel_size / 512 + 1));

            if false for 0..elf_header.e_shnum - 1 {
                base := elf.data + elf_header.e_shoff;
                base += it       * elf_header.e_shentsize;
                header := cast(*Elf64_Shdr) base;

                if header.sh_type != SHT_SYMTAB continue;

                entry_count := header.sh_size / header.sh_entsize;
                assert(header.sh_size % header.sh_entsize == 0);

                for 0..entry_count - 1 {
                    base := elf.data + header.sh_offset;
                    base += it * header.sh_entsize;
                    symbol := cast(*Elf64_Sym) base;

                    // print("Symbol: \n%\n", << symbol);
                }
            }

            write_entire_file(".build/generated.asm", builder_to_string(*generated_asm));
        }
    }

    write_string("\n=== Assembling Boot Sector ===\n");
    {
        if !assemble() return;
    }

    write_string("\n=== Creating Disk Image ===\n");
    {
        boot_sector := read_entire_file(".build/boot_sector.bin");
        kernel      := read_entire_file(".build/kernel.bin");

        theos       := join(boot_sector, kernel);

        BOCHS_MINIMUM_DISK_SIZE :: 0x200 * 16 * 63;
        padding_size := BOCHS_MINIMUM_DISK_SIZE - theos.count;

        assert(padding_size >= 0, "Kernel too large, pad to the nearest sector");

        padding := cast(*u8) alloc(padding_size);
        memset(padding, 0, padding_size);

        theos = join(theos, to_string(padding, padding_size));
        write_entire_file("theos", theos);
    }
}

assemble :: () -> bool {
    options: Nasm_Options;
    options.outfile = ".build/boot_sector.bin";
    options.format = .BIN;
    options.input_file_name = "boot.asm";
    options.warnings |= .ALL;

    array_add(*options.include, ".build/");
    success, error_code, stdout, stderr := run_nasm(options);

    if !success {
        write_string("nasm failed to run!\n");
        return false;
    }

    write_string(stdout);

    if error_code {
        write_string("\nAssembly error:\n");
        write_string(stderr);
        return false;
    } else {
        write_string("Assembly success!\n");
    }

    od_command := string.["od", "-t", "x1", "-A", "n", ".build/boot_sector.bin"];
    success, error_code, stdout, stderr = os_run_command(.. od_command, capture_and_return_output = true);
    if !success || error_code != 0 {
        write_string("od failed to run!\n");
    }
    else write_entire_file(".build/boot_sector.hex.txt", stdout);

    return true;
}

#import "Compiler";
#import "Process";
#import "File";
#import "Basic";
#import "String";
