
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
isr_slot_0x% :: () #c_call {
    c: Context;
    push_context c {
        clear_screen();

        print("\n\n       AN EXCEPTION HAS OCCURED:  ");
        print("%\n\n", theme.accent);
    }

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

    #if OS != .LINUX {
        write_string("This build program must be executed on linux, or within WSL.\n");
        return;
    }

    zip := read_entire_file("the_mailbag.zip");

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

        add_build_string(tprint("MAILBAG_SIZE     :: %;", zip.count), w);
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
            elf_header := cast(*Elf64_Ehdr) elf.data;

            get_section_header :: (index: int) -> *Elf64_Shdr #expand {
                base := `elf.data + `elf_header.e_shoff;
                base +=  index    * `elf_header.e_shentsize; //`
                header := cast(*Elf64_Shdr) base;
                return header;
            }

            print("Elf header: %\n\n", << elf_header);

            PAGE_TABLE_ADDRESS   :: 0x8000;
            PAGE_TABLE_SIZE      :: 0x6000;
            KERNEL_START_ADDRESS :: PAGE_TABLE_ADDRESS + PAGE_TABLE_SIZE;

            Patch :: struct {
                source: string;
                target: string;
                virtual_address: int;
                plt_index: int;
            }

            patches := Patch.[
                .{"crt_memset", "memset", 0, 0},
                .{"crt_memcpy", "memcpy", 0, 0},
            ];

            for 0..elf_header.e_shnum - 1 {
                header := get_section_header(it);
                if header.sh_type != SHT_SYMTAB continue;

                string_table_section_header := get_section_header(header.sh_link);
                table := elf.data + string_table_section_header.sh_offset;

                entry_count := header.sh_size / header.sh_entsize;
                assert(header.sh_size % header.sh_entsize == 0);

                for * patch: patches {
                    for 0..entry_count - 1 {
                        base := elf.data + header.sh_offset;
                        base += it * header.sh_entsize;
                        symbol := cast(*Elf64_Sym) base;

                        name := to_string(table + symbol.st_name);
                        if starts_with(name, patch.source) {
                            patch.virtual_address = xx symbol.st_value;
                            break;
                        }
                    }
                }
            }

            for 0..elf_header.e_shnum - 1 {
                header := get_section_header(it);
                if header.sh_type != SHT_RELA continue;

                {
                    section_name_table_header := get_section_header(elf_header.e_shstrndx);
                    name := to_string(elf.data + section_name_table_header.sh_offset + header.sh_name);
                    if name != ".rela.plt" continue;
                }

                symbol_table_section_header := get_section_header(header.sh_link);
                string_table_section_header := get_section_header(symbol_table_section_header.sh_link);

                symbol_table := elf.data + symbol_table_section_header.sh_offset;
                string_table := elf.data + string_table_section_header.sh_offset;

                entry_count := header.sh_size / header.sh_entsize;

                for * patch: patches {
                    for 0..entry_count - 1 {
                        base := elf.data + header.sh_offset;
                        base += it * header.sh_entsize;
                        rela := cast(*Elf64_Rela) base;

                        index := (rela.r_info >> 32);
                        symbol := cast(*Elf64_Sym) (symbol_table + index * symbol_table_section_header.sh_entsize);
                        name := to_string(string_table + symbol.st_name);

                        if name == patch.target {
                            patch.plt_index = xx it;
                            break;
                        }
                    }
                }
            }

            for 0..elf_header.e_shnum - 1 {
                header := get_section_header(it);
                if header.sh_type != SHT_PROGBITS continue;

                {
                    section_name_table_header := get_section_header(elf_header.e_shstrndx);
                    name := to_string(elf.data + section_name_table_header.sh_offset + header.sh_name);
                    if name != ".plt" continue;
                }

                PLT_ENTRY_SIZE :: 16;

                for patch: patches {
                    plt_offset := PLT_ENTRY_SIZE * (patch.plt_index + 1);
                    patch_target           := plt_offset + xx header.sh_offset;
                    source_virtual_address := plt_offset + xx header.sh_addr + 5;

                    jump := patch.virtual_address - source_virtual_address;

                    elf.data[patch_target] = 0xe9;
                    << (cast(*s32) (elf.data + patch_target + 1)) = xx jump;
                }
                break;
            }

            generated_asm: String_Builder;
            append(*generated_asm, "\n");
            append(*generated_asm, tprint("kernel_entry_point    equ 0x%\n", elf_header.e_entry));
            append(*generated_asm, tprint("kernel_start_address  equ 0x%\n", KERNEL_START_ADDRESS));
            append(*generated_asm, tprint("page_table_address    equ 0x%\n", PAGE_TABLE_ADDRESS));

            append(*generated_asm, "\nkernel_section_table:\n");
            kernel_binary: String_Builder;

            kernel_offset := KERNEL_START_ADDRESS;
            section_count: int;
            for 0..elf_header.e_phnum - 1 {
                base := elf.data + elf_header.e_phoff;
                base += it       * elf_header.e_phentsize;
                header := cast(*Elf64_Phdr) base;

                if header.p_type != PT_LOAD  continue;
                section_count += 1;

                append(*generated_asm, tprint("  .section_%:\n", section_count));
                append(*generated_asm, tprint("    dd 0x%\t\t; Target address (VMA)\n", header.p_vaddr));
                append(*generated_asm, tprint("    dd 0x%\t\t; Source address (LMA)\n", kernel_offset));
                append(*generated_asm, tprint("    dd 0x%\t\t; Bytes to zero clear\n",  header.p_memsz));
                append(*generated_asm, tprint("    dd 0x%\t\t; Bytes to copy\n",        header.p_filesz));

                // print("Header:\n%\n", << header);
                assert(header.p_vaddr + max(header.p_filesz, header.p_memsz) < 0x200_000);
                append(*kernel_binary, elf.data + header.p_offset, xx header.p_filesz);
                kernel_offset += xx header.p_filesz;
            }

            append(*kernel_binary, zip);

            section_count += 1;
            append(*generated_asm, tprint("  .section_%:\t\t ; The mailbag\n", section_count));
            append(*generated_asm, tprint("    dd 0x%\t\t; Target address (VMA)\n", 0x200_000));
            append(*generated_asm, tprint("    dd 0x%\t\t; Source address (LMA)\n", kernel_offset));
            append(*generated_asm, tprint("    dd 0x%\t\t; Bytes to zero clear\n",  0));
            append(*generated_asm, tprint("    dd 0x%\t\t; Bytes to copy\n",        zip.count));

            print("Mailbag size: %\n", zip.count);

            kernel_size := builder_string_length(*kernel_binary);
            write_entire_file(".build/kernel.bin", builder_to_string(*kernel_binary));

            append(*generated_asm, tprint("  .count: dd 0x%\n\n", section_count));

            kernel_sectors := kernel_size / 512 + 1;
            kernel_sectors += 0x7f - (kernel_sectors % 0x7f);

            append(*generated_asm, tprint("kernel_sectors equ 0x%\n", kernel_sectors));

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
        print("Padding size: %\n", padding_size);

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

    od_command := string.["od", "-t", "x1z", "-A", "x", "-v", ".build/boot_sector.bin"];
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
