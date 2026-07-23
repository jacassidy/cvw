// SimpleDataCache.sv
// Lynn cache-development exercise
//
// A small, correct, blocking, direct-mapped WRITE-THROUGH / NO-WRITE-ALLOCATE
// data cache that sits between the processor's data-memory port (computeCore
// M-stage) and Lynn's backing data memory (the testbench RAM).
//
// Default geometry (parameterizable):
//   Direct mapped, 1 KiB, 16-byte lines, 4 x 32-bit words/line, 64 lines.
//   Byte/word offset : 4 bits   (addr[3:0])
//   Index            : 6 bits   (addr[9:4])
//   Tag              : upper bits (addr[XLEN-1:10])
//
// Read miss  : allocate-on-read-miss, refill whole line (one word/cycle),
//              return originally requested word, stall processor during refill.
// Read hit   : return word combinationally, no backing-memory access, no stall.
// Store      : write-through, no-write-allocate. A store that hits also updates
//              the cached bytes. A store miss updates backing memory only.
// Uncached   : any address outside [CACHEABLE_BASE, CACHEABLE_BASE+CACHEABLE_SIZE)
//              (covers the MMIO timer at 0x0200_BFF8) bypasses the cache: passed
//              straight to backing memory, never allocated, never stalled.
//
// The backing memory in Lynn happens to return read data combinationally, but
// the refill is modeled as an explicit multi-cycle state machine so the miss
// penalty is visible and the design can later drive a realistic memory port.

