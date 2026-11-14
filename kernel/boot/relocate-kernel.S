/* SPDX-License-Identifier: MIT
 *
 * Boot shim for the stock Amazon Fire HD 8 (2017, "douglas") bootloader.
 *
 * The stock LK decompresses the kernel to 0x40080000 and jumps there. Modern arm64
 * Images use text_offset=0 and need a 2 MiB aligned base, so this 4 KiB prefix
 * copies the Image (which follows it) to 0x40200000, cleans it to the point of
 * coherency, and enters it with x0 = FDT and x1-x3 = 0 as the arm64 boot protocol
 * requires.
 *
 * IMAGE_BYTES and IMAGE_MEMORY_BYTES are supplied by mkboot.py.
 */
.section .text, "ax"
.global _start
_start:
    b relocate
    nop
    .quad 0x80000
    .quad IMAGE_MEMORY_BYTES + 4096
    .quad 0xa
    .quad 0
    .quad 0
    .quad 0
    .ascii "ARM\x64"
    .long 0

relocate:
    // Copy backwards: the destination overlaps the end of the source.
    adr x1, payload
    mov x2, #0x40200000
    ldr x3, =((IMAGE_BYTES + 7) & -8)
    add x1, x1, x3
    add x4, x2, x3
1:
    sub x1, x1, #8
    sub x4, x4, #8
    ldr x5, [x1]
    str x5, [x4]
    subs x3, x3, #8
    b.ne 1b

    // Clean the relocated instructions to PoC before invalidating the I-cache.
    // This also covers firmware that leaves the data cache enabled.
    mov x9, #0x40200000
    ldr x10, =((IMAGE_BYTES + 63) & -64)
2:
    dc cvac, x9
    add x9, x9, #64
    subs x10, x10, #64
    b.ne 2b
    dsb sy
    ic iallu
    dsb sy
    isb

    mov x6, x2
    mov x1, xzr
    mov x2, xzr
    mov x3, xzr
    br x6
    .ltorg
    .balign 4096
payload:
