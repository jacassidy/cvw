/* verilator lint_off STMTDLY */
// `define DEBUG

module testbench_fma16;
  logic        clk, reset;
  logic [15:0] x, y, z, rexpected, result;
  logic [7:0]  ctrl;
  logic        mul, add, negp, negz;
  logic [1:0]  roundmode;
  logic [31:0] vectornum, errors;
  logic [75:0] testvectors[10000:0];
  logic [3:0]  flags, flagsexpected; // Invalid, Overflow, Underflow, Inexact

  logic CorrectResult;

  // instantiate device under test
  fma16 dut(x, y, z, mul, add, negp, negz, roundmode, result, flags);

  // generate clock
  always 
    begin
      clk = 1; #5; clk = 0; #5;
    end

  // at start of test, load vectors and pulse reset
  initial
    begin
      
      // $readmemh("tests/single.tv", testvectors);
      $readmemh("work/fadd_2.tv", testvectors);
      vectornum = 0; errors = 0;
      reset = 1; #22; reset = 0;
    end

  // apply test vectors on rising edge of clk
  always @(posedge clk)
    begin
      #1; {x, y, z, ctrl, rexpected, flagsexpected} = testvectors[vectornum];
      {roundmode, mul, add, negp, negz} = ctrl[5:0];

    end

  // check results on falling edge of clk
  always @(negedge clk)
    if (~reset) begin // skip during reset
      if (result !== rexpected /* | flags !== flagsexpected */) begin  // check result
        CorrectResult = 1'b1;

        `ifdef DEBUG
        $display("\n\n\nInternalSignals");
        $display("Exponent A \t\t%b, (%d)", dut.OpAExponent, dut.OpAExponent);
        $display("Exponent C \t\t%b, (%d)", dut.OpCExponent, dut.OpCExponent);
        $display("");
        $display("IntermMulExponent \t%b, (%d)", dut.IntermendiateResultExponent, dut.IntermendiateResultExponent);
        $display("ExpResult Exponent \t%b, (%d)", dut.ExpectedFinalExponent, dut.ExpectedFinalExponent);
        $display("Result Exponent \t%b, (%d)", result[14:10], result[14:10]);
        $display("");
        $display("Mantisa A \t\t %b", dut.OpAMantisa);
        $display("Mantisa C \t\t %b", dut.OpCMantisa);
        $display("IntermMulMantisa \t%b", dut.IntermediateMultiplicationResultMantisa);
        $display("");
        $display("OpAShiftAmt \t\t%b", dut.AccumulateOpAShiftAmt);
        $display("OpAShiftAmt \t\t%b", dut.AccumulateOpBShiftAmt);
        $display("");
        $display("AccumulateOpA \t %b", dut.AccumulateOperandA);
        $display("AccumulateOpB \t %b", dut.AccumulateOperandB);
        $display("AccumulateResult \t%b", dut.AccumulateResultMantisa);
        $display("");
        $display("CalcResultMantisa \t%b", result[9:0]);
        $display("TrueResultMantisa \t%b", rexpected[9:0]);

        // $display("ResultExp \t\t%b");
        // $display("ExpectedExp \t\t%b", );
        $display("\n\n\n");
        $display("%h", testvectors[vectornum]);
        `endif
        $display("//Error: inputs %h * %h + %h", x, y, z);
        $display("//  result = %h (%h expected) flags = %b (%b expected)\n", 
          result, rexpected, flags, flagsexpected);
        errors = errors + 1;
        
        $display("Result sign: %b \t Exponent %d, Mantisa %b", result[15], result[14:10], result[9:0]);
        $display("Expect sign: %b \t Exponent %d, Mantisa %b", rexpected[15], rexpected[14:10], rexpected[9:0]);

      end else begin
        CorrectResult = 1'bx;
      end
      vectornum = vectornum + 1;
      if (testvectors[vectornum] === 'x) begin 
        $display("%d tests completed with %d errors", 
	           vectornum, errors);
        $stop;
      end
    end
endmodule
