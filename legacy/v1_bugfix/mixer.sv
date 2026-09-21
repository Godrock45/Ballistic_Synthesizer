module mixer(
    input signed [15:0] wave_out1,wave_out2,wave_out3,wave_out4,
    output logic signed [15:0] mixed_out
);
logic signed [17:0] sum;
always_comb begin
    sum=wave_out1+wave_out2+wave_out3+wave_out4;
end
assign mixed_out= sum[17:2]; // sum / 4 (arithmetic shift)
endmodule
