// cache_test.S — processor-level exercise of the Lynn data cache.
// Lynn cache-development exercise.
//
// Self-checking. Writes 1 to tohost on success, or 2*code+1 on the first
// failing check. Exercises: store-then-load, repeated (hit) loads, sequential
// loads within a line, conflict eviction, byte/halfword stores preserving
// neighbouring bytes, a load-miss immediately followed by a dependent op
// (backpressure correctness), and an uncached timer read.
//
// Runs identically on the baseline (uncached) and cache cores — it checks
// architectural results, which must match regardless of caching.

    .section .text.init
    .globl rvtest_entry_point
    .type  rvtest_entry_point, @function

// Scratch data region: well past the program image, zero-initialised memory.
// s0 = base of scratch.  Conflict stride = NUM_LINES*LINE_BYTES = 1024 = 0x400.
#define SCRATCH 0x80080000
#define CONFLICT_STRIDE 0x400
#define MTIME 0x0200bff8

rvtest_entry_point:
    li   sp, 0
    li   gp, 0
    li   s0, SCRATCH

    // ---- Check 1: store word, load it back (store-then-load) ----
    li   t0, 0xdeadbeef
    sw   t0, 0(s0)
    lw   t1, 0(s0)
    li   gp, 1
    bne  t1, t0, fail

    // ---- Check 2: repeated load = hit, same value ----
    lw   t1, 0(s0)
    lw   t2, 0(s0)
    li   gp, 2
    bne  t1, t2, fail
    bne  t1, t0, fail

    // ---- Check 3: sequential words within the same line ----
    li   t0, 0x11111111
    li   t1, 0x22222222
    li   t2, 0x33333333
    li   t3, 0x44444444
    sw   t0, 0(s0)
    sw   t1, 4(s0)
    sw   t2, 8(s0)
    sw   t3, 12(s0)
    lw   t4, 0(s0)
    li   gp, 3
    bne  t4, t0, fail
    lw   t4, 4(s0)
    bne  t4, t1, fail
    lw   t4, 8(s0)
    bne  t4, t2, fail
    lw   t4, 12(s0)
    bne  t4, t3, fail

    // ---- Check 4: conflict eviction then re-fetch of original ----
    li   t5, CONFLICT_STRIDE
    add  s1, s0, t5              // s1 maps to same index, different tag
    li   t0, 0xcafef00d
    sw   t0, 0(s1)              // fill conflicting line (write-through)
    lw   t1, 0(s1)
    li   gp, 4
    bne  t1, t0, fail
    lw   t1, 0(s0)             // original line: value must still be correct
    li   t2, 0x11111111
    bne  t1, t2, fail

    // ---- Check 5: byte store preserves neighbouring bytes ----
    li   t0, 0xaabbccdd
    sw   t0, 32(s0)
    li   t1, 0x99
    sb   t1, 33(s0)            // overwrite byte 1 only
    lw   t2, 32(s0)
    li   t3, 0xaabb99dd
    li   gp, 5
    bne  t2, t3, fail

    // ---- Check 6: halfword store preserves the other halfword ----
    li   t0, 0x12345678
    sw   t0, 48(s0)
    li   t1, 0xbeef
    sh   t1, 48(s0)           // overwrite low halfword
    lw   t2, 48(s0)
    li   t3, 0x1234beef
    li   gp, 6
    bne  t2, t3, fail

    // ---- Check 7: load-miss immediately feeding a dependent op ----
    // Force a fresh miss on a new line, then use the value right away.
    li   t5, 0x1000
    add  s2, s0, t5
    li   t0, 0x00000007
    sw   t0, 0(s2)            // establish value
    // evict by touching a conflicting line
    li   t5, CONFLICT_STRIDE
    add  s3, s2, t5
    sw   x0, 0(s3)
    // now reload s2 (miss) and immediately add
    lw   t1, 0(s2)
    addi t2, t1, 3            // dependent use in the very next instruction
    li   t3, 10
    li   gp, 7
    bne  t2, t3, fail

    // ---- Check 8: uncached timer read must not hang or corrupt ----
    li   t0, MTIME
    lw   t1, 0(t0)           // reads cycle counter; just must complete
    lw   t2, 0(t0)
    li   gp, 8
    // second read should be >= first (monotonic); tolerate equal
    bltu t2, t1, fail

    // all checks passed
    li   gp, 1
    j    finish

fail:
    // encode failure code: tohost = 2*gp + 1
    add  gp, gp, gp
    addi gp, gp, 1
    j    finish

finish:
    la   t0, tohost          // reference the symbol so --gc-sections keeps it
    sw   gp, 0(t0)
    sw   x0, 4(t0)
1:  j    1b

    .section .tohost,"aw",@progbits
    .balign 4
    .globl tohost
tohost:
    .dword 0
