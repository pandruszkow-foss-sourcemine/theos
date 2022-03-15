
%define vbs 0x10
%define vbs_str 0x13

%define dbs 0x13
%define dbs_read 0x02
%define dbs_ext_read 0x42

[org 0x7c00]
[bits 16]

    jmp 0:start
start:
    mov [.boot_drive], dl

    ; === Segment registers ===
    xor ax, ax
    mov es, ax
    mov ss, ax
    mov ds, ax

    ; === Stack registers ===
    mov bp, start
    mov sp, bp

    ; === Video mode ===
    mov al, 0x3
    int vbs

    ; === Write string ===
    mov ax, .greeting
    call write_string

    ; === Load sectors ===
    call load_kernel

    ; === Switch to Long Mode ===
    mov edi, page_table_address
    jmp SwitchToLongMode

    ; === Wait ===
    jmp $

.greeting: db 12, 'Hello sailor'
.boot_drive: db 0

%include "generated.asm"
%include "long.asm"

[bits 16]
write_string:
    pusha

    ; === Extract count and text ===
    mov bx, ax
    mov cl, [bx]
    inc ax
    mov bp, ax

    ; === New line ===
    mov al, [.line]
    mov dh, al
    inc ax
    mov [.line], al

    xor ax, ax
    mov ah, vbs_str

    mov dl, 0
    mov bh, 0
    mov bl, 0x0f

    int vbs

    popa
    ret

.line: db 0

disk_address_packet:
  .size:        db 10h
  .reserved:    db 0
  .num_sectors: dw 0
  .buffer:      dw 0
  .segment:     dw 0
  .source_lba:  dq 1

load_kernel:
    pusha

    mov word [disk_address_packet.num_sectors], kernel_sectors
    mov word [disk_address_packet.buffer],      kernel_start_address

    ; === Point DS:SI at address packet ===
    xor ax, ax
    mov ds, ax
    mov si, disk_address_packet

    ; === Call BIOS extended read ===
    mov dl, [start.boot_drive]
    mov ah, dbs_ext_read
    mov al, 0

    cld
    int dbs
    popa
    ret

[bits 64]
long_mode_start:
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
    rep stosq

    pop rdi
    pop rax

    ; === Copy ===
    mov ecx, [eax + 12]
    rep movsq

    inc ebx
    jmp .loop

  .end:
    jmp kernel_entry_point
    jmp $

times 0x1fe-($-$$) db 0
dw 0xaa55
