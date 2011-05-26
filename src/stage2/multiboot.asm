; Multiboot spec-related routines
; asmsyntax=nasm

%include "asm/main.inc"
%include "asm/output.inc"
%include "asm/mem.inc"
%include "asm/mem_private.inc"
%include "asm/elf32.inc"
%include "asm/ext2fs.inc"

BITS 16

MULTIBOOT_MAGIC equ 0x1BADB002

struc mb_hdr_t
    .magic resd 1              ; MULTIBOOT_MAGIC
    .flags resd 1              ; load options
                                   ; bit 0: align modules (req)
                                   ; bit 1: get meminfo (req)
                                   ; bit 2: get video modes (req)
                                   ; bit 16: override image load address (opt/rec)
    .checksum resd 1           ; 0 - .magic - .flags
    .header_addr resd 1        ; [16] physaddr of the header 
    .load_addr resd 1          ; [16] physaddr of the image start
    .load_end_addr resd 1      ; [16] physaddr of the image end, 0 => load whole image
    .bss_end_addr resd 1       ; [16] physaddr of bss (to fill) end, 0 => no bss
    .entry_addr resd 1         ; [16] physaddr of an entry point
    .mode_type resd 1          ; [2] rec video mode: 1 - graphic, 0 - text
    .width resd 1              ; [2] rec screen width, 0 => no preference
    .heigth resd 1             ; [2] rec screen height, 0 => no preference
    .depth resd 1              ; [2] rec screen bpp, 0 => no preference, or text mode
endstruc

struc mb_info_t
    .flags resd 1
    .mem_upper resd 1          ; [0]
    .mem_lower resd 1          ; [0]
    .boot_device resd 1        ; [1]
    .cmdline resd 1            ; [2]
    .mods_count resd 1         ; [3]
    .mods_addr resd 1          ; [3]
    .syms resd 4               ; [4, 5]
    .mmap_length resd 1        ; [6]
    .mmap_addr resd 1          ; [6]
    .drives_length resd 1      ; [7]
    .drives_addr resd 1        ; [7]
    .config_table resd 1       ; [8]
    .boot_loader_name resd 1   ; [9]
    .apm_table resd 1          ; [10]
    .vbe_control_info resd 1   ; [11]
    .vbe_mode_info resd 1      ; [11]
    .vbe_mode resw 1           ; [11]
    .vbe_iface_seg resd 1      ; [11]
    .vbe_iface_off resd 1      ; [11]
    .vbe_iface_len resd 1      ; [11]
endstruc

struc mb_aout_syms_t
    .tabsize resd 1
    .strsize resd 1
    .addr resd 1
    resd 1
endstruc

struc mb_elf_syms_t
    .num resd 1
    .size resd 1
    .addr resd 1
    .shndx resd 1
endstruc

section .text

MULTIBOOT_SEARCH_END equ 8192

; Load the kernel from the specified file handle
; Argument: file :: opaque_ptr - file handle
; Return value: the kernel entry point, or 0 in case of failure
global load_kernel
load_kernel:
    push bp
    mov bp, sp
    sub sp, 20
%define file bp + 4
%define file_header ebp - 4
%define read_size ebp - 8
%define header ebp - 12
%define mbinfo ebp - 16
%define entry ebp - 20
    mov dword [entry], 0
    push dword MULTIBOOT_SEARCH_END
    call malloc
    mov [file_header], eax
    push dword MULTIBOOT_SEARCH_END
    push dword 0
    push dword [file_header]
    push dword [file]
    call ext2_readfile
    mov [read_size], eax
    xor ecx, ecx
    sub eax, mb_hdr_t_size - 1 ; not searching past buffer end
    cmp ecx, eax
    je .hdr_notfound
    .l1:
        cmp dword [file_header + ecx], MULTIBOOT_MAGIC
        jne .continue
            mov ebx, MULTIBOOT_MAGIC
            add ebx, dword [file_header + ecx + mb_hdr_t.flags]
            add ebx, dword [file_header + ecx + mb_hdr_t.checksum]
            test ebx, ebx
            jz .hdr_found
    .continue:
        add ecx, 4
        cmp ecx, eax
        jb .l1
.hdr_notfound:
    printline "No multiboot header found in the image file"
    jmp .epilogue
.hdr_found:
    ; ecx == hdr offset
    lea ecx, [file_header + ecx]
    mov [header], ecx
    push dword mb_info_t_size
    call malloc
    mov [mbinfo], eax
    mov dword [eax + mb_info_t.flags], 0
    ; bit 0 is "supported" because we do not support modules
    bt dword [header + mb_hdr_t.flags], 1
    jnz .l2
        push dword [mbinfo]
        call prepare_meminfo
        add sp, 4
    .l2:
    bt dword [header + mb_hdr_t.flags], 2
    jnz .l3
        printline "Getting video modes is unsupported, cannot load kernel"
        jmp .epilogue        
    .l3:
    bt dword [header + mb_hdr_t.flags], 16
    jnz .l4
        ; loading manually
        mov ebx, [header]
        sub ebx, [file_header]
        sub ebx, [header + mb_hdr_t.header_addr]
        mov ecx, [header + mb_hdr_t.load_addr]
        add ebx, ecx
        mov edx, [header + mb_hdr_t.load_end_addr]
        test edx, edx
        jnz .fixed_size
            push dword [file]
            call ext2_getfilesize
            add sp, 4
            sub eax, ebx
            mov edx, eax
        .fixed_size:
        mov eax, [header + mb_hdr_t.bss_end_addr]
        test eax, eax
        cmovz eax, edx
        push eax               ; memsz
        push edx               ; filesz
        push ecx               ; addr
        push ebx               ; offset
        push dword [file]      ; file
        call load_chunk
        add sp, 20
        test eax, eax
        jnz .epilogue
        mov eax, [header + mb_hdr_t.entry_addr]
        mov [entry], eax
        jmp .loaded
    .l4:
    ; loading ELF
    push dword [read_size]
    push dword [file_header]
    push dword [file]
    call load_elf32
    add sp, 12
    mov [entry], eax
.loaded:
    
.epilogue:
    mov eax, [entry]
    mov sp, bp
    pop bp
    ret

prepare_meminfo:
    ret

; Loads some data from disk, maybe zeroing some data after it.
; Argument: file :: opaque_ptr - file handle
; Argument: offset :: uint32_t - file offset
; Argument: addr :: ptr - memory address to load to
; Argument: filesz :: uint32_t - size to load
; Argument: memsz :: uint32_t - full chunk size (to zero the rest)
; Return value: 0 in case of a success
global load_chunk
load_chunk:
    push bp
    mov bp, sp
%define file ebp + 4
%define offset ebp + 8
%define addr ebp + 12
%define filesz ebp + 16
%define memsz ebp + 20
    cmp dword [addr], HIGH_MEMORY_START
    jae .l2
        printline "Cannot load kernel into low memory"
        mov eax, -1
        jmp .epilogue        
    .l2:
    push dword [filesz]
    push dword [offset]
    push dword [addr]
    push dword [file]
    call ext2_readfile
    add sp, 16
    cmp eax, dword [filesz]
    je .l1
        printline "Chunk read failure"
        mov eax, -1
        jmp .epilogue
    .l1:
    mov ecx, [memsz]
    sub ecx, eax
    push ecx
    push dword 0
    add eax, [addr]
    push eax
    call memset
    add sp, 12
    xor eax, eax
.epilogue:
    mov sp, bp
    pop bp
    ret

section .data
