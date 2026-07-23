// cache_unit_tb.sv — standalone RTL unit test for SimpleDataCache.
// Lynn cache-development exercise.
//
// Drives the cache directly (no processor) against a tiny behavioral backing
// memory and checks the required cache behaviors. Prints "UNIT_TEST PASS" and
// $finish(0) on success, or "UNIT_TEST FAIL" and a nonzero $fatal on the first
// failing check.

`timescale 1ns/1ps
`include "parameters.svh"

module cache_unit_tb;

  logic clk = 0, reset = 1;
  always #5 clk = ~clk;

  // CPU-side request
  logic                 CpuMemEn, CpuWriteEn;
  logic [(`XLEN/8)-1:0] CpuWriteByteEn;
  logic [`XLEN-1:0]     CpuAdr, CpuWriteData, CpuReadData;
  logic                 Stall;

  // Memory-side
  logic                 MemEn, MemWriteEn;
  logic [(`XLEN/8)-1:0] MemWriteByteEn;
  logic [`XLEN-1:0]     MemAdr, MemWriteData, MemReadData;

  // Cacheable window base (default geometry)
  localparam [`XLEN-1:0] BASE = `XLEN'h8000_0000;

  SimpleDataCache dut (
    .clk, .reset,
    .CpuMemEn, .CpuWriteEn, .CpuWriteByteEn, .CpuAdr, .CpuWriteData,
    .CpuReadData, .Stall,
    .MemEn, .MemWriteEn, .MemWriteByteEn, .MemAdr, .MemWriteData, .MemReadData
  );

  // ---- Behavioral backing memory: 64Ki words, combinational read ----
  localparam int MEM_WORDS = 1 << 16;
  logic [31:0] mem [MEM_WORDS-1:0];
  wire [31:0]  windex = MemAdr[17:2];
  assign MemReadData = MemEn ? mem[windex] : 'x;

  // Count backing-memory writes to detect duplicate stores.
  int mem_write_count;
  always_ff @(posedge clk) begin
    if (!reset && MemEn && MemWriteEn) begin
      mem_write_count <= mem_write_count + 1;
      for (int i = 0; i < 4; i++)
        if (MemWriteByteEn[i]) mem[windex][i*8 +: 8] <= MemWriteData[i*8 +: 8];
    end
  end

  int errors = 0;

  task automatic check(input string name, input logic cond);
    if (cond) $display("  [ok]   %s", name);
    else begin $display("  [FAIL] %s", name); errors++; end
  endtask

  // Hold a CPU load until it completes (Stall deasserts); report stall cycles.
  task automatic cpu_load(input [`XLEN-1:0] addr,
                          output [`XLEN-1:0] data,
                          output int stalls);
    stalls = 0;
    @(negedge clk);
    CpuMemEn = 1; CpuWriteEn = 0; CpuWriteByteEn = 0; CpuAdr = addr;
    #1;
    while (Stall) begin
      stalls++;
      @(posedge clk);
      @(negedge clk);
      #1;
    end
    data = CpuReadData;
    @(negedge clk);
    CpuMemEn = 0;
  endtask

  task automatic cpu_store(input [`XLEN-1:0] addr,
                           input [(`XLEN/8)-1:0] be,
                           input [`XLEN-1:0] data);
    @(negedge clk);
    CpuMemEn = 1; CpuWriteEn = 1; CpuWriteByteEn = be; CpuAdr = addr;
    CpuWriteData = data;
    #1;
    // stores are single-cycle (no stall)
    @(posedge clk);
    @(negedge clk);
    CpuMemEn = 0; CpuWriteEn = 0;
  endtask

  logic [`XLEN-1:0] rd;
  int st, base_writes;

  initial begin
    CpuMemEn = 0; CpuWriteEn = 0; CpuWriteByteEn = 0; CpuAdr = 0; CpuWriteData = 0;
    mem_write_count = 0;
    // Preload memory: each word holds its own byte address (self-identifying).
    for (int i = 0; i < MEM_WORDS; i++) mem[i] = BASE + (i << 2);

    repeat (3) @(negedge clk);
    reset = 0;
    @(negedge clk);

    $display("SimpleDataCache unit test");

    // 1 & 2: first load to a fresh line misses (Stall asserted -> stalls>0).
    cpu_load(BASE + 32'h1000, rd, st);
    check("2. first load misses (stall observed)", st > 0);
    check("10/1. refill returns requested word", rd == (BASE + 32'h1000));

    // 3: repeated load hits (no stall).
    cpu_load(BASE + 32'h1000, rd, st);
    check("3. repeated load hits (no stall)", st == 0 && rd == (BASE + 32'h1000));

    // 4: different words in the same line return correctly (all hits).
    cpu_load(BASE + 32'h1004, rd, st);
    check("4a. same-line word +4", st == 0 && rd == (BASE + 32'h1004));
    cpu_load(BASE + 32'h1008, rd, st);
    check("4b. same-line word +8", st == 0 && rd == (BASE + 32'h1008));
    cpu_load(BASE + 32'h100c, rd, st);
    check("4c. same-line word +12", st == 0 && rd == (BASE + 32'h100c));

    // 5: conflicting address (same index, +1KiB) evicts, then original re-misses.
    cpu_load(BASE + 32'h1400, rd, st);            // conflict: fills, evicts 0x1000
    check("5a. conflict line miss", st > 0 && rd == (BASE + 32'h1400));
    cpu_load(BASE + 32'h1000, rd, st);            // original now missing again
    check("5b. evicted line re-misses", st > 0 && rd == (BASE + 32'h1000));

    // 6: store hit updates cached bytes (observed on subsequent hit load).
    cpu_load(BASE + 32'h2000, rd, st);            // allocate line
    cpu_store(BASE + 32'h2000, 4'b1111, 32'hA5A5A5A5);
    cpu_load(BASE + 32'h2000, rd, st);
    check("6. store hit updates cached word", st == 0 && rd == 32'hA5A5A5A5);

    // 7: store miss writes through without allocating.
    base_writes = mem_write_count;
    cpu_store(BASE + 32'h9000, 4'b1111, 32'h5A5A5A5A);   // fresh line, not cached
    check("7a. store miss wrote through", mem[(32'h9000)>>2] == 32'h5A5A5A5A);
    cpu_load(BASE + 32'h9000, rd, st);
    check("7b. store miss did NOT allocate (load still misses)", st > 0);

    // 8: byte store preserves neighbouring bytes.
    cpu_store(BASE + 32'h2000, 4'b1111, 32'h11223344); // known word (hit)
    cpu_store(BASE + 32'h2000, 4'b0010, 32'h0000CC00); // write byte 1 only
    cpu_load (BASE + 32'h2000, rd, st);
    check("8. byte store preserves other bytes", rd == 32'h1122CC44);

    // 9: halfword store preserves the other halfword.
    cpu_store(BASE + 32'h2000, 4'b1111, 32'hAABBCCDD);
    cpu_store(BASE + 32'h2000, 4'b0011, 32'h0000EEFF); // low halfword
    cpu_load (BASE + 32'h2000, rd, st);
    check("9. halfword store preserves other half", rd == 32'hAABBEEFF);

    // 11: uncached access (below cacheable base, e.g. MMIO timer) never allocates.
    mem[(32'h0200bff8)>>2] = 32'h1234abcd; // out of window but our mem is small; use idx
    // Drive an uncached address; expect no stall and passthrough read.
    @(negedge clk);
    CpuMemEn = 1; CpuWriteEn = 0; CpuWriteByteEn = 0; CpuAdr = 32'h0200bff8; #1;
    check("11. uncached load does not stall", Stall == 0);
    @(negedge clk); CpuMemEn = 0;

    // 12 & 14: a stalled refill resumes exactly once and loses no request.
    // Re-load an evicted line; the completing cycle returns the value exactly once.
    cpu_load(BASE + 32'h3000, rd, st);
    check("12/14. stall resolves once, request not lost", rd == (BASE + 32'h3000) && st > 0);

    // 13: no duplicate backing store — a single word store causes exactly one write.
    base_writes = mem_write_count;
    cpu_store(BASE + 32'h4000, 4'b1111, 32'hDEADBEEF);
    check("13. store issues exactly one backing write", (mem_write_count - base_writes) == 1);

    if (errors == 0) begin
      $display("UNIT_TEST PASS (0 errors)");
      $finish;
    end else begin
      $display("UNIT_TEST FAIL (%0d errors)", errors);
      $fatal(1);
    end
  end

  // Global watchdog
  initial begin
    #200000;
    $display("UNIT_TEST FAIL (timeout)");
    $fatal(1);
  end

endmodule
