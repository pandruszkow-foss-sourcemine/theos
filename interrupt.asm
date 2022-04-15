
section .text

[bits 64]
extern handle_interrupt

%macro push_all 0
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
%endmacro

%macro pop_all 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
%endmacro

global interrupt_wrapper
align 8
interrupt_wrapper:
    cli
    push rax
    ; === Read status register C ===
    mov al, 0x0c
    out 0x70, al
    in al, 0x71

    call handle_interrupt

    ; === Send EOI ===
    mov al, 0x20
    out 0xa0, al
    out 0x20, al

    pop rax
    iretq
