.section .text
    .globl _start

_start:
    # x10 = 1.0f  (0x3f800000)
    # x11 = 2.0f  (0x40000000)

    lui   x10, 0x3f800
    lui   x11, 0x40000

    # Move integer bits to FP registers
    # f0 = 1.0
    # f1 = 2.0

    fmv.w.x  ft0, x10
    fmv.w.x  ft1, x11

    # f2 = f0 + f1  (should be 3.0)

    fadd.s   ft2, ft0, ft1

    # Convert float result -> integer
    # x12 = 3

    fcvt.w.s x12, ft2

    # Store result to memory at 0x80000000

    lui   x14, 0x80000
    sw    x12, 0(x14)
    