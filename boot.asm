
%define vbs 0x10
%define vbs_str 0x13
%define vbs_tty 0x0e

%define vbs_vesa_info      0x4f00
%define vbs_vesa_mode_info 0x4f01
%define vbs_vesa_set_mode  0x4f02

%define vesa_success 0x4f

%define dbs 0x13
%define dbs_read 0x02
%define dbs_ext_read 0x42

%define sbe 0x15

%define PRINT_MODES 0

[org 0x7c00]
[bits 16]

stack:
    jmp 0:start

%include "generated.asm"

start:
    mov [.boot_drive], dl
    mov byte [boot_data_area + 4], dl

    ; === Segment registers ===
    xor ax, ax
    mov es, ax
    mov ss, ax
    mov ds, ax

    ; === Stack registers ===
    mov bp, stack
    mov sp, bp

    ; === Video mode ===
    mov al, 0x3
    int vbs

    ; === Load the rest of the bootloader ===
    mov ah, dbs_read
    mov al, bootloader_sectors - 1
    mov cx, 2
    mov dh, 0
    mov dl, [.boot_drive]
    mov bx, second_sector

    int dbs

    xor bx, bx
    mov bl, ah
    call write_hex

    ; === Write string ===
    mov bx, .greeting
    call write_string

    ; === Enable A20 (probably) ===
    mov ax, 0x2401
    int 0x15

    ; === Get memory map ===
    mov word [boot_data_area + 6], 0
    mov di, boot_data_area + 0x800;
    xor ebx, ebx

  .mmap_loop:
    mov eax, 0xe820
    mov edx, 0x534D4150
    mov ecx, 24
    add di, 24

    int sbe

    cmp ebx, 0x0
    je .mmap_end
    inc word [boot_data_area + 6]
    jmp .mmap_loop
  .mmap_end:
    mov word [boot_data_area + 8], boot_data_area + 0x800

%if ENABLE_VESA
    ; === Get VESA info ===
    mov di, vbe_info_block
    mov ax, vbs_vesa_info
    int vbs
    cmp al, vesa_success
    jne .fail

    ; === Iterate VESA mode numbers ===
    mov bx, vbe_info_block.video_modes

  .loop:
    mov cx, [bx]
    cmp cx, 0xffff
    je .fail

    mov di, vbe_mode
    mov ax, vbs_vesa_mode_info
    int vbs

    ; === Display VESA mode parameters ===
    ; pusha
    ; mov bx, [bx]
    ; call write_hex
    ; 
    ; mov bx, [vbe_mode.width]
    ; call write_hex
    ; 
    ; mov bx, [vbe_mode.height]
    ; call write_hex
    ; 
    ; xor bx, bx
    ; mov byte bl, [vbe_mode.bpp]
    ; call write_hex
    ; call newline
    ; popa

    add bx, 2

    cmp word [vbe_mode.width], vesa_width
    jne .loop
    cmp word [vbe_mode.height], vesa_height
    jne .loop
    cmp byte [vbe_mode.bpp], vesa_depth
    jne .loop
    mov ax, [vbe_mode.attributes]
    test ax, 1 << 7
    jz .loop

    jmp .succeed

  .fail:
    mov bx, .vesa_fail
    call write_string
    jmp $

  .succeed:
    mov ax, vbs_vesa_set_mode
    mov bx, [bx - 2]
    or bx, 0x4000
    int vbs
    cmp ax, vesa_success
    jne .fail

    mov dword eax, [vbe_mode.buffer]
    mov dword [boot_data_area], eax
%endif ; ENABLE_VESA

    call load_kernel_dbs

    ; === Switch to Long Mode ===
    mov edi, page_table_address
    jmp SwitchToLongMode

  .greeting: db 'Hello, sailor', 0xa, 0xd, 0
  .msg_b: db 'Loading kernel', 0xa, 0xd, 0
  .msg_c: db 'Switching to long mode', 0xa, 0xd, 0

%if ENABLE_VESA
  .vesa_fail: db '  No appropriate VESA mode was found, or VESA is not supported.', 0xa, 0xd, 0
%endif
  .boot_drive: db 0
  .space: db ' ', 0

write_string:
    pusha
    mov ah, vbs_tty

  .loop:
    mov al, [bx]
    cmp al, 0
    je .end
    inc bx
    int vbs

    jmp .loop

  .end:
    popa
    ret

