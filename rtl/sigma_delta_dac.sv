// First-order sigma-delta DAC. The density of ones on dac_out tracks the sample value,
// so an RC low-pass on the pin (e.g. 1 kOhm + 10 nF) recovers the analog audio.
module sigma_delta_dac(
    input  logic               clk,
    input  logic               rst,
    input  logic signed [15:0] sample,
    output logic               dac_out
);
    logic [16:0] acc;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            acc     <= 17'd0;
            dac_out <= 1'b0;
        end else begin
            acc     <= {1'b0, acc[15:0]} + {1'b0, sample ^ 16'h8000};  // signed -> offset binary
            dac_out <= acc[16];
        end
    end
endmodule
