module wavegen(
    input clk,
    input rst,
    input sample_tick,
    input [15:0] freq1,
    input [15:0] ampl,
    input [1:0] wave_type,
    output logic signed [15:0] wave_out
);
logic [15:0] phase_acc;
logic signed [15:0] raw_sample; // signed, centred on 0, so volume scaling can't shift the DC level
logic [15:0] sine_lut_value;
logic signed [31:0] scaled;
sineLUT lut(.addr(phase_acc[15:8]), .sine_value(sine_lut_value));
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        phase_acc<=0;
        raw_sample<=0;
    end else if (sample_tick) begin
        phase_acc<=phase_acc+freq1; // freq is now interpreted as Hz directly (sample_tick @ 65,536 Hz, 16-bit acc)
        // "^ 16'h8000" converts offset-binary (0..FFFF, midpoint 8000) to two's complement.
        case (wave_type)
            2'b00: raw_sample<=(phase_acc[15]) ? 16'sd32767 : -16'sd32767; // Square wave
            2'b01: raw_sample<=phase_acc ^ 16'h8000; // Sawtooth wave
            2'b10: raw_sample<=((phase_acc[15]) ? {~phase_acc[14:0], 1'b0} : {phase_acc[14:0], 1'b0}) ^ 16'h8000; // Triangle wave
            2'b11: raw_sample<=sine_lut_value ^ 16'h8000; // Sine wave
            default: raw_sample<=0;
        endcase
    end
end
always_comb begin
    scaled   = raw_sample * $signed({1'b0, ampl}); // Scale by amplitude (ampl is unsigned 0..FFFF)
    wave_out = scaled[31:16];
end


endmodule
