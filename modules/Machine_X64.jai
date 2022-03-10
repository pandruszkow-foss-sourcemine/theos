//
// Useful routines for 64-bit Intel x86 machines (which we tend to call x64 in this compiler).
// This is for routines that are very specific to this architecture. More-generic routines,
// like compare-and-swap, bit-scan, etc, that make sense on many machines (but may also
// be implemented in assembly on those machines), will be in a different place.
//

//
// For folks investigating this file: The #asm syntax is not yet finalized, and will change.
// So if you are going to be
// an early adopter, be aware of this! Also, we haven't tested it much, and it does not have
// full interoperability with many compiler features yet.  -jblow, 4 August 2021.
//

// These x86 enums must be kept in sync with asm_x86.h in the compiler.

x86_Vendor :: enum u8 {
    UNKNOWN             :: 0;
    INTEL               :: 1;
    AMD                 :: 2;
}

// @todo: remove the x86_Feature_Leaf enum casts everywhere

// There are 32-bits per leaf for feature flags. The order of these fields determines how the bits are laid out in the
// large bit array.
x86_Feature_Leaf :: enum u8 {
    // The hex number is the EAX input, the register name is the output.
    _01H_EDX            :: 0;
    _01H_ECX            :: 1;
    _19H_EBX            :: 2;
    
    // EXT means the high bit is set on the EAX input.
    _01H_EXT_EDX        :: 3;
    _01H_EXT_ECX        :: 4;
    _08H_EXT_EBX        :: 5;

    // The first column is EAX input and the second is ECX input.
    _07H_00H_EBX        :: 6;
    _07H_00H_ECX        :: 7;
    _07H_00H_EDX        :: 8;
    _07H_01H_EAX        :: 9;
    _0DH_01H_EAX        :: 10;

    NUMBER              :: 11;
}

