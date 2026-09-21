// Per-voice effect stage. Signed samples; every effect saturates instead of wrapping.
module dsp(
    input clk,
    input rst,
    input signed [15:0] wave_out,
    input [4:0] effect_op,
    output logic signed [15:0] dsp_out
);
logic signed [17:0] x, y; // headroom for x4 gain before saturating

function automatic signed [15:0] sat16(input signed [17:0] v);
    if (v > 18'sd32767)       sat16 = 16'sh7FFF;
    else if (v < -18'sd32768) sat16 = 16'sh8000;
    else                      sat16 = v[15:0];
endfunction

always_comb begin
    x = wave_out;
    case (effect_op)
        5'b00000: y = x;       // No effect
        5'b00001: y = x <<< 1; // Boost: x2 gain
        5'b00010: y = x >>> 1; // Cut: x0.5 gain
        5'b00011: y = x <<< 2; // Distortion: x4 gain into hard clipping
        5'b00100: begin        // Compression: static 4:1 above half scale (no envelope follower)
            if (x > 18'sd16384)       y = 18'sd16384 + ((x - 18'sd16384) >>> 2);
            else if (x < -18'sd16384) y = -18'sd16384 + ((x + 18'sd16384) >>> 2);
            else                      y = x;
        end
        default:  y = x;       // Default to no effect
    endcase
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        dsp_out <= 16'sd0;
    end else begin
        dsp_out <= sat16(y);
    end
end

endmodule
