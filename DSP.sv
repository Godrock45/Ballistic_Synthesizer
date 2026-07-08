module dsp(
    input clk,
    input rst,
    input [15:0] wave_out,
    input [4:0] effect_op,
    output logic [15:0] dsp_out
);
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        dsp_out <= 16'b0;
    end else begin
        case (effect_op)
            5'b00000: dsp_out <= wave_out; // No effect
            5'b00001: dsp_out <= wave_out + 16'h1000; // Simple boost
            5'b00010: dsp_out <= wave_out - 16'h1000; // Simple cut
            5'b00011: dsp_out <= wave_out << 1; // Simple distortion
            5'b00100: dsp_out <= wave_out >> 1; // Simple compression
            default: dsp_out <= wave_out; // Default to no effect
        endcase
    end 
end

endmodule