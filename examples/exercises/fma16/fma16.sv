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
    logic OpASign, OpBSign, ResultSign;

    assign ResultSign = OpASign ^ OpBSign;

    logic [10:0] OpAMantisa, OpBMantisa;
    logic [21:0] IntermediateResultMantisa;

    assign OpASign = OperandA[15];
    assign OpBSign = OperandB[15];

    assign OpAMantisa = {1'b1, OperandA[9:0]};
    assign OpBMantisa = {1'b1, OperandB[9:0]};

    assign IntermediateResultMantisa = OpAMantisa * OpBMantisa;

    always_comb begin
        if(IntermediateResultMantisa[21]) begin
            result = {ResultSign, 5'd16, IntermediateResultMantisa[20:11]};
        end else begin
            result = {ResultSign, 5'd15, IntermediateResultMantisa[19:10]};
        end
    end

    assign flags = 4'b0;

    


endmodule