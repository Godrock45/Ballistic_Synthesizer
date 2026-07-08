module wavegen(
    input clk,
    input rst,
    input sample_tick,
    input [4:0] effect_op,
    input [15:0] freq1,
    input [15:0] ampl,
    input [1:0] wave_type,
    output reg [15:0] wave_out
);
logic [15:0] phase_acc;
logic [15:0] raw_sample;
logic [15:0] sine_lut_value;
sineLUT lut(.addr(phase_acc[15:8]), .sine_value(sine_lut_value));
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        phase_acc<=0;
        raw_sample<=0;
    end else if (sample_tick) begin
        phase_acc<=phase_acc+freq1; // freq is now interpreted as Hz directly (sample_tick @ 65,536 Hz, 16-bit acc)
        case (wave_type)
            2'b00: raw_sample<=(phase_acc[15]) ? 16'hFFFF : 16'h0000; // Square wave
            2'b01: raw_sample<=phase_acc; // Sawtooth wave
            2'b10: raw_sample<=(phase_acc[15]) ? {~phase_acc[14:0], 1'b0} : {phase_acc[14:0], 1'b0}; // Triangle wave
            2'b11: raw_sample<=sine_lut_value; // Sine wave
            default: raw_sample<=0;
        endcase
    end
end
always_comb begin  
    wave_out = (32'(raw_sample) * 32'(ampl))>>16; // Scale by amplitude 
end


endmodule