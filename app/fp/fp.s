 .section .text
    .globl _start
_start:
    lui  x10, 0x3FA00      # Load upper 20 bits of 1.25 (0x3FA00000)
    
    lui  x11, 0x40200      # Load upper 20 bits of 2.50 (0x40200000)
    
    # FADD.S x12, x10, x11  (funct7=0000000, rs2=01011(11), rs1=01010(10), rm=000, rd=01100(12), opcode=1010011)
    .word 0x00B57653

    # Write result to memory for verification
    lui  x13, 0x80000
    sw   x12, 0(x13)
    
   