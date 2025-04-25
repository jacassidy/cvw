//2/12/25 jkc.cassidy@gmail.com James Kaden Cassidy

//Conducts result = A * B + C

`include "fmaUtils.svh"

module  fma16 (
    input   logic [15:0]    OperandA, 
    input   logic [15:0]    OperandB, 
    input   logic [15:0]    OperandC, 
    input   logic           mul, 
    input   logic           add, 
    input   logic           negp, 
    input   logic           negz, 
    input   logic [1:0]     roundmode, 
    output  logic [15:0]    result, 
    output  logic [3:0]     flags
);

    //Arithmatic Logic
    logic       OpASign,        OpBSign,        OpCSign;
    logic[10:0] OpAMantisa,     OpBMantisa,     OpCMantisa;
    logic[4:0]  OpAExponent,    OpBExponent,    OpCExponent;

    logic       OpANan,         OpBNan,         OpCNan;
    
    logic       MultiplicationResultSign;  
    logic[5:0]  MultiplicationResultExponent, MultiplicationIntermediateExp;
    logic[21:0] MultiplicationResultMantisa;

    logic       AccumulateResultSign;
    logic[4:0]  AccumulateResultExponent;
    logic[23:0] AccumulateResultMantisa;

    logic[4:0]  NormalizedExponent;
    logic[23:0] NormalizedMantisa;

    logic[9:0]  RoundedMantisa;
    
    logic[15:0] AnticipatedResult;

    logic       InexactRound, StickyA, StickyB;

    //Intermodule Signals
    logic       MultiplicationProducedInf;
    logic       ArithmaticInvalid;

    logic       AccumulateSignMismatch;


    ////Convenience Assignments////
    assign OpASign      = OperandA[15];
    assign OpBSign      = mul ? OperandB[15] : 0;    //Set Op B to 1 if not doing multiplication
    assign OpCSign      = add ? OperandC[15] : 0;    //Set Op A to 0 if not doing multiplication

    assign OpAExponent  = OperandA[14:10];
    assign OpBExponent  = mul ? OperandB[14:10] : 5'd15; //Set Op B to 1 if not doing multiplication
    assign OpCExponent  = add ? OperandC[14:10] : 5'b0;  //Set Op A to 0 if not doing multiplication

    assign OpAMantisa   = {1'b1, OperandA[9:0]};
    assign OpBMantisa   = {1'b1, (mul ? OperandB[9:0] : 10'b0)};  //Set Op B to 1 if not doing multiplication
    //If OpC isnt zero give it a leading one
    assign OpCMantisa   = add ? {(|OperandC[14:0]), OperandC[9:0]} : 11'b0;    //Set Op A to 0 if not doing multiplication

    ////Multiplication calculation////

    logic MultiplcationInputZero;
    logic MultiplicationExponentOverflow;
    logic MultiplicationExponentNegative;

    assign MultiplicationResultSign         = OpASign ^ OpBSign;
    assign MultiplicationIntermediateExp    = OpAExponent + OpBExponent;
    assign MultiplicationResultExponent     = (MultiplicationIntermediateExp - 5'd15) & {(6){~MultiplcationInputZero}};
    assign MultiplicationResultMantisa      = OpAMantisa * OpBMantisa & {(22){~MultiplcationInputZero}};

    //TODO (think works) Need to ensure that overflow is not due to negative 2s compliment
    assign MultiplicationExponentOverflow   = MultiplicationResultExponent[5] & MultiplicationIntermediateExp[5]; 
    assign MultiplicationExponentNegative   = MultiplicationResultExponent[5];
    

    ////Accumulate calculation////
    accumulator Accumulator(.MultiplicationResultSign, .MultiplicationResultExponent, .MultiplicationResultMantisa,
                            .OpCSign, .OpCExponent, .OpCMantisa, .MultiplicationExponentNegative, .MultiplicationProducedInf,
                            .MultiplicationResultZero(MultiplcationInputZero), .AccumulateSignMismatch, .StickyA, .StickyB,
                            .AccumulateResultSign, .AccumulateResultExponent, .AccumulateResultMantisa);

    //Normalization
    normalizationShifter NormalizationShifter(.AccumulateResultMantisa, .AccumulateResultExponent, 
                                                .AccumulateSubtraction(AccumulateSignMismatch),
                                                .NormalizedMantisa, .NormalizedExponent);

    rounder Rounder(.NormalizedMantisa, .StickyA, .StickyB, .RoundedMantisa, .InexactRound);

    //Special Cases (inf, Nan, Zero)
    assign AnticipatedResult = {AccumulateResultSign, NormalizedExponent, RoundedMantisa};

    specialCaseHandler SpecialCaseHandler(.OpAExponent, .OpBExponent, .OpCExponent, .OpAMantisa, .OpBMantisa,
                                        .OpCMantisa, .OpCSign, .MultiplicationExponentOverflow, .AccumulateSubtraction(AccumulateSignMismatch),
                                        .MultiplicationResultSign, .AccumulateResultSign, .MultiplcationInputZero, 
                                        .MultiplicationProducedInf, .ArithmaticInvalid, 
                                        .OpANan, .OpBNan, .OpCNan,
                                        .AnticipatedResult, .result);

    //Flags
    flagHandler FlagHandler(.roundmode, 
                            .OpASignalNan(OpANan & ~OpAMantisa[9]),
                            .OpBSignalNan(OpBNan & ~OpBMantisa[9]),
                            .OpCSignalNan(OpCNan & ~OpCMantisa[9]),
                            .ArithmaticInvalid,
                            .InexactRound,
                            .flags);

endmodule

module accumulator (
    input   logic       MultiplicationResultSign,
    input   logic[5:0]  MultiplicationResultExponent,
    input   logic[21:0] MultiplicationResultMantisa,

    input   logic       OpCSign,
    input   logic[4:0]  OpCExponent,
    input   logic[10:0] OpCMantisa,
    
    input   logic       MultiplicationExponentNegative,
    input   logic       MultiplicationProducedInf,
    input   logic       MultiplicationResultZero, 

    output  logic       AccumulateSignMismatch,
    output  logic       StickyA,
    output  logic       StickyB,

    output  logic       AccumulateResultSign,
    output  logic[4:0]  AccumulateResultExponent,
    output  logic[23:0] AccumulateResultMantisa
);
    logic[21:0]     AccumulateOperandA;
    logic[21:0]     AccumulateOperandB;

    logic[5:0]      AccumulateExponentDiff;
    logic           NegExponentDiff;
    logic           OpCExponentGreater;
    logic[5:0]      AccumulateOpAShiftAmt, AccumulateOpBShiftAmt;

    logic[21:-20]   ShiftedMultiplicationResultMantisa, ShiftedOpCMantisa;
    logic[22:0]     SelectivelyInvertedAccumulateOpB;
    logic[23:0]     AccumulateStandardMantisa, AccumulateInvertedMantisa;

    logic           AccumulateInvertedMantisaNegative;
    logic           SelectAccumulateInvertedMantisa;

    ////-----------CALCULATE SHIFT-----------////
    assign AccumulateExponentDiff   = 6'(MultiplicationResultExponent[5:0] - {1'b0, OpCExponent});
    assign NegExponentDiff          = AccumulateExponentDiff[5];
    
    assign OpCExponentGreater       = (NegExponentDiff | MultiplicationExponentNegative); 

    assign AccumulateOpBShiftAmt    = AccumulateExponentDiff & {(6){~OpCExponentGreater}};
    assign AccumulateOpAShiftAmt    = (~AccumulateExponentDiff[5:0] + 1) & {(6){OpCExponentGreater}};

    ////-----------SHIFT-----------////
    assign ShiftedMultiplicationResultMantisa   = {MultiplicationResultMantisa[21:0], 20'b0}    >> AccumulateOpAShiftAmt;
    assign ShiftedOpCMantisa                    = {1'b0, OpCMantisa, 30'b0}                     >> AccumulateOpBShiftAmt;

    assign AccumulateOperandA = ShiftedMultiplicationResultMantisa[21:0];
    assign AccumulateOperandB = ShiftedOpCMantisa[21:0];

    //If the bottom bits are one or if the number was non-zero and has been completely shifted out (can consider the sticky )
    assign StickyA = ((|ShiftedMultiplicationResultMantisa[-1:-20]) | 
                    (~MultiplicationResultZero & (((AccumulateOpAShiftAmt[4] & AccumulateOpAShiftAmt[2]) 
                    | (AccumulateOpAShiftAmt[4] & AccumulateOpAShiftAmt[3]) | (AccumulateOpAShiftAmt[5])))));
    //When either the bottom bits are 1 or the number is non-zero and all the bits have been shifted out
    assign StickyB = ((|ShiftedOpCMantisa[-1:-20]) | 
                    ((|{OpCExponent, OpCMantisa}) & (((AccumulateOpBShiftAmt[4] & AccumulateOpBShiftAmt[2]) 
                    | (AccumulateOpBShiftAmt[4] & AccumulateOpBShiftAmt[3]) | (AccumulateOpBShiftAmt[5])))));

    ////-----------ADD-----------////

    assign AccumulateSignMismatch           = MultiplicationResultSign ^ OpCSign;

    assign SelectivelyInvertedAccumulateOpB = AccumulateSignMismatch ? 
                                            ~{AccumulateOperandB, StickyB} : {AccumulateOperandB, StickyB};

    assign AccumulateStandardMantisa        = {AccumulateOperandA, StickyA} + SelectivelyInvertedAccumulateOpB 
                                                + {22'b0, AccumulateSignMismatch};
    assign AccumulateInvertedMantisa        = {AccumulateOperandB, StickyB} - {AccumulateOperandA, StickyA};

    assign AccumulateInvertedMantisaNegative = AccumulateInvertedMantisa[23];

    assign SelectAccumulateInvertedMantisa = ~AccumulateInvertedMantisaNegative & AccumulateSignMismatch;

    assign AccumulateResultSign         = MultiplicationResultSign ^ 
                                        ((AccumulateSignMismatch & SelectAccumulateInvertedMantisa) & ~MultiplicationProducedInf);
    
    assign AccumulateResultExponent     = OpCExponentGreater ? OpCExponent : MultiplicationResultExponent[4:0];
    assign AccumulateResultMantisa      = SelectAccumulateInvertedMantisa ? AccumulateInvertedMantisa : AccumulateStandardMantisa;

endmodule

//Conduct massive cancelation and remove the leading 1 from result mantisa
module normalizationShifter (
    input   logic[23:0] AccumulateResultMantisa,
    input   logic[4:0]  AccumulateResultExponent,
    input   logic       AccumulateSubtraction,

    output  logic[23:0] NormalizedMantisa,
    output  logic[4:0]  NormalizedExponent
);
    logic   [4:0]   ShiftAmt;
    int             idx;

    always_comb begin
        
        idx = 1;

        if (AccumulateResultMantisa[23] & ~AccumulateSubtraction) begin //First bit of result is overflow if subtraction was performed
            ShiftAmt = 5'd0;
            NormalizedExponent = AccumulateResultExponent + 2;
        end else begin
            //Priotiry Encoder
            while (idx >= -31 & ~AccumulateResultMantisa[21+idx]) begin
                idx--;
            end
            ShiftAmt = 5'(2 - idx);
            NormalizedExponent = 5'(AccumulateResultExponent + idx);
        end            
    end    
    
    assign NormalizedMantisa = (AccumulateResultMantisa << ShiftAmt);

endmodule

module rounder(
    input   logic[23:0] NormalizedMantisa,

    input   logic       StickyA,
    input   logic       StickyB,

    output  logic[9:0]  RoundedMantisa,

    output  logic       InexactRound
);

    assign RoundedMantisa   = NormalizedMantisa[22:13];
    //TODO There is a chance for a hyper edge case where the sticky bit is active and its being subtracted and the sticky bit and tunkated bits are all 0 maybe 
    assign InexactRound     = (|NormalizedMantisa[12:0]) | StickyA | StickyB; //Both sticky bits cannot be one at the same time so theres no chance for cancelation
endmodule

module specialCaseHandler (
    input   logic[4:0]  OpAExponent,
    input   logic[4:0]  OpBExponent,
    input   logic[4:0]  OpCExponent,
    input   logic[10:0] OpAMantisa,
    input   logic[10:0] OpBMantisa,
    input   logic[10:0] OpCMantisa,
    input   logic       OpCSign,

    input   logic       MultiplicationExponentOverflow,
    input   logic       AccumulateSubtraction,
    input   logic       MultiplicationResultSign,
    input   logic       AccumulateResultSign,

    output  logic       MultiplcationInputZero,
    output  logic       MultiplicationProducedInf,
    output  logic       ArithmaticInvalid,

    output  logic       OpANan,
    output  logic       OpBNan,
    output  logic       OpCNan,

    input   logic[15:0] AnticipatedResult,
    output  logic[15:0] result
);

    `ifdef DEBUG
    specialCase SpecialCase;
    `endif 

    logic OpAExponentAllOnes,   OpBExponentAllOnes, OpCExponentAllOnes;
    logic OpAExponentZero,      OpBExponentZero;
    logic OpAMantisaZero,       OpBMantisaZero,     OpCMantisaZero;
    logic OpAMantisaNonZero,    OpBMantisaNonZero,  OpCMantisaNonZero;

    assign OpAMantisaZero       = ~(|OpAMantisa[9:0]);
    assign OpBMantisaZero       = ~(|OpBMantisa[9:0]);
    assign OpCMantisaZero       = ~(|OpCMantisa[9:0]);

    assign OpAMantisaNonZero    = (|OpAMantisa[9:0]);
    assign OpBMantisaNonZero    = (|OpBMantisa[9:0]);
    assign OpCMantisaNonZero    = (|OpCMantisa[9:0]);

    assign OpAExponentZero      = ~(|OpAExponent);
    assign OpBExponentZero      = ~(|OpBExponent);

    assign OpAExponentAllOnes   = (&OpAExponent);
    assign OpBExponentAllOnes   = (&OpBExponent);
    assign OpCExponentAllOnes   = (&OpCExponent);

    assign OpANan               = (OpAExponentAllOnes & OpAMantisaNonZero);
    assign OpBNan               = (OpBExponentAllOnes & OpBMantisaNonZero);
    assign OpCNan               = (OpCExponentAllOnes & OpCMantisaNonZero);

    assign MultiplicationProducedInf    = MultiplicationExponentOverflow | OpAExponentAllOnes | OpBExponentAllOnes;
    assign MultiplcationInputZero       = (OpAExponentZero & OpAMantisaZero) | (OpBExponentZero & OpBMantisaZero);


    always_comb begin
        //Zero times inf
        if (OpAMantisaZero & OpBMantisaZero & 
            ((OpAExponentZero & OpBExponentAllOnes) | (OpBExponentZero & OpAExponentAllOnes))) begin
            
            result[15:0]            = 16'b0_11111_1000000000; //NAN
            ArithmaticInvalid       = 1'b1;

            `ifdef DEBUG
            SpecialCase = ZeroTimesInf;
            `endif 

        // if any of inputs are NAN
        end else if (OpANan | OpBNan | OpCNan) begin
            
            result[15:0]            = 16'b0_11111_1000000000; //NAN
            ArithmaticInvalid       = 1'b0;

            `ifdef DEBUG
            SpecialCase = InputsNaN;
            `endif 

        //If multiplcation results in inf due to overflow of exponent or starting with inf
        end else if (MultiplicationProducedInf) begin 

            //If either OpC is the inverse inf or nan
            if(OpCExponentAllOnes & (AccumulateSubtraction | OpCMantisaNonZero)) begin

                result[15:0]        = 16'b0_11111_1000000000; //NAN
                ArithmaticInvalid   = ~(|OpCMantisa[9:0]); // if the reason for entering the case was +inf -inf

                `ifdef DEBUG
                SpecialCase = CalculatedNaN;
                `endif 

            end else begin

                result[15:0]        = {MultiplicationResultSign, 15'b11111_0000000000};//INF
                ArithmaticInvalid   = 1'b0;

                `ifdef DEBUG
                SpecialCase = MultiplicationOverflow;
                `endif 

            end
        //op C is inf and multiplication edge cases already handled
        end else if (OpCExponentAllOnes & OpCMantisaZero) begin

            result[15:0]            = {OpCSign, 15'b11111_0000000000};//INF
            ArithmaticInvalid       = 1'b0;

            `ifdef DEBUG
            SpecialCase             = AdditionOverflow;
            `endif 

        //Otherwise use FMA result
        end else begin

            result                  = AnticipatedResult;
            ArithmaticInvalid       = 1'b0;

            `ifdef DEBUG
            SpecialCase = None;
            `endif 
        end
    end

endmodule

module flagHandler (
    input   logic[1:0]  roundmode,

    input   logic       OpASignalNan,
    input   logic       OpBSignalNan, 
    input   logic       OpCSignalNan,

    input   logic       ArithmaticInvalid,
    input   logic       InexactRound,

    output  logic[3:0]  flags
);
    logic   RNE, RNTA, RZ, RN, RP;
    logic   Invalid, Overflow, Underflow, Inexact;

    assign RNE  = roundmode == 2'b01;
    assign RZ   = roundmode == 2'b00;
    assign RN   = roundmode == 2'b10;
    assign RP   = roundmode == 2'b11;

    assign Invalid      = OpASignalNan | OpBSignalNan | OpCSignalNan | ArithmaticInvalid;
    assign Overflow     = 1'b0;
    assign Underflow    = 1'b0;
    assign Inexact      = InexactRound;

    assign flags        = {Invalid, Overflow, Underflow, Inexact};

endmodule