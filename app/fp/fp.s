.section .text
.globl main

main:
    # x10 = 1.0f (0x3f800000)
    lui   x10, 0x3f800

    # x11 = 2.0f (0x40000000)
    lui   x11, 0x40000

    # Move integer bit patterns to FP registers
    fmv.w.x  ft0, x10      # ft0 = 1.0
    fmv.w.x  ft1, x11      # ft1 = 2.0

    # Floating point add
    # fadd.s   ft2, ft0, ft1 # ft2 = 3.0
    fmul.s   ft2, ft0, ft1
    ret