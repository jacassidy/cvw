//2/12/25 jkc.cassidy@gmail.com James Kaden Cassidy

//Conducts result = A * B + C

// typedef enum logic[5:0] {
//         None,
//         ZeroTimesInf,
//         InputsNaN,
//         CalculatedNaN,
//         MultiplicationOverflow,
//         AdditionOverflow
// } specialCase;

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
    logic[5:0]  MultiplicationResultExponent;
    logic[21:0] MultiplicationResultMantisa;

    logic       AccumulateResultSign;
    logic[4:0]  AccumulateResultExponent;
    logic[23:0] AccumulateResultMantisa;
    logic       NormalizationOverflow;

    logic[4:0]  NormalizedExponent;
    logic[23:0] NormalizedMantisa;
    logic       NormalizedSign;

    logic[4:0]  RoundedExponent;
    logic[9:0]  RoundedMantisa;
    
    logic[15:0] AnticipatedResult;

    logic       InexactRound, StickyA, StickyB;

    //Intermodule Signals
    logic       MultiplicationOperandInf;
    logic       ArithmaticInvalid;

    logic       AccumulateSignMismatch;
    logic       RoundUpOverflow;

    logic       ZeroResultSign;

    logic[3:0]  expectedFlags;


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
    logic MultiplicationExponentUnderflow;

    ////Multiplier////
    multiplier Multiplier(.OpASign, .OpBSign, .OpCSign, .OpAExponent, .OpBExponent, .OpCExponent, .OpAMantisa, .OpBMantisa,
                            .OpCMantisa, .MultiplcationInputZero, .MultiplicationResultSign, .MultiplicationResultExponent,
                            .MultiplicationResultMantisa, .MultiplicationExponentOverflow, .MultiplicationExponentUnderflow, 
                            .MultiplicationExponentNegative);

    ////Accumulate calculation////
    accumulator Accumulator(.MultiplicationResultSign, .MultiplicationResultExponent, .MultiplicationResultMantisa,
                            .OpCSign, .OpCExponent, .OpCMantisa, .MultiplicationExponentNegative, .MultiplicationOperandInf,
                            .MultiplicationExponentOverflow,
                            .MultiplicationResultZero(MultiplcationInputZero), .AccumulateSignMismatch, .StickyA, .StickyB,
                            .AccumulateResultSign, .AccumulateResultExponent, .AccumulateResultMantisa);

    zeroSignAnticipator ZeroSignAnticipator(.roundmode, .OpASign, .OpBSign, .OpCSign, .MultiplicationExponentUnderflow, 
                                            .MultiplcationInputZero, .ZeroResultSign);

    //Normalization
    normalizationShifter NormalizationShifter(.AccumulateResultMantisa, .AccumulateResultExponent, .AccumulateResultSign, 
                                                .AccumulateSubtraction(AccumulateSignMismatch),  .MultiplicationExponentOverflow,
                                                .ZeroResultSign, .NormalizedMantisa, .NormalizedExponent, .NormalizedSign, 
                                                .NormalizationOverflow);

    rounder Rounder(.roundmode, .NormalizedSign, .NormalizedExponent, .NormalizedMantisa, .StickyA, .StickyB, 
                    .PreRoundOverflow(MultiplicationExponentOverflow | (NormalizationOverflow)),
                    .RoundedExponent, .RoundedMantisa, .InexactRound, .RoundUpOverflow);

    //Special Cases (inf, Nan, Zero)
    assign AnticipatedResult = {NormalizedSign, RoundedExponent, RoundedMantisa};

    //Flags
    flagHandler FlagHandler(.OpASignalNan(OpANan & ~OpAMantisa[9]),
                            .OpBSignalNan(OpBNan & ~OpBMantisa[9]),
                            .OpCSignalNan(OpCNan & ~OpCMantisa[9]),
                            .ArithmaticInvalid,
                            .InexactRound,
                            .MultiplicationExponentOverflow,
                            .FinalResultInf(&NormalizedExponent[4:0]),
                            .MultiplicationExponentUnderflow,
                            .NormalizationOverflow,
                            .RoundUpOverflow,
                            .flags(expectedFlags));

    specialCaseHandler SpecialCaseHandler(.OpAExponent, .OpBExponent, .OpCExponent, .OpAMantisa, .OpBMantisa,
                                        .OpCMantisa, .OpCSign, .MultiplicationExponentOverflow, .AccumulateSubtraction(AccumulateSignMismatch),
                                        .MultiplicationResultSign, .AccumulateResultSign, .MultiplcationInputZero, 
                                        .MultiplicationOperandInf, .ArithmaticInvalid, 
                                        .OpANan, .OpBNan, .OpCNan, .expectedFlags,
                                        .AnticipatedResult, .result, .flags);

    