`include "parameters.svh"

module SimpleDataCache #(
    parameter int LINE_BYTES     = 16,                     // bytes per line
    parameter int NUM_LINES      = 64,                     // number of lines
    parameter [`XLEN-1:0] CACHEABLE_BASE = `XLEN'h8000_0000,
    parameter [`XLEN-1:0] CACHEABLE_SIZE = `XLEN'h0400_0000 // 64 MiB cacheable window
) (
    input  logic                 clk,
    input  logic                 reset,

    // ---- CPU side (from computeCore M stage) ----
    input  logic                 CpuMemEn,        // memory access this cycle
    input  logic                 CpuWriteEn,      // 1 = store, 0 = load
    input  logic [(`XLEN/8)-1:0] CpuWriteByteEn,  // byte strobes (already qualified)
    input  logic [`XLEN-1:0]     CpuAdr,          // word-aligned data address
    input  logic [`XLEN-1:0]     CpuWriteData,    // store data
    output logic [`XLEN-1:0]     CpuReadData,     // load data back to processor
    output logic                 Stall,           // 1 = access not complete, hold core

    // ---- Memory side (to Lynn backing data memory) ----
    output logic                 MemEn,
    output logic                 MemWriteEn,
    output logic [(`XLEN/8)-1:0] MemWriteByteEn,
    output logic [`XLEN-1:0]     MemAdr,
    output logic [`XLEN-1:0]     MemWriteData,
    input  logic [`XLEN-1:0]     MemReadData
);

    // ---- Derived geometry ----
    localparam int WORD_BYTES  = `XLEN/8;                 // 4
    localparam int WORDS_LINE  = LINE_BYTES/WORD_BYTES;   // 4
    localparam int OFFSET_BITS = $clog2(LINE_BYTES);      // 4
    localparam int WOFF_BITS   = $clog2(WORDS_LINE);      // 2 (word-within-line)
    localparam int BOFF_BITS   = $clog2(WORD_BYTES);      // 2 (byte-within-word)
    localparam int INDEX_BITS  = $clog2(NUM_LINES);       // 6
    localparam int TAG_BITS    = `XLEN - INDEX_BITS - OFFSET_BITS;

    // ---- Address decomposition ----
    logic [TAG_BITS-1:0]   tag;
    logic [INDEX_BITS-1:0] index;
    logic [WOFF_BITS-1:0]  word_off;

    assign tag      = CpuAdr[`XLEN-1 -: TAG_BITS];
    assign index    = CpuAdr[OFFSET_BITS +: INDEX_BITS];
    assign word_off = CpuAdr[BOFF_BITS +: WOFF_BITS];

    // ---- Storage ----
    logic                  valid_arr [NUM_LINES-1:0];
    logic [TAG_BITS-1:0]   tag_arr   [NUM_LINES-1:0];
    logic [`XLEN-1:0]      data_arr  [NUM_LINES-1:0][WORDS_LINE-1:0];

    // ---- Classification (combinational) ----
    logic cacheable, is_load, is_store, hit;
    assign cacheable = (CpuAdr >= CACHEABLE_BASE) &&
                       (CpuAdr <  (CACHEABLE_BASE + CACHEABLE_SIZE));
    assign is_load   = CpuMemEn & ~CpuWriteEn;
    assign is_store  = CpuMemEn &  CpuWriteEn;
    assign hit       = valid_arr[index] & (tag_arr[index] == tag);

    // ---- Miss/refill state machine ----
    logic                  busy;         // refill in progress
    logic [WOFF_BITS-1:0]  refill_idx;   // which word we are fetching
    logic [INDEX_BITS-1:0] miss_index;
    logic [TAG_BITS-1:0]   miss_tag;
    logic [`XLEN-1:0]      miss_base;    // line-aligned byte address
    logic [`XLEN-1:0]      refill_buf [WORDS_LINE-1:0];

    logic [`XLEN-1:0]      line_base;
    assign line_base = {CpuAdr[`XLEN-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};

    logic read_miss;
    assign read_miss = is_load & cacheable & ~hit;

    // Stall the core the cycle we detect a read miss, and for the whole refill.
    assign Stall = busy | read_miss;

    // ---- Backing-memory request muxing ----
    always_comb begin
        if (busy) begin
            // Sequentially fetch each word of the missed line.
            MemEn          = 1'b1;
            MemWriteEn     = 1'b0;
            MemWriteByteEn = '0;
            MemAdr         = miss_base + (`XLEN'(refill_idx) << BOFF_BITS);
            MemWriteData   = '0;
        end else begin
            // Normal pass-through of the current CPU request (loads that hit
            // do not actually need the read, but driving it is harmless).
            MemEn          = CpuMemEn;
            MemWriteEn     = CpuWriteEn;     // write-through (both hit and miss)
            MemWriteByteEn = CpuWriteByteEn;
            MemAdr         = CpuAdr;
            MemWriteData   = CpuWriteData;
        end
    end

    // ---- Read-data return to the CPU ----
    always_comb begin
        if (busy) begin
            CpuReadData = 'x;                 // stalled: value not consumed
        end else if (is_load & ~cacheable) begin
            CpuReadData = MemReadData;        // uncached load: straight through
        end else if (is_load & hit) begin
            CpuReadData = data_arr[index][word_off];
        end else begin
            CpuReadData = MemReadData;        // stores / don't-care
        end
    end

    // ---- Sequential state ----
    integer i, w;
    always_ff @(posedge clk) begin
        if (reset) begin
            busy       <= 1'b0;
            refill_idx <= '0;
            for (i = 0; i < NUM_LINES; i++) valid_arr[i] <= 1'b0;
        end else if (!busy) begin
            // Store hit: update the cached bytes of the target word.
            if (is_store & cacheable & hit) begin
                for (i = 0; i < WORD_BYTES; i++)
                    if (CpuWriteByteEn[i])
                        data_arr[index][word_off][i*8 +: 8] <= CpuWriteData[i*8 +: 8];
            end
            // Read miss: begin a refill.
            if (read_miss) begin
                busy       <= 1'b1;
                refill_idx <= '0;
                miss_index <= index;
                miss_tag   <= tag;
                miss_base  <= line_base;
            end
        end else begin
            // Capture the word currently presented by backing memory.
            refill_buf[refill_idx] <= MemReadData;
            if (refill_idx == WOFF_BITS'(WORDS_LINE-1)) begin
                // Install the whole line. The last word is taken from the
                // combinational read (it has not been latched into refill_buf yet).
                for (w = 0; w < WORDS_LINE-1; w++)
                    data_arr[miss_index][w] <= refill_buf[w];
                data_arr[miss_index][WORDS_LINE-1] <= MemReadData;
                tag_arr[miss_index]   <= miss_tag;
                valid_arr[miss_index] <= 1'b1;
                busy                  <= 1'b0;
            end else begin
                refill_idx <= refill_idx + 1'b1;
            end
        end
    end

    // ============================================================
    //  Performance counters + assertions (simulation only).
    //  Excluded from synthesis so they do not inflate area/timing.
    // ============================================================
`ifndef SYNTHESIS
    longint unsigned c_accesses, c_read, c_write;
    longint unsigned c_read_hits, c_read_misses;
    longint unsigned c_store_hits, c_store_misses;
    longint unsigned c_refills, c_refill_cycles, c_stall_cycles, c_uncached;

    initial begin
        c_accesses = 0; c_read = 0; c_write = 0;
        c_read_hits = 0; c_read_misses = 0;
        c_store_hits = 0; c_store_misses = 0;
        c_refills = 0; c_refill_cycles = 0; c_stall_cycles = 0; c_uncached = 0;
    end

    // Count a new CPU access only on cycles where we are not mid-refill and the
    // access is not being replayed because of a stall we already counted.
    logic prev_stall;
    always_ff @(posedge clk) begin
        if (reset) begin
            prev_stall <= 1'b0;
        end else begin
            prev_stall <= Stall;

            if (busy) c_refill_cycles <= c_refill_cycles + 1;
            if (Stall) c_stall_cycles  <= c_stall_cycles + 1;

            // A genuine new access: enable asserted, not currently busy, and the
            // previous cycle was not stalling (so we don't recount the replay).
            if (CpuMemEn & ~busy & ~prev_stall) begin
                c_accesses <= c_accesses + 1;
                if (~cacheable) c_uncached <= c_uncached + 1;
                if (is_load) begin
                    c_read <= c_read + 1;
                    if (~cacheable)      ; // uncached load, already counted
                    else if (hit)        c_read_hits   <= c_read_hits   + 1;
                    else                 c_read_misses  <= c_read_misses + 1;
                end
                if (is_store) begin
                    c_write <= c_write + 1;
                    if (cacheable & hit) c_store_hits   <= c_store_hits   + 1;
                    else                 c_store_misses <= c_store_misses + 1;
                end
                if (read_miss) c_refills <= c_refills + 1;
            end
        end
    end

    // Assertion: never issue more than one backing-memory store per store.
    // (A store lasts exactly one cycle because the PC advances; during a refill
    //  MemWriteEn is forced low.)
    always_ff @(posedge clk) begin
        if (!reset) begin
            if (busy) assert (~MemWriteEn)
                else $error("SimpleDataCache: store issued during refill (duplicate risk)");
            // Illegal state: refill index out of range.
            assert (refill_idx < WORDS_LINE)
                else $error("SimpleDataCache: refill_idx out of range");
        end
    end

    function automatic real hit_rate();
        longint unsigned rd = c_read_hits + c_read_misses;
        if (rd == 0) return 0.0;
        return real'(c_read_hits) / real'(rd);
    endfunction

    final begin
        $display("CACHE_STATS accesses=%0d read=%0d write=%0d read_hits=%0d read_misses=%0d store_hits=%0d store_misses=%0d refills=%0d refill_cycles=%0d stall_cycles=%0d uncached=%0d hit_rate=%0.4f",
            c_accesses, c_read, c_write, c_read_hits, c_read_misses,
            c_store_hits, c_store_misses, c_refills, c_refill_cycles,
            c_stall_cycles, c_uncached, hit_rate());
    end
`endif

endmodule
