.section .text
    .globl _start
_start:
    # Load initial values
    lui  x10, 0x3fa00      # x10 = 1.25 (0x3fa00000)
    lui  x11, 0x40200      # x11 = 2.5  (0x40200000)
    lui  x12, 0x40000      # x12 = 2.0  (0x40000000)
    lui  x13, 0x3f800      # x13 = 1.0  (0x3f800000)
    
    # FADD.S #1:
    .word 0x00B50553
    
    # FADD.S #2:
    .word 0x00D605D3
    
    # FADD.S #3:
    .word 0x00B50653
    
    # FADD.S #4:
    .word 0x00A606D3
    
    # FADD.S #5:
    .word 0x00B68553
    
    # FSUB.S #1: 
    .word 0x08C505D3
    
    # FSUB.S #2: 
    .word 0x08D58653
    
    # FSUB.S #3: 
    .word 0x08B506D3
    
    # FSUB.S #4: 
    .word 0x08D60553
    
    # FSUB.S #5: 
    .word 0x08A685D3
    
    # Store final results to memory for verification
    lui  x14, 0x80000
    sw   x10, 0(x14)
    sw   x11, 4(x14)
    sw   x12, 8(x14)
    sw   x13, 12(x14)