// This enumerates all feature bits. See check_feature() below for testing if a flag is on.
x86_Feature_Flag :: enum u16 {
    FPU                 :: 32 * x86_Feature_Leaf._01H_EDX     + 0;    // Onboard x87 FPU
    VME                 :: 32 * x86_Feature_Leaf._01H_EDX     + 1;    // Virtual 8086 mode extensions
    DE                  :: 32 * x86_Feature_Leaf._01H_EDX     + 2;    // Debugging extensions
    PSE                 :: 32 * x86_Feature_Leaf._01H_EDX     + 3;    // Page Size Extension (4mb)
    TSC                 :: 32 * x86_Feature_Leaf._01H_EDX     + 4;    // RDTSC instruction
    MSR                 :: 32 * x86_Feature_Leaf._01H_EDX     + 5;    // RDMSR and WRMSR instructions
    PAE                 :: 32 * x86_Feature_Leaf._01H_EDX     + 6;    // Physical Address Extension
    MCE                 :: 32 * x86_Feature_Leaf._01H_EDX     + 7;    // Machine Check Exception
    CX8                 :: 32 * x86_Feature_Leaf._01H_EDX     + 8;    // CMPXCHG8B instruction
    APIC                :: 32 * x86_Feature_Leaf._01H_EDX     + 9;    // Onboard APIC
    SEP                 :: 32 * x86_Feature_Leaf._01H_EDX     + 11;   // SYSENTER and SYSEXIT instructions
    MTRR                :: 32 * x86_Feature_Leaf._01H_EDX     + 12;   // Memory Type Range Registers
    PGE                 :: 32 * x86_Feature_Leaf._01H_EDX     + 13;   // Page Global Entry bit in CR4
    MCA                 :: 32 * x86_Feature_Leaf._01H_EDX     + 14;   // Machine Check Architecture
    CMOV                :: 32 * x86_Feature_Leaf._01H_EDX     + 15;   // CMOV, FCOMI, and FCMOV instructions
    PAT                 :: 32 * x86_Feature_Leaf._01H_EDX     + 16;   // Page Attribute Table
    PSE_36              :: 32 * x86_Feature_Leaf._01H_EDX     + 17;   // 32-bit Page Size Extension
    PSN                 :: 32 * x86_Feature_Leaf._01H_EDX     + 18;   // Processor Serial Number
    CLFLUSH             :: 32 * x86_Feature_Leaf._01H_EDX     + 19;   // CLFLUSH instruction
    DS                  :: 32 * x86_Feature_Leaf._01H_EDX     + 21;   // Debug store (save trace of executed jumps)
    ACPI                :: 32 * x86_Feature_Leaf._01H_EDX     + 22;   // Onboard thermal control for ACPI
    MMX                 :: 32 * x86_Feature_Leaf._01H_EDX     + 23;   // MMX instructions
    FXSR                :: 32 * x86_Feature_Leaf._01H_EDX     + 24;   // FXSAVE and FXRSTOR instructions
    SSE                 :: 32 * x86_Feature_Leaf._01H_EDX     + 25;   // SSE instructions
    SSE2                :: 32 * x86_Feature_Leaf._01H_EDX     + 26;   // SSE2 instructions
    SS                  :: 32 * x86_Feature_Leaf._01H_EDX     + 27;   // CPU Cache implements self-snoop
    HTT                 :: 32 * x86_Feature_Leaf._01H_EDX     + 28;   // Hyper-threading
    TM                  :: 32 * x86_Feature_Leaf._01H_EDX     + 29;   // Thermal Monitor
    IA64                :: 32 * x86_Feature_Leaf._01H_EDX     + 30;   // Itanium processor emulating x86
    PBE                 :: 32 * x86_Feature_Leaf._01H_EDX     + 31;   // Pending Break Enable

    SSE3                :: 32 * x86_Feature_Leaf._01H_ECX     + 0;    // SSE3 instructions
    PCLMULQDQ           :: 32 * x86_Feature_Leaf._01H_ECX     + 1;    // PCLMULQDQ instruction
    DTEST64             :: 32 * x86_Feature_Leaf._01H_ECX     + 2;    // 64-bit debug store
    MONITOR             :: 32 * x86_Feature_Leaf._01H_ECX     + 3;    // MONITOR and MWAIT instructions (not allowed in user-mode)
    DS_CPL              :: 32 * x86_Feature_Leaf._01H_ECX     + 4;    // CPL qualified debug store
    VMX                 :: 32 * x86_Feature_Leaf._01H_ECX     + 5;    // Virtual Machine eXtensions
    SMX                 :: 32 * x86_Feature_Leaf._01H_ECX     + 6;    // Safer Mode eXtensions
    EIST                :: 32 * x86_Feature_Leaf._01H_ECX     + 7;    // Enhanced SpeedStep
    TM2                 :: 32 * x86_Feature_Leaf._01H_ECX     + 8;    // Thermal Monitor 2
    SSSE3               :: 32 * x86_Feature_Leaf._01H_ECX     + 9;    // Supplemental SSE3 instructions
    CNXT_ID             :: 32 * x86_Feature_Leaf._01H_ECX     + 10;   // L1 Context ID
    SDBG                :: 32 * x86_Feature_Leaf._01H_ECX     + 11;   // Silicon Debug Interface
    FMA                 :: 32 * x86_Feature_Leaf._01H_ECX     + 12;   // Fused multiply-add instructions (FMA3, not FMA4)
    CX16                :: 32 * x86_Feature_Leaf._01H_ECX     + 13;   // CMPXCHG16B instruction
    XTPR                :: 32 * x86_Feature_Leaf._01H_ECX     + 14;   // Task priority messages can be disabled
    PDCM                :: 32 * x86_Feature_Leaf._01H_ECX     + 15;   // Perfmon and debug capabilities
    PCID                :: 32 * x86_Feature_Leaf._01H_ECX     + 17;   // Process context identifiers
    DCA                 :: 32 * x86_Feature_Leaf._01H_ECX     + 18;   // Direct cache access for DMA writes
    SSE4_1              :: 32 * x86_Feature_Leaf._01H_ECX     + 19;   // SSE4.1 instructions
    SSE4_2              :: 32 * x86_Feature_Leaf._01H_ECX     + 20;   // SSE4.2 instructions
    X2APIC              :: 32 * x86_Feature_Leaf._01H_ECX     + 21;
    MOVBE               :: 32 * x86_Feature_Leaf._01H_ECX     + 22;   // MOVBE instruction
    POPCNT              :: 32 * x86_Feature_Leaf._01H_ECX     + 23;   // POPCNT instruction
    TSC_DEADLINE        :: 32 * x86_Feature_Leaf._01H_ECX     + 24;
    AES                 :: 32 * x86_Feature_Leaf._01H_ECX     + 25;   // AES instructions
    XSAVE               :: 32 * x86_Feature_Leaf._01H_ECX     + 26;   // XSAVE, XRSTOR, XSETBV, and XGETBV instructions
    OSXSAVE             :: 32 * x86_Feature_Leaf._01H_ECX     + 27;   // XSAVE enabled by OS
    AVX                 :: 32 * x86_Feature_Leaf._01H_ECX     + 28;   // Advanced Vector Extensions
    F16C                :: 32 * x86_Feature_Leaf._01H_ECX     + 29;   // Half precision float instructions
    RDRAND              :: 32 * x86_Feature_Leaf._01H_ECX     + 30;   // RDRAND instruction
    HYPERVISOR          :: 32 * x86_Feature_Leaf._01H_ECX     + 31;   // Hypervisor present (always zero on physical CPUs)

    AESKLE              :: 32 * x86_Feature_Leaf._19H_EBX     + 0;
    AESKLE_WIDE         :: 32 * x86_Feature_Leaf._19H_EBX     + 2;
    KEY_LOCKER_MSR      :: 32 * x86_Feature_Leaf._19H_EBX     + 4;

    SYSCALL_SYSRET      :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 11;   // SYSCALL and SYSRET instructions
    MP                  :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 19;   // Multiprocessor capable
    NX                  :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 20;   // No-execute page protection
    MMX_EXT             :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 22;   // AMD extensions to the MMX instruction set
    FXSR_OPT            :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 25;   // FXSAVE and FXRSTOR instruction optimizations
    PDPE1GB             :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 26;   // 1-GB paging support
    RDTSCP              :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 27;   // RDTSCP instruction
    _64BIT_MODE         :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 29;   // Long Mode
    _3DNOW_EXT          :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 30;   // AMD extensions to the 3DNow! instruction set
    _3DNOW              :: 32 * x86_Feature_Leaf._01H_EXT_EDX + 31;   // 3DNow! instruction set

    LAHF_SAHF           :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 0;    // LAHF and SAHF support in 64-bit mode
    CMP_LEGACY          :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 1;    // Core multi-processing legacy mode
    SVM                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 2;    // Secure virtual machine
    EXTAPIC             :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 3;    // Extended APIC space
    CR8_LEGACY          :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 4;    // 'LOCK MOV CR0' instead means 'MOV CR8'
    ABM                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 5;    // Advanced bit manipulation (LZCNT and POPCNT)
    SSE4A               :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 6;    // EXTRQ, INSERTQ, MOVNTSS, and MOVNTSD instructions
    MISALIGNED_SSE      :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 7;    // 16-byte alignment is not required
    _3DNOW_PREFETCH     :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 8;    // PREFETCH and PREFETCHW instructions
    OSVW                :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 9;    // OS-visible workaround
    IBS                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 10;   // Instruction based sampling
    XOP                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 11;   // Extended operation support
    SKINIT              :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 12;   // SKINIT and STGI instructions
    WDT                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 13;   // Watchdog timer
    LWP                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 15;   // Lightweight profiling
    FMA4                :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 16;   // 4-operand FMA instructions
    TCE                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 17;   // Translation Cache Extension
    NODE_ID             :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 19;
    TBM                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 21;   // Trailing Bit Manipulation instructions
    TOPOLOGY_EXTENSIONS :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 22;
    PERFCTR_CORE        :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 23;   // Core performance counter extensions
    PERFCTR_NB          :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 24;   // NB performance counter extensions
    DBX                 :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 26;   // Data breakpoints extension
    PERFTSC             :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 27;   // Performance TSC
    PCX_L2I             :: 32 * x86_Feature_Leaf._01H_EXT_ECX + 28;   // L2I perf counter extension

    CLZERO              :: 32 * x86_Feature_Leaf._08H_EXT_EBX + 0;    // CLZERO instruction
    INVLPGB             :: 32 * x86_Feature_Leaf._08H_EXT_EBX + 3;    // INVLPGB and TLBSYNC instructions
    RDPRU               :: 32 * x86_Feature_Leaf._08H_EXT_EBX + 4;    // RDPRU instruction
    MCOMMIT             :: 32 * x86_Feature_Leaf._08H_EXT_EBX + 8;    // MCOMMIT instruction
    WBNOINVD            :: 32 * x86_Feature_Leaf._08H_EXT_EBX + 9;    // WBNOINVD instruction

    FSGSBASE            :: 32 * x86_Feature_Leaf._07H_00H_EBX + 0;    // RDFSBASE, WRFSBASE, RDGSBASE, and WRGSBASE instructions
    TSC_ADJUST          :: 32 * x86_Feature_Leaf._07H_00H_EBX + 1;
    SGX                 :: 32 * x86_Feature_Leaf._07H_00H_EBX + 2;    // Software Guard Extensions
    BMI1                :: 32 * x86_Feature_Leaf._07H_00H_EBX + 3;    // Bit Manipulation Instruction Set 1
    HLE                 :: 32 * x86_Feature_Leaf._07H_00H_EBX + 4;    // TSX Hardware Lock Elision
    AVX2                :: 32 * x86_Feature_Leaf._07H_00H_EBX + 5;    // Advanced Vector Extensions 2
    FDP_EXCPTN_ONLY     :: 32 * x86_Feature_Leaf._07H_00H_EBX + 6;
    SMEP                :: 32 * x86_Feature_Leaf._07H_00H_EBX + 7;    // Supervisor Mode Execution Prevention
    BMI2                :: 32 * x86_Feature_Leaf._07H_00H_EBX + 8;    // Bit Manipulation Instruction Set 2
    ENHANCED_REP        :: 32 * x86_Feature_Leaf._07H_00H_EBX + 9;    // Fast long-length REP MOV and STO-SB
    INVPCID             :: 32 * x86_Feature_Leaf._07H_00H_EBX + 10;   // INVPCID instruction
    RTM                 :: 32 * x86_Feature_Leaf._07H_00H_EBX + 11;   // TSX Restricted Transactional Memory
    RDT_M               :: 32 * x86_Feature_Leaf._07H_00H_EBX + 12;
    DEP_FPU_CS_DS       :: 32 * x86_Feature_Leaf._07H_00H_EBX + 13;
    MPX                 :: 32 * x86_Feature_Leaf._07H_00H_EBX + 14;   // Memory Protection Extensions
    RDT_A               :: 32 * x86_Feature_Leaf._07H_00H_EBX + 15;
    AVX512F             :: 32 * x86_Feature_Leaf._07H_00H_EBX + 16;   // AVX-512 Foundation
    AVX512DQ            :: 32 * x86_Feature_Leaf._07H_00H_EBX + 17;   // AVX-512 Double and Quad-word instructions
    RDSEED              :: 32 * x86_Feature_Leaf._07H_00H_EBX + 18;   // RDSEED instruction
    ADX                 :: 32 * x86_Feature_Leaf._07H_00H_EBX + 19;   // ADCX and ADOX instructions
    SMAP                :: 32 * x86_Feature_Leaf._07H_00H_EBX + 20;   // Suprvisor Mode Access Prevention
    AVX512_IFMA         :: 32 * x86_Feature_Leaf._07H_00H_EBX + 21;   // AVX-512 Integer Fused Multiply-Add instructions
    PCOMMIT             :: 32 * x86_Feature_Leaf._07H_00H_EBX + 22;   // PCOMMIT instruction
    CLFLUSHOPT          :: 32 * x86_Feature_Leaf._07H_00H_EBX + 23;   // CLFLUSHOPT instruction
    CLWB                :: 32 * x86_Feature_Leaf._07H_00H_EBX + 24;   // CLWB instruction
    INTEL_PT            :: 32 * x86_Feature_Leaf._07H_00H_EBX + 25;   // Intel Processor Trace
    AVX512PF            :: 32 * x86_Feature_Leaf._07H_00H_EBX + 26;   // AVX-512 Prefetch instructions (Xeon Phi only)
    AVX512ER            :: 32 * x86_Feature_Leaf._07H_00H_EBX + 27;   // AVX-512 Exponential and Reciprocal instructions (Xeon Phi only)
    AVX512CD            :: 32 * x86_Feature_Leaf._07H_00H_EBX + 28;   // AVX-512 Conflict Detection instructions
    SHA                 :: 32 * x86_Feature_Leaf._07H_00H_EBX + 29;   // SHA extensions
    AVX512BW            :: 32 * x86_Feature_Leaf._07H_00H_EBX + 30;   // AVX-512 Byte and Word instructions
    AVX512VL            :: 32 * x86_Feature_Leaf._07H_00H_EBX + 31;   // AVX-512 Vector Length extensions

    PREFETCHWT1         :: 32 * x86_Feature_Leaf._07H_00H_ECX + 0;    // PREFETCHWT1 instruction (Xeon Phi only)
    AVX512_VBMI         :: 32 * x86_Feature_Leaf._07H_00H_ECX + 1;    // AVX-512 Vector Bit Manipulation Instructions
    UMIP                :: 32 * x86_Feature_Leaf._07H_00H_ECX + 2;    // User-mode Instruction Prevention
    PKU                 :: 32 * x86_Feature_Leaf._07H_00H_ECX + 3;    // Memory Protection Keys for User-mode pages
    OSPKE               :: 32 * x86_Feature_Leaf._07H_00H_ECX + 4;    // PKU enabled by OS
    WAITPKG             :: 32 * x86_Feature_Leaf._07H_00H_ECX + 5;    // Timed pause and user-level MONITOR and MWAIT
    AVX512_VBMI2        :: 32 * x86_Feature_Leaf._07H_00H_ECX + 6;    // AVX-512 Vector Bit Manipulation Instructions 2
    CET_SS              :: 32 * x86_Feature_Leaf._07H_00H_ECX + 7;    // Control flow enforcement shadow stack
    GFNI                :: 32 * x86_Feature_Leaf._07H_00H_ECX + 8;    // Galois Field instructions
    VAES                :: 32 * x86_Feature_Leaf._07H_00H_ECX + 9;    // AES instruction set for VEX-256 and EVEX
    VPCLMULQDQ          :: 32 * x86_Feature_Leaf._07H_00H_ECX + 10;   // CLMUL instruction set for VEX-256 and EVEX
    AVX512_VNNI         :: 32 * x86_Feature_Leaf._07H_00H_ECX + 11;   // AVX-512 Vector Neural Network Instructions
    AVX512_BITALG       :: 32 * x86_Feature_Leaf._07H_00H_ECX + 12;   // AVX-512 BITALG instructions
    TME_EN              :: 32 * x86_Feature_Leaf._07H_00H_ECX + 13;   // TME MSRs are available
    AVX512_VPOPCNTDQ    :: 32 * x86_Feature_Leaf._07H_00H_ECX + 14;   // AVX-512 Vector Population Count (Xeon Phi only)
    FIVE_LEVEL_PAGING   :: 32 * x86_Feature_Leaf._07H_00H_ECX + 16;
    MAWAU_0             :: 32 * x86_Feature_Leaf._07H_00H_ECX + 17;   // MPX Address-Width Adjust Used (5 bits)
    MAWAU_1             :: 32 * x86_Feature_Leaf._07H_00H_ECX + 18;
    MAWAU_2             :: 32 * x86_Feature_Leaf._07H_00H_ECX + 19;
    MAWAU_3             :: 32 * x86_Feature_Leaf._07H_00H_ECX + 20;
    MAWAU_4             :: 32 * x86_Feature_Leaf._07H_00H_ECX + 21;
    RDPID               :: 32 * x86_Feature_Leaf._07H_00H_ECX + 22;   // RDPID instruction
    KL                  :: 32 * x86_Feature_Leaf._07H_00H_ECX + 23;   // Key Locker support
    CLDEMOTE            :: 32 * x86_Feature_Leaf._07H_00H_ECX + 25;   // CLDEMOTE instruction
    MOVDIRI             :: 32 * x86_Feature_Leaf._07H_00H_ECX + 27;   // MOVDIRI instruction
    MOVDIR64B           :: 32 * x86_Feature_Leaf._07H_00H_ECX + 28;   // MOVDIR64B instruction
    ENQCMD              :: 32 * x86_Feature_Leaf._07H_00H_ECX + 29;   // ENQCMD instruction
    SGX_LC              :: 32 * x86_Feature_Leaf._07H_00H_ECX + 30;   // SGX launch configuration
    PKS                 :: 32 * x86_Feature_Leaf._07H_00H_ECX + 31;   // Protection keys for supervisor-mode pages

    AVX512_4VNNIW       :: 32 * x86_Feature_Leaf._07H_00H_EDX + 2;    // AVX-512 4-register Neural Network Instructions (Xeon Phi only)
    AVX512_4FMAPS       :: 32 * x86_Feature_Leaf._07H_00H_EDX + 3;    // AVX-512 4-register FMA instructions (Xeon Phi only)
    FSRM                :: 32 * x86_Feature_Leaf._07H_00H_EDX + 4;    // Fast short-length REP MOVSB
    AVX512_VP2INTERSECT :: 32 * x86_Feature_Leaf._07H_00H_EDX + 8;    // AVX-512 VP2INTERSECT for Double and Quad-words instructions
    SRBDS_CTRL          :: 32 * x86_Feature_Leaf._07H_00H_EDX + 9;
    MD_CLEAR            :: 32 * x86_Feature_Leaf._07H_00H_EDX + 10;
    TSX_FORCE_ABORT     :: 32 * x86_Feature_Leaf._07H_00H_EDX + 13;
    SERIALIZE           :: 32 * x86_Feature_Leaf._07H_00H_EDX + 14;   // SERIALIZE instruction
    HYBRID              :: 32 * x86_Feature_Leaf._07H_00H_EDX + 15;
    TSXLDTRK            :: 32 * x86_Feature_Leaf._07H_00H_EDX + 16;
    PCONFIG             :: 32 * x86_Feature_Leaf._07H_00H_EDX + 18;   // PCONFIG instruction
    LBR                 :: 32 * x86_Feature_Leaf._07H_00H_EDX + 19;
    CET_IBT             :: 32 * x86_Feature_Leaf._07H_00H_EDX + 20;   // Control flow enforcement indirect branch tracking
    AMX_BF16            :: 32 * x86_Feature_Leaf._07H_00H_EDX + 22;   // Tile computations on bfloat16
    AVX512_FP16         :: 32 * x86_Feature_Leaf._07H_00H_EDX + 23;   // AVX-512 half-precision floating-point instructions
    AMX_TILE            :: 32 * x86_Feature_Leaf._07H_00H_EDX + 24;   // Tile architecture
    AMX_INT8            :: 32 * x86_Feature_Leaf._07H_00H_EDX + 25;   // Tile computation on 8-bit integers
    SPEC_CTRL           :: 32 * x86_Feature_Leaf._07H_00H_EDX + 26;
    STIBP               :: 32 * x86_Feature_Leaf._07H_00H_EDX + 27;
    L1D_FLUSH           :: 32 * x86_Feature_Leaf._07H_00H_EDX + 28;
    ARCH_CAPABILITIES   :: 32 * x86_Feature_Leaf._07H_00H_EDX + 29;
    CORE_CAPABILITIES   :: 32 * x86_Feature_Leaf._07H_00H_EDX + 30;
    SSBD                :: 32 * x86_Feature_Leaf._07H_00H_EDX + 31;

    AVX_VNNI            :: 32 * x86_Feature_Leaf._07H_01H_EAX + 4;    // VEX-encoded version of the VNNI instructions
    AVX512_BF16         :: 32 * x86_Feature_Leaf._07H_01H_EAX + 5;    // AVX-512 bfloat16 instructions
    FZRM                :: 32 * x86_Feature_Leaf._07H_01H_EAX + 10;   // Fast zero-length REP MOVSB
    FSRS                :: 32 * x86_Feature_Leaf._07H_01H_EAX + 11;   // Fast short-length REP STOSB
    FSRCS               :: 32 * x86_Feature_Leaf._07H_01H_EAX + 12;   // Fast short-length REP CMP and SCA-SB (are there earlier long-length versions?)
    HRESET              :: 32 * x86_Feature_Leaf._07H_01H_EAX + 22;   // History reset support
    LAM                 :: 32 * x86_Feature_Leaf._07H_01H_EAX + 26;   // Linear Address Masking

    XSAVEOPT            :: 32 * x86_Feature_Leaf._0DH_01H_EAX + 0;
    XSAVEC              :: 32 * x86_Feature_Leaf._0DH_01H_EAX + 1;
    XGETBV_ECX1         :: 32 * x86_Feature_Leaf._0DH_01H_EAX + 2;
    XSAVES_XRSTORS      :: 32 * x86_Feature_Leaf._0DH_01H_EAX + 3;
    XFD                 :: 32 * x86_Feature_Leaf._0DH_01H_EAX + 4;
}

