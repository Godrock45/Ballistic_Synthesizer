module wavegen(
    input clk,
    input rst,
    input [4:0] effect_op,
    input [15:0] freq1,
    input [15:0] ampl,
    input [1:0] wave_type, 
    output reg [15:0] wave_out
);
logic [31:0] phase_acc;
logic [15:0] raw_sample;
logic [15:0] sine_lut_value;
sinLUT(.addr(phase_acc[31:16]), .sine_value(sine_lut_value));
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        phase_acc <= 0;
        raw_sample <= 0;
    end else begin
        phase_acc <= phase_acc + freq1; // Increment phase accumulator by frequency
        case (wave_type)
            2'b00: raw_sample <= (phase_acc[31]) ? 16'hFFFF : 16'h0000; // Square wave
            2'b01: raw_sample <= phase_acc[31:16]; // Sawtooth wave
            2'b10: raw_sample <= (phase_acc[31]) ? (~phase_acc[30:15]):(phase_acc[30:15]); // Triangle wave
            2'b11: raw_sample <= sine_lut_value; // Sine wave
            default: raw_sample <= 0;
        endcase
    end
end
always_comb begin 
    wave_out = (raw_sample * ampl) >> 16; // Scale by amplitude 
end


endmodule