newline:
    pusha
    mov bx, .lfcr
    call write_string
    popa
    ret

  .lfcr: db 0xa, 0xd, 0

write_hex:
    pusha

    mov cx, bx
    mov bx, .prefix
    call write_string
    mov bx, cx
    mov cx, 12

  .loop:
    push bx
    sar bx, cl
    and bx, 0xf
    mov ax, [.table + bx]
    mov [.char], al
    mov bx, .char
    call write_string

    pop bx
    sub cx, 4
    cmp cx, 0
    jge .loop

    popa
    mov bx, start.space
    call write_string
    ret

  .table: db '0123456789abcdef', 0
  .char: db 0, 0
  .prefix: db '0x', 0

; === Fake partition table ===
; times 0x1b8-($-$$) db 0
; 
; dd 0x89abcdef
; dw 0x0
; 
; db 0x00, 0x01, 0x01, 0x00, 0x06, 0x3f, 0x3f, 0xc4
; db 0x3f, 0x00, 0x00, 0x00, 0x81, 0x1e, 0x0c, 0x00

times 0x1fe-($-$$) db 0
dw 0xaa55
second_sector:

[bits 16]
disk_address_packet:
  .size:        db 10h
  .reserved:    db 0
  .num_sectors: dw 10h
  .buffer:      dw 0
  .segment:     dw 0
  .source_lba:  dq bootloader_sectors

load_kernel_dbs:
    pusha

    mov bx, kernel_start_address >> 4
    mov cx, kernel_sectors

    ; === Point DS:SI at address packet ===
    xor ax, ax
    mov ds, ax
    mov si, disk_address_packet

  .loop:
    mov word [disk_address_packet.segment], bx
    add bx, 0x200

    ; === Call BIOS extended read ===
    mov dl, [start.boot_drive]
    mov ah, dbs_ext_read
    mov al, 0

    cld
    int dbs
    add word [disk_address_packet.source_lba], 0x10
    sub cx, 0x10
    jns .loop

    popa
    ret

%include "long.asm"

[bits 64]
long_mode_start:
    mov rbp, 0x1ff000
    mov rsp, rbp

    mov ecx, 0x100000
  .clear_loop:
    mov byte [ecx], 0
    inc ecx
    cmp ecx, 0x200000
    jne .clear_loop

    cld
    xor ebx, ebx
  .loop:
    cmp dword ebx, [kernel_section_table.count]
    je .end

    ; === Target address ===
    mov eax, ebx
    imul eax, 16
    add eax, kernel_section_table
    mov edi, [eax]

    ; === Source address ===
    mov esi, [eax + 4]

    ; === Clear ===
    mov ecx, [eax + 8]

    push rax
    push rdi

    xor eax, eax
    ; rep stosb

    pop rdi
    pop rax

    ; === Copy ===
    mov ecx, [eax + 12]
    rep movsb

    inc ebx
    jmp .loop

  .end:
    jmp kernel_entry_point

load_kernel:
    mov r8, kernel_sectors
    mov r9, bootloader_sectors
    mov edi, kernel_start_address

  .loop:
    mov rax, r9
    shr eax, 24
    or al, 0b11100000
    mov dx, 0x1f6
    out dx, al

    mov dx, 0x1f2
    mov al, 0x7f
    out dx, al

    mov rax, r9
    mov dx, 0x1f3
    out dx, al

    shr rax, 8
    mov dx, 0x1f4
    out dx, al

    shr rax, 8
    mov dx, 0x1f5
    out dx, al

    mov al, 0x20
    mov dx, 0x1f7
    out dx, al

  .wait_for_trq:
    in al, dx
    test al, 8
    jz .wait_for_trq

    mov rax, 256
    mov rcx, rax
    mov rdx, 0x1f0
    rep insw

    add r9, 1
    sub r8, 1
    cmp r8, 0
    jnz .loop

    ret


%if ENABLE_VESA
vbe_info_block:
  .signature:      dd 0
  .version:        dw 0
  .oem:            dd 0
  .capabilities:   dd 0
  .video_modes:    dd 0
  .total_memory:   dw 0

; === Space, because some implementations put video mode numbers here ===
times 0x200 db 0

vbe_mode:
  .attributes: dw 0
  times 0x10   db 0
  .width:      dw 0
  .height:     dw 0
  times 0x3    db 0
  .bpp:        db 0
  times 0xe    db 0
  .buffer:     dd 0
%endif

times (bootloader_sectors * 0x200)-($-$$) db 0