//
// A helper struct you can use to get information about the machine
// and its instruction capabilities. Call get_cpu_info() to get
// one of these.
//
Cpu_X86 :: struct {
    vendor: x86_Vendor;
    feature_leaves: [x86_Feature_Leaf.NUMBER] u32 = ---;
};

get_cpu_info :: (cpu: *Cpu_X86) {
    // The cpuid instruction will give us back the wrong info if we pass an 'a' value that is too large for the cpu we
    // are on, so instead we check the max value (for basic and extended separately) and only ask for the info if we
    // know it is supported.
    max_basic_info: u32 = ---;
    max_extended_info: u32 = ---;

    // @todo: once we have control flow in #asm, it'd be nice to just check the vendor there
    vendor_chunk_0: u32 = ---;
    vendor_chunk_1: u32 = ---;
    vendor_chunk_2: u32 = ---;

    #asm {
        xor.d a: gpr === a, a;
        xor.d c: gpr === c, c;
        cpuid a, b:, c, d:;
        mov.d max_basic_info, a;

        mov.d vendor_chunk_0, b;
        mov.d vendor_chunk_1, d;
        mov.d vendor_chunk_2, c;

        mov.d a, 0x80000000;
        xor.d c, c;
        cpuid a, b, c, d;
        mov.d max_extended_info, a;
    }

    // GenuineIntel
    if (vendor_chunk_0 == 0x756E6547 && vendor_chunk_1 == 0x49656E69 && vendor_chunk_2 == 0x6C65746E) cpu.vendor = .INTEL;

    // AuthenticAMD
    if (vendor_chunk_0 == 0x68747541 && vendor_chunk_1 == 0x69746E65 && vendor_chunk_2 == 0x444D4163) cpu.vendor = .AMD;

    // @todo: when we have stack and struct field offset memory addressing working, this pointer gathering won't be necessary
    feature_flags_0  := *cpu.feature_leaves[x86_Feature_Leaf._01H_EDX];
    feature_flags_1  := *cpu.feature_leaves[x86_Feature_Leaf._01H_ECX];
    feature_flags_2  := *cpu.feature_leaves[x86_Feature_Leaf._19H_EBX];
    feature_flags_3  := *cpu.feature_leaves[x86_Feature_Leaf._01H_EXT_EDX];
    feature_flags_4  := *cpu.feature_leaves[x86_Feature_Leaf._01H_EXT_ECX];
    feature_flags_5  := *cpu.feature_leaves[x86_Feature_Leaf._08H_EXT_EBX];
    feature_flags_6  := *cpu.feature_leaves[x86_Feature_Leaf._07H_00H_EBX];
    feature_flags_7  := *cpu.feature_leaves[x86_Feature_Leaf._07H_00H_ECX];
    feature_flags_8  := *cpu.feature_leaves[x86_Feature_Leaf._07H_00H_EDX];
    feature_flags_9  := *cpu.feature_leaves[x86_Feature_Leaf._07H_01H_EAX];
    feature_flags_10 := *cpu.feature_leaves[x86_Feature_Leaf._0DH_01H_EAX];

    if max_basic_info >= 0x01 #asm {
        mov.d a: gpr === a, 0x01;
        xor.d c: gpr === c, c;
        cpuid a, b:, c, d:;
        mov.d [feature_flags_0], d;
        mov.d [feature_flags_1], c;
    }

    if max_basic_info >= 0x19 #asm {
        mov.d a: gpr === a, 0x19;
        xor.d c: gpr === c, c;
        cpuid a, b:, c, d:;
        mov.d [feature_flags_2], b;
    }

    if max_extended_info >= 0x80000001 #asm {
        mov.d a: gpr === a, 0x80000001;
        xor.d c: gpr === c, c;
        cpuid a, b:, c, d:;
        mov.d [feature_flags_3], d;
        mov.d [feature_flags_4], c;
    }

    if max_extended_info >= 0x80000008 #asm {
        mov.d a: gpr === a, 0x80000008;
        xor.d c: gpr === c, c;
        cpuid a, b:, c, d:;
        mov.d [feature_flags_5], b;
    }

    if max_basic_info >= 0x07 #asm {
        mov.d a: gpr === a, 0x07;
        xor.d c: gpr === c, c;
        cpuid a, b:, c, d:;
        mov.d [feature_flags_6], b;
        mov.d [feature_flags_7], c;
        mov.d [feature_flags_8], d;

        mov.d a, 0x07;
        mov.d c, 0x01;
        cpuid a, b, c, d;
        mov.d [feature_flags_9], a;
    }

    if max_basic_info >= 0x0D #asm {
        mov.d a: gpr === a, 0x0D;
        mov.d c: gpr === c, 0x01;
        cpuid a, b:, c, d:;
        mov.d [feature_flags_10], a;
    }
}

