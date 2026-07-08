module instruct_rom(
    input [7:0] addr,
    output reg [16:0] data
);
    reg [16:0] rom [0:255];
    initial begin
     rom[0]=17'b00000000000000000; // rest
     rom[1]=17'b01000010000000001; // c4
    end
    always_comb data = rom[addr];




endmodule