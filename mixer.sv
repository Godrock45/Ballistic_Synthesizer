module mixer(
    input [15:0] wave_out1,wave_out2,wave_out3,wave_out4,
    output logic [15:0] mixed_out
);
logic [17:0]sum;
always_comb begin 
    sum=18'(wave_out1)+18'(wave_out2)+18'(wave_out3)+18'(wave_out4);
end
assign mixed_out= sum >> 2;
endmodule