check_feature :: (leaves: [x86_Feature_Leaf.NUMBER] u32, flag: x86_Feature_Flag) -> bool {
    return leaves[flag >> 5] & (1 << (flag & 31)) != 0;
}

enable_feature :: (leaves: *[x86_Feature_Leaf.NUMBER] u32, flag: x86_Feature_Flag) {
    (<< leaves)[flag >> 5] |= cast(u32) 1 << (flag & 31);
}

disable_feature :: (leaves: *[x86_Feature_Leaf.NUMBER] u32, flag: x86_Feature_Flag) {
    (<< leaves)[flag >> 5] &= ~cast(u32) (1 << (flag & 31));
}

//
// Lower-level hooks to specific assembly instructions:
// 

Prefetch_Hint :: enum {
    T0  :: 0;
    T1  :: 1;
    T2  :: 2;
    NTA :: 3;
}

prefetch :: (pointer: *void, $hint: Prefetch_Hint) #expand {
    #if hint == .NTA {
        #asm { prefetchnta [pointer]; }
    } else #if hint == .T0 {
        #asm { prefetcht0  [pointer]; }
    } else #if hint == .T1 {
        #asm { prefetcht1  [pointer]; }
    } else #if hint == .T2 {
        #asm { prefetcht2  [pointer]; }
    } else {
        #assert false "'hint' argument to prefetch is out of range.";
    }
}

rdtsc :: () -> u64 #expand {
    result: u64 = ---;

    #asm {
        result === a;
        
        rdtsc high:, result;
        shl.q high, 32;
        or.q  result, high;
    }
    
    return result;
}

rdtscp :: () -> (timestamp: u64, msr: u32) #expand {
    result: u64 = ---;
    msr:    u32 = ---;
    
    #asm {
        result === a;
        msr === c;
        
        rdtscp high:, result, msr;
        shl.q  high, 32;
        or.q   result, high;
    }
    
    return result, msr;
}

rdseed :: () -> (success: bool, value: u64) #expand {
    success: bool = ---;
    value:   u64  = ---;

    #asm {
        rdseed.q value;
        setc     success;
    }
    
    return success, value;
}

rdrand :: () -> (success: bool, value: u64) #expand {
    success: bool = ---;
    value:   u64  = ---;

    #asm {
        rdrand.q value;
        setc     success;
    }
    
    return success, value;
}

mfence :: () #expand {
    #asm { mfence; }
}

pause :: () #expand {
    #asm { pause; }
}
