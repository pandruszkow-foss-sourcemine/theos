
Nasm_Options :: struct {
    input_file_name: string;

    // Specifies the output file format.
    format: Nasm_Format = .BIN;

    // Causes nasm to assemble the given input file without first applying the macro preprocessor.
    assemble: bool;

    // Pre-defines a single line macro. The value field is optional.
    define: [..] struct {
        name: string;
        value: Any;
    };

    // Undefines a single-line macro.
    undefine: [..] string;

    // Causes nasm to generate debug information in selected format.
    generate_debug: bool;

    // Causes nasm to preprocess the given input file, and write the output to stdout (or the specified
    // output file name), and not actually assemble anything.
    preprocess: bool;

    // Adds a directory to the search path for include files. The directory specification must include
    // the trailing slash, as it will be directly prepended to the name of the include file.
    include: [..] string;

    // Causes an assembly listing to be directed to the given file, in which the original source is
    // displayed on the right hand side (plus the source for included files and the expansions of multi-line
    // macros) and the generated code is shown in hex on the left.
    listfile: string;

    // Causes nasm to output Makefile-style dependencies to stdout; normal output is suppressed.
    print_dependencies: bool;

    // Optimize branch offsets (0 disables).
    optimize: int;

    // Specifies a precise name for the output file, overriding nasm's default means of determining it.
    outfile: string;

    // Specifies files to be pre-included, before the main source file starts to be processed.
    pre_include: [..] string;

    // Causes nasm to assemble in SciTech TASM compatible mode.
    tasm: bool;

    // Causes nasm to enable or disable certain classes of warning messages.
    warnings: Nasm_Warnings = NASM_DEFAULT_WARNINGS;

    // Specifies error reporting format (gnu or vc).
    error_format: enum {
        DEFAULT;
        GNU;
        VC;
    } = .DEFAULT;

    // Causes nasm to redirect error messages to filename. This option exists to support operating systems on
    // which stderr is not easily redirected.
    error_file: string;

    // Causes nasm to send its error messages and/or help text to stdout instead of stderr.
    errors_to_stdout: bool;
}

run_nasm :: (options: Nasm_Options) -> bool, int, string, string {
    cmd: [..] string;
    array_add(*cmd, "nasm");

    array_add(*cmd, options.input_file_name);

    array_add(*cmd, "-f");
    format := tprint("%", options.format);
    to_lower_in_place(format);
    array_add(*cmd, format);

    if options.assemble array_add(*cmd, "-a");

    for options.define {
        array_add(*cmd, "-D");
        if it.value.value_pointer {
            array_add(*cmd, tprint("%=%", it.name, it.value));
        }
        else array_add(*cmd, it.name);
    }
    if options.preprocess array_add(*cmd, "-e");

    for options.undefine {
        array_add(*cmd, "-U");
        array_add(*cmd, it);
    }

    if options.generate_debug array_add(*cmd, "-g");

    for options.include {
        array_add(*cmd, "-I");
        array_add(*cmd, it);
    }

    for options.pre_include {
        array_add(*cmd, "-p");
        array_add(*cmd, it);
    }

    if options.outfile != "" {
        array_add(*cmd, "-o");
        array_add(*cmd, options.outfile);
    }

    if options.listfile != "" {
        array_add(*cmd, "-l");
        array_add(*cmd, options.listfile);
    }

    if options.error_file != "" {
        array_add(*cmd, "-Z");
        array_add(*cmd, options.error_file);
    }

    if options.error_format != .DEFAULT {
        array_add(*cmd, "-X");

        ti := type_info(type_of(options.error_format));
        name := to_lower_copy(ti.names[options.error_format]);
        array_add(*cmd, name);
    }

    if options.print_dependencies array_add(*cmd, "-M");
    if options.errors_to_stdout array_add(*cmd, "-s");
    if options.tasm array_add(*cmd, "-t");

    if options.optimize array_add(*cmd, tprint("-O%", options.optimize));

    ti := type_info(Nasm_Warnings);

    for 0..ti.names.count - 1 {
        enabled := options.warnings & xx (1 << it);
        if enabled != NASM_DEFAULT_WARNINGS & xx (1 << it) {
            name := ti.names[it];
            copy := to_lower_copy(name);

            for * cast([] u8) copy if << it == #char "_" {
                << it = #char "-";
            }

            array_add(*cmd, tprint("-w%1%2", ifx enabled then "+" else "-", copy));
        }
    }

    success, error_code, stdout, stderr := os_run_command(.. cmd, capture_and_return_output = true);
    return success, error_code, stdout, stderr;
}

