rvtest_entry_point:

    # set up trap trap_handler
    la t0, trap_handler # address of trap trap_handler
    csrw mtvec, t0      # mtvec = pointer to trap handler
    la t0, trapstack    # address of trap stack
    csrw mscratch, t0   # mscratch = pointer to trap stack

    la t0, a0  # get address to make a load
    lw a0, 3(t0)        # misaligned load will invoke trap handler

    ret



trap_handler:   
    # save registers
    addi sp, sp, -72
    sw ra, 68(sp)
    sw t0, 64(sp)
    sw t1, 60(sp)
    sw t2, 56(sp)
    sw t3, 52(sp)
    sw t4, 48(sp)
    sw t5, 44(sp)
    sw t6, 40(sp)
    #save s registers
    sd s0, 32(sp)
    sd s1, 24(sp)
    sd s2, 16(sp)
    sd s3, 8(sp)
    sd s4, 0(sp)

    #save current mstatus
    csrr t0, mstatus
    #disable mstatus mie
    li t1, 0x00000008
    and t0, t0, t1
    #set mstatus to new value
    csrw mstatus, t0

    # get the cause of the trap
    csrr t0, mcause
    # check if it was a load access fault
    li t1, 5
    bne t0, t1, not_load_fault

    # get the address that caused the fault
    csrr t0, mtval

    #get address %4 for an arbirtray off axis load
    li t1, 0x00000003
    and t3, t0, t1
    
    #get the on byte address of the above and below memory segments
    sub s1, t0, t3 #calculate the below memory segment
    li t1, 0x04
    sub t2, t1, t3 #calculate the above memory segment byte offset
    add s2, t0, t2  #calculate the above memory segment

    #load the below memory segment
    lw s3, 0(s1)
    #load the above memory segment
    lw s4, 0(s2)

    #combine the two memory segments
    muli t2, t2, 8
    muli t3, t3, 8

    sll s4, s4, t2
    srli s3, s3, t3
    or s3, s3, s4

    #set value to be returned by the trap to allow program to access correct memory
    csrw mepc, s3

    #return s register values
    ld s0, 32(sp)
    ld s1, 24(sp)
    ld s2, 16(sp)
    ld s3, 8(sp)
    ld s4, 0(sp)

    #return all registers to original value and mret
    lw ra, 68(sp)
    lw t0, 64(sp)
    lw t1, 60(sp)
    lw t2, 56(sp)
    lw t3, 52(sp)
    lw t4, 48(sp)
    lw t5, 44(sp)
    lw t6, 40(sp)
    addi sp, sp, 72
    mret    

not_load_fault:
    # handle other faults here
    j self_loop

destination:
    .dword 0x0123456789ABCDEF   # fill destination with some stuff

trapstack:
    .fill 32, 4             # room to save registers

