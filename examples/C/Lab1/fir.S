.globl firt
        #   a0      a1          a2      a3      a4
#void fir(int x[], int c[], int y[], int n, int m)
firt:
    
    sd s0, -8(sp)
    sd s1, -16(sp)

    sub t0, a3, a4  #n-m
    addi t0, t0, 2  #n-m+2
    mv  s1, a4
    addi a4, a4, -1 #m = m-1
    slli a4, a4, 2  #bitwise m = m-1
    li t1, 0        #j = 0


forj:
    bge t1, t0, end_forj    #if j >= n-m+2 return
    li t2, 0        # i = 0

    li s0, 0        #sum = 0

    slli t5, t1, 2          #bitwise j        (bc saved as ints)
    add t5, t5, a4          #bitwise t5 = j + m-1

fori:
    bge t2, s1, end_fori    #if i >= m end for

    #complete multiplication based on current i and j
    slli t4, t2, 2          #bytewise i             (bc saved as ints)
    
    add t3, a1, t4          #address = i + c*
    lw t6, 0(t3)            #c[i]

    sub t4, t5, t4          #bitwise j + m-1 -i
    add t4, t4, a0          #x* + j + m-1 -i

    lw t4, 0(t4)            #x[j + m-1 -i]
    
    mul t4, t4, t6          #long long res = (long long)a * (long long)b;

    slli t4, t4, 1
    srai t4, t4, 32         #int result = (int)(res >> 31);  

    #add result to sum
    add s0, s0, t4

    addi t2, t2, 1          #i++
    j fori

end_fori:
    sub t5, t5, a4          #bitwise j
    add t5, t5, a2          #y* + j

    sw s0, 0(t5)            #y[j] = sum

    addi t1, t1, 1          #j++
    j forj

    
end_forj:


    ld s0, -8(sp)
    ld s1, -16(sp)

    ret 