Nasm_Format :: enum {
    BIN;       // flat-form binary files (e.g. DOS .COM, .SYS)
    ITH;       // Intel hex
    SREC;      // Motorola S-records
    AOUT;      // Linux a.out object files
    AOUTB;     // NetBSD/FreeBSD a.out object files
    COFF;      // COFF (i386) object files (e.g. DJGPP for DOS)
    ELF32;     // ELF32 (i386) object files (e.g. Linux)
    ELF64;     // ELF64 (x86_64) object files (e.g. Linux)
    ELFX32;    // ELFX32 (x86_64) object files (e.g. Linux)
    AS86;      // Linux as86 (bin86 version 0.3) object files
    OBJ;       // MS-DOS 16-bit/32-bit OMF object files
    WIN32;     // Microsoft Win32 (i386) object files
    WIN64;     // Microsoft Win64 (x86-64) object files
    RDF;       // Relocatable Dynamic Object File Format v2.0
    IEEE;      // IEEE-695 (LADsoft variant) object file format
    MACHO32;   // NeXTstep/OpenStep/Rhapsody/Darwin/MacOS X (i386) object files
    MACHO64;   // NeXTstep/OpenStep/Rhapsody/Darwin/MacOS X (x86_64) object files
    DBG;       // Trace of all info passed to output stage
    ELF;       // ELF (short name for ELF32)
    MACHO;     // MACHO (short name for MACHO32)
    WIN;       // WIN (short name for WIN32)
}

NASM_DEFAULT_WARNINGS :: Nasm_Warnings.MACRO_PARAMS | .MACRO_DEFAULTS | .ORPHAN_LABELS | .NUMBER_OVERFLOW | .FLOAT_OVERFLOW | .FLOAT_TOOLONG | .USER | .LOCK | .HLE | .BND | .ZEXT_RELOC | .PTR | .NEGATIVE_REP |.OTHER;

Nasm_Warnings :: enum_flags {
    MACRO_PARAMS;            // Macro calls with wrong parameter count [on]
    MACRO_SELFREF;           // Cyclic macro references [off]
    MACRO_DEFAULTS;          // Macros with more default than optional parameters [on]
    ORPHAN_LABELS;           // Labels alone on lines without trailing `:' [on]
    NUMBER_OVERFLOW;         // Numeric constant does not fit [on]
    GNU_ELF_EXTENSIONS;      // Using 8- or 16-bit relocation in ELF32, a GNU extension [off]
    FLOAT_OVERFLOW;          // Floating point overflow [on]
    FLOAT_DENORM;            // Floating point denormal [off]
    FLOAT_UNDERFLOW;         // Floating point underflow [off]
    FLOAT_TOOLONG;           // Too many digits in floating-point number [on]
    USER;                    // %warning directives [on]
    LOCK;                    // Lock prefix on unlockable instructions [on]
    HLE;                     // Invalid hle prefixes [on]
    BND;                     // Invalid bnd prefixes [on]
    ZEXT_RELOC;              // Relocation zero-extended to match output format [on]
    PTR;                     // Non-NASM keyword used in other assemblers [on]
    BAD_PRAGMA;              // Empty or malformed %pragma [off]
    UNKNOWN_PRAGMA;          // Unknown %pragma facility or directive [off]
    NOT_MY_PRAGMA;           // %pragma not applicable to this compilation [off]
    UNKNOWN_WARNING;         // Unknown warning in -W/-w or warning directive [off]
    NEGATIVE_REP;            // Regative %rep count [on]
    PHASE;                   // Phase error during stabilization [off]
    LABEL_REDEF;             // Label redefined to an identical value [off]
    LABEL_REDEF_LATE;        // Label (re)defined during code generation [error]
    OTHER;                   // Any warning not specifially mentioned above [on]
    ALL;                     // All possible warnings
}


#scope_module

#import "Process";
