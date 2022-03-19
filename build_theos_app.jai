
#run {
    set_build_options_dc(.{do_output = false});

    user_args, compiler_args := compiler_get_command_line_arguments();
    if !user_args.count assert(false);
    name := user_args[0];

    print("\n=== Compiling User Application \"%\" ===\n", name);
    {
        w := compiler_create_workspace("User Application");
        options := get_build_options(w);
        options.output_executable_name = name;
        options.output_type = .EXECUTABLE;
        options.entry_point_name = "start";

        options.stack_trace = false;
        options.array_bounds_check = .OFF;
        options.cast\_bounds_check = .OFF;
        options.math\_bounds_check = .OFF;
        options.null_pointer_check = .OFF;

        write_entire_file(".build/program_link.ld", linker_script);
        options.additional_linker_arguments = .["-T", ".build/program_link.ld"];

        set_build_options(options, w);

        add_build_file(tprint("%.jai", name), w);
    }
}

linker_script :: #string END
ENTRY(start)

SECTIONS {
    . = 0x300000;
    .text   : { * (.text);  }
    .rodata : { * (.rodata);  }
    .data   : { * (.data);  }
    .bss    : { * (.bss);  }
}
END;

#import "Compiler";
#import "File";
#import "Basic";
