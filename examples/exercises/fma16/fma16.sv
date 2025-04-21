//2/12/25 jkc.cassidy@gmail.com James Kaden Cassidy

//Conducts result = A * B + C
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
    logic OpASign, OpBSign, OpCSign, MultiplicationResultSign, ResultSign;
    logic AccumulateSignMismatch;
    logic SelectAccumulateInvertedMantisa;

    typedef enum logic[5:0] {
        None,
        ZeroTimesInf,
        InputsNaN,
        CalculatedNaN,
        MultiplicationOverflow,
        AdditionOverflow
    } specialCase;

    specialCase SpecialCase;

    logic               OpCExponentGreater;
    logic   [10:0]      OpAMantisa, OpBMantisa, OpCMantisa;
    logic   [4:0]       OpAExponent, OpBExponent, OpCExponent, PreshiftFinalExponent, ResultExponent;
    logic   [5:0]       AccumulateOpAShiftAmt, AccumulateOpBShiftAmt;
    logic   [5:0]       MultiplicationResultExponent, MultiplicationExponentAddition;
    logic   [21:0]      MultiplicationResultMantisa;
    logic   [22:0]      SelectivelyInvertedAccumulateOpB;
    logic   [21:-20]    ShiftedMultiplicationResultMantisa, ShiftedOpCMantisa;
    logic   [21:0]      AccumulateOperandA;
    logic   [21:0]      AccumulateOperandB;
    logic               GuardA, RoundA, StickyA, GuardB, RoundB, StickyB;
    logic   [22:-1]      AccumulateResultMantisa, AccumulateStandardMantisa, AccumulateInvertedMantisa;

    logic               RNE, RNTA, RZ, RN, RP;
    logic               Invalid, Overflow, Underflow, Inexact;
    logic               MulProduceInf;

    logic   [4:0]   FinalShiftAmt;

    ////Convenience Assignments////
    assign OpASign = OperandA[15];
    assign OpBSign = mul ? OperandB[15] : 0;    //Set Op B to 1 if not doing multiplication
    assign OpCSign = add ? OperandC[15] : 0;    //Set Op A to 0 if not doing multiplication

    assign OpAExponent = OperandA[14:10];
    assign OpBExponent = mul ? OperandB[14:10] : 5'd15; //Set Op B to 1 if not doing multiplication
    assign OpCExponent = add ? OperandC[14:10] : 5'b0;  //Set Op A to 0 if not doing multiplication

    assign OpAMantisa = {1'b1, OperandA[9:0]};
    assign OpBMantisa = {1'b1, (mul ? OperandB[9:0] : 10'b0)};  //Set Op B to 1 if not doing multiplication
    assign OpCMantisa = add ? {1'b1, OperandC[9:0]} : 11'b0;    //Set Op A to 0 if not doing multiplication

    ////Multiplication calculation////

    logic MultiplcationInputZero;
    assign MultiplcationInputZero = (~(|OpAExponent) & ~(|OpAMantisa[9:0])) | (~(|OpBExponent) & ~(|OpBMantisa[9:0]));

    assign MultiplicationResultMantisa      = OpAMantisa * OpBMantisa & {(22){~MultiplcationInputZero}};
    assign MultiplicationExponentAddition   = OpAExponent + OpBExponent;
    assign MultiplicationResultExponent     = (MultiplicationExponentAddition - 5'd15) & {(6){~MultiplcationInputZero}};
    assign MultiplicationResultSign         = OpASign ^ OpBSign;

    ////Accumulate shift calculation////
    logic NegExponentDiff;
    logic [5:0] AccumulateExponentDiff;
    assign {AccumulateExponentDiff} = {MultiplicationResultExponent[5:0]} - {1'b0, OpCExponent};
    assign NegExponentDiff = AccumulateExponentDiff[5];
    assign AccumulateSignMismatch = MultiplicationResultSign ^ OpCSign;
    
    //If mulExponent[4:0] is less than OpCExp or Multiplication overflowed exponent
    assign OpCExponentGreater = (NegExponentDiff | MultiplicationResultExponent[5]); 
    assign AccumulateOpBShiftAmt = AccumulateExponentDiff & {(6){~OpCExponentGreater}};
    assign AccumulateOpAShiftAmt = (~AccumulateExponentDiff[5:0] + 1) & {(6){OpCExponentGreater}};

    ////Shifting and truncated for rounding////
    assign ShiftedMultiplicationResultMantisa = {MultiplicationResultMantisa[21:0], 20'b0} >> AccumulateOpAShiftAmt;
    assign ShiftedOpCMantisa = {1'b0, OpCMantisa, 30'b0} >> AccumulateOpBShiftAmt;

    assign AccumulateOperandA = ShiftedMultiplicationResultMantisa[21:0];
    //If the bottom bits are one or if the number was non-zero and has been completely shifted out (can consider the sticky )
    assign StickyA = ((|ShiftedMultiplicationResultMantisa[-1:-20]) | (~MultiplcationInputZero & (((AccumulateOpAShiftAmt[4] & AccumulateOpAShiftAmt[2]) | (AccumulateOpAShiftAmt[4] & AccumulateOpAShiftAmt[3]) | (AccumulateOpAShiftAmt[5])))));

    assign AccumulateOperandB = ShiftedOpCMantisa[21:0];
    //When either the bottom bits are 1 or the number is non-zero and all the bits have been shifted out
    assign StickyB = ((|ShiftedOpCMantisa[-1:-20]) | (~MultiplcationInputZero & (((AccumulateOpBShiftAmt[4] & AccumulateOpBShiftAmt[2]) | (AccumulateOpBShiftAmt[4] & AccumulateOpBShiftAmt[3]) | (AccumulateOpBShiftAmt[5])))));

    ////Accumulate calculation////
    logic AccumulateInvertedMantisaNegative;

    assign SelectivelyInvertedAccumulateOpB = AccumulateSignMismatch ? ~{AccumulateOperandB, StickyB} : {AccumulateOperandB, StickyB};

    assign AccumulateStandardMantisa = ({AccumulateOperandA, StickyA} + SelectivelyInvertedAccumulateOpB + {22'b0, AccumulateSignMismatch});
    assign AccumulateInvertedMantisa = {AccumulateOperandB, StickyB} - {AccumulateOperandA, StickyA};

    assign AccumulateInvertedMantisaNegative = AccumulateInvertedMantisa[22];

    assign SelectAccumulateInvertedMantisa = ~AccumulateInvertedMantisaNegative & AccumulateSignMismatch;

    assign AccumulateResultMantisa = SelectAccumulateInvertedMantisa ? AccumulateInvertedMantisa : AccumulateStandardMantisa;

    ////Final calculations

    assign PreshiftFinalExponent = OpCExponentGreater ? OpCExponent : MultiplicationResultExponent[4:0];
    // AccumulateSignMismatch ? (MultiplicationResultSign ^ SelectAccumulateInvertedMantisa) : (MultiplicationResultSign); and not inf
    assign ResultSign = MultiplicationResultSign ^ ((AccumulateSignMismatch & SelectAccumulateInvertedMantisa) & ~MulProduceInf);

    logic oVerflow;

    always_comb begin
        
        if (AccumulateResultMantisa[22] & ~AccumulateSignMismatch) begin //during a subtraction this is the overflow bit
            FinalShiftAmt = 5'd1;
            {oVerflow, ResultExponent} = PreshiftFinalExponent + 2;
        end else if(AccumulateResultMantisa[21]) begin
            FinalShiftAmt = 5'd2;
            {oVerflow, ResultExponent}= PreshiftFinalExponent + 1;
        end else if(AccumulateResultMantisa[20]) begin
            FinalShiftAmt = 5'd3;
            ResultExponent = PreshiftFinalExponent;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[19]) begin
            FinalShiftAmt = 5'd4;
            ResultExponent = PreshiftFinalExponent - 1;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[18]) begin
            FinalShiftAmt = 5'd5;
            ResultExponent = PreshiftFinalExponent - 2;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[17]) begin
            FinalShiftAmt = 5'd6;
            ResultExponent = PreshiftFinalExponent - 3;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[16]) begin
            FinalShiftAmt = 5'd7;
            ResultExponent = PreshiftFinalExponent - 4;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[15]) begin
            FinalShiftAmt = 5'd8;  
            ResultExponent = PreshiftFinalExponent - 5;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[14]) begin
            FinalShiftAmt = 5'd9;  
            ResultExponent = PreshiftFinalExponent - 6;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[13]) begin
            FinalShiftAmt = 5'd10;  
            ResultExponent = PreshiftFinalExponent - 7;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[12]) begin
            FinalShiftAmt = 5'd11;  
            ResultExponent = PreshiftFinalExponent - 8;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[11]) begin
            FinalShiftAmt = 5'd12;  
            ResultExponent = PreshiftFinalExponent - 9;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[10]) begin
            FinalShiftAmt = 5'd13;  
            ResultExponent = PreshiftFinalExponent - 10;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[9]) begin
            FinalShiftAmt = 5'd14;  
            ResultExponent = PreshiftFinalExponent - 11;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[8]) begin
            FinalShiftAmt = 5'd15;  
            ResultExponent = PreshiftFinalExponent - 12;
            oVerflow = 1'b0;
        end else if(AccumulateResultMantisa[7]) begin
            FinalShiftAmt = 5'd16;  
            ResultExponent = PreshiftFinalExponent - 13;
            oVerflow = 1'b0;
        end else begin //massive cancelation not supported
            FinalShiftAmt = 5'd17;  
            ResultExponent = PreshiftFinalExponent - 14;
            oVerflow = 1'b0;
        end
    end

    //have to remove the leading 1
    logic [22:-1] ResultMantisa;
    
    assign ResultMantisa = (AccumulateResultMantisa << FinalShiftAmt);

    //if addition overflowed or one of the inputs was inf
    assign MulProduceInf = MultiplicationExponentAddition[5] | (&OpAExponent) | (&OpBExponent);

    logic ArithmaticInvalid;

    always_comb begin
        //Zero times inf
        if (~(|OpAMantisa[9:0]) & ~(|OpBMantisa[9:0]) & ((~(|OpAExponent) & (&OpBExponent)) | (~(|OpBExponent) & (&OpAExponent)))) begin
            //NAN
            result[9:0] = 10'b1000000000;
            result[14:10] = 5'b11111;
            result[15] = 1'b0;
            ArithmaticInvalid = 1'b1;
            SpecialCase = ZeroTimesInf;
        // if any of inputs are NAN
        end else if (((&OpAExponent) & (|OpAMantisa[9:0])) | ((&OpBExponent) & (|OpBMantisa[9:0])) | ((&OpCExponent) & (|OpCMantisa[9:0]))) begin
            //NAN
            result[9:0] = 10'b1000000000;
            result[14:10] = 5'b11111;
            result[15] = 1'b0;
            ArithmaticInvalid = 1'b0;
            SpecialCase = InputsNaN;
        //If multiplcation results in inf
        end else if (MulProduceInf) begin 
            //If either OpC is the inverse inf or nan
            if((&OpCExponent) & (AccumulateSignMismatch | (|OpCMantisa[9:0]))) begin
                //NAN
                result[9:0] = 10'b1000000000;
                result[14:10] = 5'b11111;
                result[15] = 1'b0;
                ArithmaticInvalid = ~(|OpCMantisa[9:0]); // means the reason for entering the case was +inf -inf
                SpecialCase = CalculatedNaN;
            end else begin
                //INF
                result[9:0] = 10'b0;
                result[14:10] = 5'b11111;
                result[15] = MultiplicationResultSign;
                ArithmaticInvalid = 1'b0;
                SpecialCase = MultiplicationOverflow;
            end
        //addition overflow (or op C is inf)
        end else if (oVerflow | ((&OpCExponent) & ~(|OpCMantisa[9:0]))) begin
            //INF
            result[9:0] = 10'b0;
            result[14:10] = 5'b11111;
            result[15] = OpCSign;
            ArithmaticInvalid = 1'b0;
            SpecialCase = AdditionOverflow;
        end else begin
            result[9:0] = ResultMantisa[22:13];
            result[14:10] = ResultExponent;
            result[15] = ResultSign;
            ArithmaticInvalid = 1'b0;
            SpecialCase = None;
        end
    end

    assign RNE  = roundmode == 2'b01;
    assign RZ   = roundmode == 2'b00;
    assign RN   = roundmode == 2'b10;
    assign RP   = roundmode == 2'b11;

    assign Invalid = ((&OpAExponent) & (|OpAMantisa[8:0]) & ~OpAMantisa[9]) | ((&OpBExponent) & (|OpBMantisa[8:0]) & ~OpBMantisa[9]) | ((&OpCExponent) & (|OpCMantisa[8:0]) & ~OpCMantisa[9]) | ArithmaticInvalid;
    assign Overflow = 1'b0;
    assign Underflow = 1'b0;
    assign Inexact = |ResultMantisa[13:7];

    assign flags = {Invalid, Overflow, Underflow, Inexact};

endmodule