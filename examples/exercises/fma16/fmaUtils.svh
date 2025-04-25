//James Kaden Cassidy jkc.cassidy@gmail.com 4/19/25

`define DEBUG

typedef enum logic[5:0] {
        None,
        ZeroTimesInf,
        InputsNaN,
        CalculatedNaN,
        MultiplicationOverflow,
        AdditionOverflow
} specialCase;