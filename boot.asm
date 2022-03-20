
%define vbs 0x10
%define vbs_str 0x13

%define dbs 0x13
%define dbs_read 0x02

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

    ; === Load the rest of the bootloader ===
    mov ah, dbs_read
    mov al, 1
    mov cl, 2
    mov ch, 0
    mov dh, 0
    mov dl, [.boot_drive]
    mov bx, second_sector
    int dbs

    ; === Switch to Long Mode ===
    mov edi, page_table_address
    jmp SwitchToLongMode
    jmp $

.greeting: db 13, 'Hello, sailor'
.boot_drive: db 0

%include "generated.asm"

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

[bits 64]
long_mode_start:
    call load_kernel

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
    rep movsb

    inc ebx
    jmp .loop

  .end:
    jmp kernel_entry_point

load_kernel:
    mov r8, kernel_sectors
    mov r9, 2
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

times 0x1fe-($-$$) db 0
dw 0xaa55


[bits 16]
second_sector:
  %include "long.asm"

times 0x400-($-$$) db 0
