
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
            PAGE_TABLE_SIZE      :: 1024 * 24;
            KERNEL_START_ADDRESS :: PAGE_TABLE_ADDRESS + PAGE_TABLE_SIZE;

            generated_asm: String_Builder;
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
                append(*generated_asm, tprint("    dd 0x%\t\t; Size in bytes\n", header.p_filesz));
                append(*generated_asm, tprint("    dd 0x%\t\t; Zero clear\n", header.p_memsz));

                // print("Header:\n%\n", << header);
                append(*kernel_binary, elf.data + header.p_offset, xx header.p_filesz);
                kernel_offset += xx header.p_filesz;
            }
            kernel_size := builder_string_length(*kernel_binary);

            write_entire_file(".build/kernel.bin", builder_to_string(*kernel_binary));

            append(*generated_asm, tprint("  .count: dd 0x%\n\n", count));
            append(*generated_asm, tprint("kernel_sectors equ 0x%\n", kernel_size / 512 + 1));

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
    nasm_command := string.["nasm", "boot.asm", "-f", "bin", "-o", ".build/boot_sector.bin"];
    success, error_code, stdout, stderr := os_run_command(.. nasm_command, capture_and_return_output = true);

    if !success {
        write_string("nasm failed to run!\n");
        return false;
    }

    write_string(stderr);
    write_string(stdout);

    if error_code {
        write_string("\nAssembly error:\n");
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
