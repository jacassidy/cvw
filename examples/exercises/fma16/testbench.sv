/* verilator lint_off STMTDLY */
`include "fmaUtils.svh"

module testbench_fma16;
  logic        clk, reset;
  logic [15:0] x, y, z, rexpected, result;
  logic [7:0]  ctrl;
  logic        mul, add, negp, negz;
  logic [1:0]  roundmode;
  logic [31:0] vectornum, errors;
  logic [75:0] testvectors[1000000:0];
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
      // $readmemh("tests/fma_special_rz.tv", testvectors);
      // $readmemh("tests/fma_special_rm.tv", testvectors);
      // $readmemh("tests/fma_special_rne.tv", testvectors);
      // $readmemh("tests/fma_special_rp.tv", testvectors);
      // $readmemh("tests/baby_torture.tv", testvectors);
      // $readmemh("tests/torture.tv", testvectors);
      $readmemh("tests/fma_1.tv", testvectors);
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
      if (result[15:0] !== rexpected[15:0] | flags[3:0] !== flagsexpected[3:0]) begin  // check result
        CorrectResult = 1'b1;

        `ifdef DEBUG
        $display("\n\n\nInternalSignals");
        $display("Exponent A \t\t%b, (%d)", dut.OpAExponent, dut.OpAExponent);
        $display("Exponent B \t\t%b, (%d)", dut.OpBExponent, dut.OpBExponent);
        $display("Mantisa A \t\t %b", dut.OpAMantisa);
        $display("Mantisa B \t\t %b", dut.OpBMantisa);
        $display("Sign A \t\t %b", dut.OpASign);
        $display("Sign B \t\t %b", dut.OpBSign);
        $display("");
        $display("MulResultExponent \t%b, (%d)", dut.MultiplicationResultExponent, signed'(dut.MultiplicationResultExponent));
        $display("MulResultMantisa \t%b", dut.MultiplicationResultMantisa);
        $display("MulResultSign \t%b", dut.MultiplicationResultSign);
        $display("MulResultInf \t\t%b", dut.MultiplicationExponentOverflow);
        $display("MulInpZero \t\t%b", dut.MultiplcationInputZero);
        $display("");
        $display("Exponent C \t\t%b, (%d)", dut.OpCExponent, dut.OpCExponent);
        $display("Mantisa C \t\t %b", dut.OpCMantisa);
        $display("Sign C \t\t %b", dut.OpCSign);
        $display("");
        $display("Exponent Diff \t%b, (%d)", dut.Accumulator.AccumulateExponentDiff, dut.Accumulator.AccumulateExponentDiff);
        $display("Preshift Exponent \t%b, (%d)", dut.AccumulateResultExponent, dut.AccumulateResultExponent);
        $display("");
        $display("OpCExponentGreater \t %b", dut.Accumulator.OpCExponentGreater);
        $display("MultiplicationExponentNegative \t %b", dut.MultiplicationExponentNegative);
        $display("OpAShiftAmt (Int)\t%b, (%d)", dut.Accumulator.AccumulateOpAShiftAmt, dut.Accumulator.AccumulateOpAShiftAmt);
        $display("OpBShiftAmt (C)\t%b, (%d)", dut.Accumulator.AccumulateOpBShiftAmt, dut.Accumulator.AccumulateOpBShiftAmt);
        $display("");
        if (dut.Accumulator.SelectAccumulateInvertedMantisa) begin
          $display("AccumulateOpA Inv (Int) \t %b %b", ~dut.Accumulator.AccumulateOperandA, ~dut.Accumulator.StickyA);
          $display("AccumulateOpB (C) \t\t %b %b", dut.Accumulator.AccumulateOperandB, dut.Accumulator.StickyB);
          $display("CarryInForSubtract\t\t %b %b", {22'b0}, dut.Accumulator.AccumulateSignMismatch);
          $display("");
          $display("AccumulateInvertedMantisa \t%b", dut.Accumulator.AccumulateInvertedMantisa);
        end else begin
          $display("AccumulateOpA (Int) \t\t %b %b", dut.Accumulator.AccumulateOperandA, dut.Accumulator.StickyA);
          $display("AccumulateOpB Inv \t\t %b %b", dut.Accumulator.SelectivelyInvertedAccumulateOpB[22:1], dut.Accumulator.SelectivelyInvertedAccumulateOpB[0]);
          $display("CarryInForSubtract\t\t %b %b", {22'b0}, dut.Accumulator.AccumulateSignMismatch);
          $display("");
          $display("AccumulateStandardMantisa \t%b", dut.Accumulator.AccumulateStandardMantisa);
        end
        $display("Select Invterted \t%b", dut.Accumulator.SelectAccumulateInvertedMantisa);
        $display("AccumulateResult \t%b", dut.AccumulateResultMantisa);
        $display("FinalLeftShiftAmt \t%b (%d)", dut.NormalizationShifter.ShiftAmt, dut.NormalizationShifter.ShiftAmt);
        $display("");
        $display("Accumulate Result Sign \t%b", dut.AccumulateResultSign);
        $display("");
        $display("Multiplication Oflw \t%b", dut.MultiplicationExponentOverflow);
        $display("Normalization Oflw \t%b", dut.NormalizationOverflow);
        $display("");
        $display("Rounding Mode RN \t%b", dut.Rounder.RN);
        $display("Rounding Mode RNE \t%b", dut.Rounder.RNE);
        $display("Rounding Mode RZ \t%b", dut.Rounder.RZ);
        $display("Rounding Mode RP \t%b", dut.Rounder.RP);
        $display("");
        $display("LeastSigBit \t\t%b", dut.Rounder.LeastSigBit);
        $display("GuardBit \t\t%b", dut.Rounder.GuardBit);
        $display("RoundBit | StickyBit \t%b", dut.Rounder.RoundBit | dut.Rounder.StickyBit);
        $display("");
        $display("Round Up \t\t%b", dut.Rounder.RoundUp);
        $display("");
        $display("Exp Increase Amt\t\t%d", signed'(-(dut.NormalizationShifter.ShiftAmt - 2)));
        $display("");
        $display("Result Exponent \t%b, (%d)", result[14:10], result[14:10]);
        $display("True Exponent \t%b, (%d)", rexpected[14:10], rexpected[14:10]);
        $display("");
        $display("ResultMantisa \t%b", result[9:0]);
        $display("TrueResultMantisa \t%b", rexpected[9:0]);
        $display("");
        $display("Arithmatic Invalid \t%b", dut.ArithmaticInvalid);
        $display("Special Case \t\t%0s", dut.SpecialCaseHandler.SpecialCase);
        $display("");
        $display("GuardBit \t\t%b", dut.Rounder.GuardBit);
        $display("RoundBit \t\t%b", dut.Rounder.RoundBit);
        $display("StickyBit \t\t%b", dut.Rounder.StickyBit);
        $display("StickyA \t\t%b", dut.Rounder.StickyA);
        $display("StickyB \t\t%b", dut.Rounder.StickyB);
        $display("\n\n\n");
        `endif

        $display("%h", testvectors[vectornum]);
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
