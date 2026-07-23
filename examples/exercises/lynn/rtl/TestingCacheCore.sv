// TestingCacheCore.sv
// Lynn cache-development exercise
//
// Cached counterpart of the baseline TestingCore.sv. Exposes the identical
// Lynn-facing port interface, instantiates the same computeCore, and inserts a
// blocking direct-mapped write-through data cache (SimpleDataCache) between the
// core's data-memory port and Lynn's backing data memory. Instruction fetch is
// left uncached (identical to the baseline).

`include "parameters.svh"

module testingCacheCore(
    input   logic                       clk,
    input   logic                       reset,

    output  logic [`XLEN-1:0]           PC,          // instruction memory target address
    input   logic [31:0]                Instr,       // instruction memory read data

    output  logic [`XLEN-1:0]           IEUAdr,      // data memory target address
    input   logic [`XLEN-1:0]           ReadData,    // data memory read data
    output  logic [`XLEN-1:0]           WriteData,   // data memory write data

    output  logic                       MemEn,
    output  logic                       WriteEn,
    output  logic [`XLEN/8-1:0]         WriteByteEn  // one-hot byte store strobes
  );

    logic [`XLEN-1:0]      InstrAdr;

    // computeCore data-memory port (CPU side of the cache)
    logic                 Core_MemEn, Core_MemWriteEn;
    logic [`XLEN-1:0]     Core_MemWriteData, Core_MemReadData;
    logic [`XLEN-1:0]     Core_MemAdr;
    logic [(`XLEN/8)-1:0] Core_MemWriteByteEn;

    // Cache -> processor backpressure
    logic                 Stall;

    // Instruction fetch (uncached, same as baseline)
    assign PC = InstrAdr;

    computeCore ComputeCore(
        .clk, .reset,
        .External_PC(InstrAdr),
        .External_MemEn(Core_MemEn),
        .External_MemWriteEn(Core_MemWriteEn),
        .External_MemWriteByteEn(Core_MemWriteByteEn),
        .External_MemAdr(Core_MemAdr),
        .External_MemWriteData(Core_MemWriteData),
        .External_Instr(Instr),
        .External_MemReadData(Core_MemReadData),
        .External_MemStall(Stall)
    );

    // The baseline applies the write-enable mask to the byte strobes; do the
    // same here so the cache and backing memory see qualified strobes.
    logic [(`XLEN/8)-1:0] Core_WriteByteEnQualified;
    assign Core_WriteByteEnQualified = Core_MemWriteByteEn & {(`XLEN/8){Core_MemWriteEn}};

    SimpleDataCache DataCache(
        .clk, .reset,

        // CPU side
        .CpuMemEn(Core_MemEn),
        .CpuWriteEn(Core_MemWriteEn),
        .CpuWriteByteEn(Core_WriteByteEnQualified),
        .CpuAdr(Core_MemAdr),
        .CpuWriteData(Core_MemWriteData),
        .CpuReadData(Core_MemReadData),
        .Stall(Stall),

        // Memory side (to Lynn backing data memory)
        .MemEn(MemEn),
        .MemWriteEn(WriteEn),
        .MemWriteByteEn(WriteByteEn),
        .MemAdr(IEUAdr),
        .MemWriteData(WriteData),
        .MemReadData(ReadData)
    );

endmodule
