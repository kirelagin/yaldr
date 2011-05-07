; CPU mode switching
; asmsyntax=nasm

section .text

; This function returns manually
; Interrupts will be disabled
global switch_to_protected
switch_to_protected:
    mov ebx, [esp]
    cli
    lgdt [gdtr]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    ; We are in the protected mode now
    mov cx, 0x8
    mov ds, cx
    mov es, cx
    mov fs, cx
    mov gs, cx
    mov ss, cx
    jmp 0x10:ebx


global switch_to_unreal
switch_to_unreal:
    push ds
    push es
    push fs
    push gs
    mov bx, ss
    cli
    lgdt [gdtr]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    ; We are in the protected mode now
    ; Load segments
    mov cx, 0x8
    mov ds, cx
    mov es, cx
    mov fs, cx
    mov gs, cx
    mov ss, cx
    ; Disable protected mode
    and al, 0xFE
    mov cr0, eax
    mov ss, bx
    pop gs
    pop fs
    pop es
    pop ds
    sti
    ret

section .data
gdtr:
    dw gdt.end - $ + 1
    dd gdt
gdt:
    ; NULL entry (also the descriptor)
    dd 0, 0
    ; FLAT DATA entry
    db 0xff, 0xff, 0, 0, 0, 10010010b, 11001111b, 0
    ; FLAT CODE entry
    db 0xff, 0xff, 0, 0, 0, 10011010b, 11001111b, 0
.end: