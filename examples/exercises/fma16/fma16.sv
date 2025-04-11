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
    logic OpASign, OpBSign, OpCSign, ResultSign;

    assign ResultSign = OpASign ^ OpBSign;

    logic           OpCExponentGreater;
    logic   [10:0]  OpAMantisa, OpBMantisa, OpCMantisa;
    logic   [4:0]   OpAExponent, OpBExponent, OpCExponent, ExpectedFinalExponent, AccumulateOpAShiftAmt, AccumulateOpBShiftAmt;
    logic   [5:0]   IntermendiateResultExponent;
    logic   [21:0]  IntermediateMultiplicationResultMantisa;
    logic   [21:0]  AccumulateOperandA, AccumulateOperandB;
    logic   [22:0]  AccumulateResultMantisa;

    logic   [2:0]   FinalShiftAmt;

    assign OpASign = OperandA[15];
    assign OpBSign = mul ? OperandB[15] : 0;
    assign OpCSign = add ? OperandC[15] : 0;

    assign OpAExponent = OperandA[14:10];
    assign OpBExponent = mul ? OperandB[14:10] : 5'd15;
    assign OpCExponent = add ? OperandC[14:10] : 5'b0;

    assign OpAMantisa = {1'b1, OperandA[9:0]};
    assign OpBMantisa = {1'b1, (mul ? OperandB[9:0] : 10'b0)};
    assign OpCMantisa = add ? {1'b1, OperandC[9:0]} : 11'b0;

    assign IntermediateMultiplicationResultMantisa = OpAMantisa * OpBMantisa;

    assign IntermendiateResultExponent = OpAExponent + OpBExponent - 5'd15;
    logic interm2;
    assign {interm2, AccumulateOpBShiftAmt} = IntermendiateResultExponent[4:0] - OpCExponent;
    assign OpCExponentGreater = interm2 ^ (IntermendiateResultExponent[5]);
    assign AccumulateOpAShiftAmt = (~AccumulateOpBShiftAmt[4:0] + 1);

    assign ExpectedFinalExponent = OpCExponentGreater ? OpCExponent : IntermendiateResultExponent[4:0];

    assign AccumulateOperandA = (IntermediateMultiplicationResultMantisa[21:0]) >> (AccumulateOpAShiftAmt & {(5){OpCExponentGreater}});
    assign AccumulateOperandB = {1'b0, OpCMantisa, 10'b0} >> (AccumulateOpBShiftAmt & {(5){~OpCExponentGreater}});

    assign AccumulateResultMantisa = AccumulateOperandA + AccumulateOperandB;

    //currently only supports positive operands
    assign result[15] = ResultSign;

    always_comb begin
        if (AccumulateResultMantisa[22]) begin
            FinalShiftAmt = 3'd1;
            result[14:10] = ExpectedFinalExponent + 2;
        end else if(AccumulateResultMantisa[21]) begin
            FinalShiftAmt = 3'd2;
            result[14:10] = ExpectedFinalExponent + 1;
        end else if(AccumulateResultMantisa[20]) begin
            FinalShiftAmt = 3'd3;
            result[14:10] = ExpectedFinalExponent;
        end else begin //massive cancelation not supported
            FinalShiftAmt = 3'd0;
            result[14:10] = ExpectedFinalExponent;
        end
    end


    //have to remove the leading 1
    logic [22:0] interm;
    assign interm = (AccumulateResultMantisa << FinalShiftAmt);
    assign result[9:0] = interm[22:13]; //[12:3]

    assign flags = 4'b0;

endmodule