endmodule

module multiplier(
    input   logic       OpASign,
    input   logic       OpBSign,
    input   logic       OpCSign,

    input   logic[4:0]  OpAExponent,
    input   logic[4:0]  OpBExponent,
    input   logic[4:0]  OpCExponent,

    input   logic[10:0] OpAMantisa,
    input   logic[10:0] OpBMantisa,
    input   logic[10:0] OpCMantisa,

    input   logic       MultiplcationInputZero,

    output  logic       MultiplicationResultSign,
    output  logic[5:0]  MultiplicationResultExponent,
    output  logic[21:0] MultiplicationResultMantisa,

    output  logic       MultiplicationExponentOverflow,
    output  logic       MultiplicationExponentUnderflow,
    output  logic       MultiplicationExponentNegative
);
    logic[5:0] MultiplicationIntermediateExp;

    assign MultiplicationResultSign         = OpASign ^ OpBSign;
    assign MultiplicationIntermediateExp    = OpAExponent + OpBExponent;
    assign MultiplicationResultExponent     = (MultiplicationIntermediateExp - 5'd15) & {(6){~MultiplcationInputZero}};
    assign MultiplicationResultMantisa      = OpAMantisa * OpBMantisa & {(22){~MultiplcationInputZero}};

    //TODO (think works) Need to ensure that overflow is not due to negative 2s compliment
    assign MultiplicationExponentOverflow   = MultiplicationResultExponent[5] & MultiplicationIntermediateExp[5]; 
    assign MultiplicationExponentUnderflow  = MultiplicationResultExponent[5] & ~MultiplicationIntermediateExp[5];
    assign MultiplicationExponentNegative   = MultiplicationResultExponent[5];

endmodule

module accumulator (
    input   logic       MultiplicationResultSign,
    input   logic[5:0]  MultiplicationResultExponent,
    input   logic[21:0] MultiplicationResultMantisa,

    input   logic       OpCSign,
    input   logic[4:0]  OpCExponent,
    input   logic[10:0] OpCMantisa,
    
    input   logic       MultiplicationExponentNegative,
    input   logic       MultiplicationOperandInf,
    input   logic       MultiplicationExponentOverflow,
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

    logic[6:0]      AccumulateExponentDiff;
    logic           NegExponentDiff;
    logic           OpCExponentGreater;
    logic[6:0]      AccumulateOpAShiftAmt, AccumulateOpBShiftAmt;

    logic[21:-20]   ShiftedMultiplicationResultMantisa, ShiftedOpCMantisa;
    logic[22:0]     SelectivelyInvertedAccumulateOpB;
    logic[23:0]     AccumulateStandardMantisa, AccumulateInvertedMantisa;

    logic           AccumulateInvertedMantisaNegative;
    logic           SelectAccumulateInvertedMantisa;

    ////-----------CALCULATE SHIFT-----------////
    assign AccumulateExponentDiff   = MultiplicationResultExponent[5:0] - {1'b0, OpCExponent};
    assign NegExponentDiff          = AccumulateExponentDiff[5];
    
    assign OpCExponentGreater       = (NegExponentDiff | MultiplicationExponentNegative); 

    assign AccumulateOpBShiftAmt    = AccumulateExponentDiff & {(7){~OpCExponentGreater}};
    assign AccumulateOpAShiftAmt    = (~AccumulateExponentDiff + 1) & {(7){OpCExponentGreater}} & {~MultiplicationExponentNegative, 6'b111111};

    ////-----------SHIFT-----------////
    assign ShiftedMultiplicationResultMantisa   = {MultiplicationResultMantisa[21:0], 20'b0}    >> AccumulateOpAShiftAmt;
    assign ShiftedOpCMantisa                    = {1'b0, OpCMantisa, 30'b0}                     >> AccumulateOpBShiftAmt;

    assign AccumulateOperandA = ShiftedMultiplicationResultMantisa[21:0];
    assign AccumulateOperandB = ShiftedOpCMantisa[21:0];

    //If the bottom bits are one or if the number was non-zero and has been completely shifted out (can consider the sticky )
    assign StickyA = ((|ShiftedMultiplicationResultMantisa[-1:-20]) | 
                    (~MultiplicationResultZero & (((AccumulateOpAShiftAmt[4] & AccumulateOpAShiftAmt[2]) 
                    | (AccumulateOpAShiftAmt[4] & AccumulateOpAShiftAmt[3]) | (|AccumulateOpAShiftAmt[6:5])))));
    //When either the bottom bits are 1 or the number is non-zero and all the bits have been shifted out
    assign StickyB = ((|ShiftedOpCMantisa[-1:-20]) | 
                    ((|{OpCExponent, OpCMantisa}) & (((AccumulateOpBShiftAmt[4] & AccumulateOpBShiftAmt[2]) 
                    | (AccumulateOpBShiftAmt[4] & AccumulateOpBShiftAmt[3]) | (|AccumulateOpBShiftAmt[6:5])))));

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
                                        ((AccumulateSignMismatch & SelectAccumulateInvertedMantisa) & ~MultiplicationOperandInf & ~MultiplicationExponentOverflow);
    
    assign AccumulateResultExponent     = OpCExponentGreater ? OpCExponent : MultiplicationResultExponent[4:0];
    assign AccumulateResultMantisa      = SelectAccumulateInvertedMantisa ? AccumulateInvertedMantisa : AccumulateStandardMantisa;

endmodule

module zeroSignAnticipator(
    input   logic[1:0]  roundmode,

    input   logic       OpASign,
    input   logic       OpBSign,
    input   logic       OpCSign,

    input   logic       MultiplicationExponentUnderflow,
    input   logic       MultiplcationInputZero,

    output  logic       ZeroResultSign
);

    always_comb begin
        case(roundmode)
            2'b00: begin //RZ
                ZeroResultSign = (MultiplicationExponentUnderflow ? (OpASign ^ OpBSign) :
                    (MultiplcationInputZero ? (OpASign ^ OpBSign) & OpCSign : 1'b0));
            end
            2'b10: begin //RN
                ZeroResultSign = (MultiplicationExponentUnderflow ? (OpASign ^ OpBSign) :
                    (MultiplcationInputZero ? (OpASign ^ OpBSign) | OpCSign : 1'b1));
            end
            2'b01: begin //RNE
                ZeroResultSign = (MultiplicationExponentUnderflow ? (OpASign ^ OpBSign) :
                    (MultiplcationInputZero ? (OpASign ^ OpBSign) & OpCSign : 1'b0));
            end
            2'b11: begin //RP
                ZeroResultSign = (MultiplicationExponentUnderflow ? (OpASign ^ OpBSign) :
                    (MultiplcationInputZero ? (OpASign ^ OpBSign) & OpCSign : 1'b0));
            end
            default: ZeroResultSign = 1'b0;
        endcase
    end

    

endmodule

//Conduct massive cancelation and remove the leading 1 from result mantisa
module normalizationShifter (
    input   logic[23:0] AccumulateResultMantisa,
    input   logic[4:0]  AccumulateResultExponent,
    input   logic       AccumulateResultSign, 
    input   logic       AccumulateSubtraction,

    input   logic       ZeroResultSign,
    input   logic       MultiplicationExponentOverflow,

    output  logic[23:0] NormalizedMantisa,
    output  logic[4:0]  NormalizedExponent,
    output  logic       NormalizedSign,

    output  logic       NormalizationOverflow
);
    logic   [4:0]   ShiftAmt;
    int             idx;

    logic           CarryOut;

    always_comb begin
        
        idx = 1;
        //TODO Multiplication exponent overflow is to make sure the normalized sign isnt modified on the hyper edge case there is an overflow and the mantisa is 0
        if(~((AccumulateResultMantisa[23] & ~AccumulateSubtraction) | (|AccumulateResultMantisa[22:1])) & ~MultiplicationExponentOverflow) begin //If accumulate produces 0
            NormalizedMantisa       = 24'b0;
            NormalizedExponent      = 5'b0;
            NormalizationOverflow   = 1'b0;
            ShiftAmt                = 5'd0;
            NormalizedSign          = ZeroResultSign;
            CarryOut                = 1'b0;
        end else begin
            if (AccumulateResultMantisa[23] & ~AccumulateSubtraction) begin //First bit of result is overflow if subtraction was performed
                ShiftAmt = 5'd0;
                {CarryOut, NormalizedExponent} = AccumulateResultExponent + 2;
                NormalizationOverflow = CarryOut | (&NormalizedExponent);
            end else begin
                //Priotiry Encoder
                while (idx >= -31 & ~AccumulateResultMantisa[21+idx]) begin
                    idx--;
                end
                ShiftAmt = 5'(2 - idx);
                {CarryOut, NormalizedExponent} = AccumulateResultExponent + 5'(idx);
                NormalizationOverflow = (CarryOut & (idx >= 0)) | (&NormalizedExponent); //if index is negative than carry bit isn't overflow
            end       
            NormalizedMantisa = (AccumulateResultMantisa << ShiftAmt);
            NormalizedSign  = AccumulateResultSign;    
        end
    end    
    
endmodule

module rounder(
    input   logic[1:0]  roundmode,

    input   logic       NormalizedSign,
    input   logic[4:0]  NormalizedExponent,
    input   logic[23:0] NormalizedMantisa,

    input   logic       StickyA,
    input   logic       StickyB,

    input   logic       PreRoundOverflow, //Needed to determine what to happens (inf or max num)

    output  logic[4:0]  RoundedExponent,
    output  logic[9:0]  RoundedMantisa,

    output  logic       InexactRound,
    output  logic       RoundUpOverflow
);
    logic   RNE, RNTA, RZ, RN, RP;
    logic   LeastSigBit, GuardBit, RoundBit, StickyBit;
    logic   RoundUp;
    logic   InexactTruncate;

    assign RNE  = roundmode == 2'b01;
    assign RZ   = roundmode == 2'b00;
    assign RN   = roundmode == 2'b10;
    assign RP   = roundmode == 2'b11;

    assign LeastSigBit  = NormalizedMantisa[13];
    assign GuardBit     = NormalizedMantisa[12];
    assign RoundBit     = NormalizedMantisa[11];
    assign StickyBit    = (|NormalizedMantisa[10:0]);

    always_comb begin
        case(roundmode)
            2'b00: begin //RZ
                RoundUp = 1'b0;
            end
            2'b10: begin //RN
                if(PreRoundOverflow) begin
                    RoundUp = NormalizedSign;
                end else begin
                    if(NormalizedSign) begin
                        casez({LeastSigBit, GuardBit, RoundBit | StickyBit}) 
                            3'b?01: RoundUp = 1'b1;
                            3'b010: RoundUp = 1'b1;
                            3'b110: RoundUp = 1'b1;
                            3'b?11: RoundUp = 1'b1;

                            default: RoundUp = 1'b0;
                        endcase
                    end else begin
                        RoundUp = 1'b0;
                    end
                end
            end
            2'b01: begin //RNE
                casez({NormalizedSign, PreRoundOverflow, LeastSigBit, GuardBit, RoundBit | StickyBit}) 
                    5'b0_0_110: RoundUp = 1'b1;
                    5'b0_0_?11: RoundUp = 1'b1;
                    5'b0_1_???: RoundUp = 1'b1;
                    
                    5'b1_0_010: RoundUp = 1'b0;
                    5'b1_0_110: RoundUp = 1'b1;
                    5'b1_0_?11: RoundUp = 1'b1;
                    5'b1_1_???: RoundUp = 1'b1;

                    default: RoundUp = 1'b0;
                endcase 
            end
            2'b11: begin //RP
                casez({NormalizedSign, PreRoundOverflow, LeastSigBit, GuardBit, RoundBit | StickyBit}) 
                    5'b0_0_?01: RoundUp = 1'b1;
                    5'b0_0_010: RoundUp = 1'b1;
                    5'b0_0_110: RoundUp = 1'b1;
                    5'b0_0_?11: RoundUp = 1'b1;
                    5'b0_1_???: RoundUp = 1'b1;

                    default: RoundUp = 1'b0;
                endcase 
            end
            default: RoundUp = 1'b0;
        endcase
    end

    logic[4:0]  RoundedUpExponent;
    logic[11:0] NormalizedMantisaP1;
    logic[9:0]  RoundedUpMantisa;
    logic Carry;

    always_comb begin
        RoundedUpExponent   = 'x;
        NormalizedMantisaP1 = 'x;
        RoundedUpMantisa    = 'x;
        Carry               = 'x;

        if(PreRoundOverflow) begin
            if(~RoundUp) begin //If round zero the result is maxnum
                RoundedExponent = 5'b11110;
                RoundedMantisa  = 10'b1111111111;
            end else begin //otherwise inf is produced during multiplication
                RoundedExponent = 5'b11111;
                RoundedMantisa  = 10'b0000000000;
            end
            InexactRound     = InexactTruncate;
            RoundUpOverflow  = 1'b0;
        end else begin
            if(RoundUp) begin
                
                //TODO round up logic
                NormalizedMantisaP1 = NormalizedMantisa[23:13] + {10'b0, 1'b1};

                if(NormalizedMantisaP1[11]) begin //Extra up shift required
                    {Carry, RoundedUpExponent}  = NormalizedExponent + 1;
                    RoundedUpMantisa            = NormalizedMantisaP1[10:1];
                end else begin
                    Carry                       = 1'b0;
                    RoundedUpExponent           = NormalizedExponent;
                    RoundedUpMantisa            = NormalizedMantisaP1[9:0];
                end

                InexactRound     = 1'b1;
                
                //TODO what happens if this overflows the result
                if(Carry | (&RoundedUpExponent)) begin
                    //TODO always round up
                    // if(~RZ) begin //If round zero the result is maxnum 
                        // RoundedExponent = 5'b11110;
                        // RoundedMantisa  = 10'b1111111111;
                    // end else begin //otherwise inf is produced during multiplication
                        RoundedExponent = 5'b11111;
                        RoundedMantisa  = 10'b0000000000;
                    // end
                    //InexactRound     = InexactRound; // TODO add logic
                    RoundUpOverflow     = 1'b1;
                end else begin
                    RoundedExponent     = RoundedUpExponent;
                    RoundedMantisa      = RoundedUpMantisa;
                    RoundUpOverflow     = 1'b0;
                end
            end else begin
                //Truncate
                RoundedMantisa   = NormalizedMantisa[22:13];
                RoundedExponent  = NormalizedExponent;
                InexactRound     = InexactTruncate;
                RoundUpOverflow  = 1'b0;
            end
        end
    end
    //TODO There is a chance for a hyper edge case where the sticky bit is active and its being subtracted and the sticky bit and tunkated bits are all 0 maybe 
    assign InexactTruncate     = GuardBit | RoundBit | StickyBit /*| StickyA | StickyB*/; //Both sticky bits cannot be one at the same time so theres no chance for cancelation

    
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

    input   logic[3:0]  expectedFlags,

    output  logic       MultiplcationInputZero,
    output  logic       MultiplicationOperandInf,
    output  logic       ArithmaticInvalid,

    output  logic       OpANan,
    output  logic       OpBNan,
    output  logic       OpCNan,

    input   logic[15:0] AnticipatedResult,
    output  logic[15:0] result,
    output  logic[3:0]  flags
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

    //TODO multiplication produce INF needs to be reworked as overflow is different than an initial operand being inf in rounding
    assign MultiplicationOperandInf    = OpAExponentAllOnes | OpBExponentAllOnes;
    assign MultiplcationInputZero       = (OpAExponentZero & OpAMantisaZero) | (OpBExponentZero & OpBMantisaZero);


    always_comb begin
        //Zero times inf
        if (OpAMantisaZero & OpBMantisaZero & 
            ((OpAExponentZero & OpBExponentAllOnes) | (OpBExponentZero & OpAExponentAllOnes))) begin
            
            result[15:0]            = 16'b0_11111_1000000000; //NAN
            ArithmaticInvalid       = 1'b1;
            flags                   = 4'b1000;

            `ifdef DEBUG
            SpecialCase = ZeroTimesInf;
            `endif 

        // if any of inputs are NAN
        end else if (OpANan | OpBNan | OpCNan) begin
            
            result[15:0]            = 16'b0_11111_1000000000; //NAN
            ArithmaticInvalid       = 1'b0;
            flags                   = {expectedFlags[3], 3'b000};

            `ifdef DEBUG
            SpecialCase = InputsNaN;
            `endif 

        //If multiplcation results in inf due starting with inf
        end else if (MultiplicationOperandInf) begin 

            //If either OpC is the inverse inf or nan
            if(OpCExponentAllOnes & (AccumulateSubtraction | OpCMantisaNonZero)) begin

                result[15:0]        = 16'b0_11111_1000000000; //NAN
                ArithmaticInvalid   = ~(|OpCMantisa[9:0]); // if the reason for entering the case was +inf -inf
                flags               = {expectedFlags[3], 3'b000};

                `ifdef DEBUG
                SpecialCase = CalculatedNaN;
                `endif 

            end else begin

                result[15:0]        = {MultiplicationResultSign, 15'b11111_0000000000};//INF
                ArithmaticInvalid   = 1'b0;
                flags               = 4'b0000;

                `ifdef DEBUG
                SpecialCase = MultiplicationOverflow;
                `endif 

            end
        //op C is inf and multiplication edge cases already handled
        end else if (OpCExponentAllOnes & OpCMantisaZero) begin

            result[15:0]            = {OpCSign, 15'b11111_0000000000};//INF
            ArithmaticInvalid       = 1'b0;
            flags                   = 4'b0000;

            `ifdef DEBUG
            SpecialCase             = AdditionOverflow;
            `endif 

        //Otherwise use FMA result
        end else begin

            result                  = AnticipatedResult;
            ArithmaticInvalid       = 1'b0;
            flags                   = expectedFlags;

            `ifdef DEBUG
            SpecialCase = None;
            `endif 
        end
    end

endmodule

module flagHandler (
    input   logic       OpASignalNan,
    input   logic       OpBSignalNan, 
    input   logic       OpCSignalNan,

    input   logic       ArithmaticInvalid,
    input   logic       InexactRound,
    input   logic       MultiplicationExponentOverflow,
    input   logic       FinalResultInf,
    input   logic       MultiplicationExponentUnderflow,
    input   logic       NormalizationOverflow,
    input   logic       RoundUpOverflow,

    output  logic[3:0]  flags
);
    logic   Invalid, Overflow, Underflow, Inexact;

    //All by definition
    assign Invalid      = OpASignalNan | OpBSignalNan | OpCSignalNan | ArithmaticInvalid;
    assign Overflow     = (MultiplicationExponentOverflow | FinalResultInf | NormalizationOverflow | RoundUpOverflow);
    assign Underflow    = /*MultiplicationExponentUnderflow;*/ 1'b0;
    assign Inexact      = InexactRound | Overflow; 

    assign flags        = {Invalid, Overflow, Underflow, Inexact};

endmodule