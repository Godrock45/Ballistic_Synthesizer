// Audio time base: a one-clock sample strobe at FS and a 1 ms strobe for the sequencer.
// Uses a fractional (phase-accumulator) divider, so any CLK_HZ gives an exact average FS.
module sample_clock #(
    parameter CLK_HZ = 50_000_000,
    parameter FS     = 48_000        // must be a multiple of 1000
)(
    input  logic clk,
    input  logic rst,
    output logic sample_tick,        // FS pulses per second
    output logic ms_tick             // 1000 pulses per second, coincident with a sample_tick
);
    logic [31:0] acc;
    logic [15:0] ms_div;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            acc         <= 32'd0;
            ms_div      <= 16'd0;
            sample_tick <= 1'b0;
            ms_tick     <= 1'b0;
        end else begin
            sample_tick <= 1'b0;
            ms_tick     <= 1'b0;
            if (acc + FS >= CLK_HZ) begin
                acc         <= acc + FS - CLK_HZ;
                sample_tick <= 1'b1;
                if (ms_div == FS / 1000 - 1) begin
                    ms_div  <= 16'd0;
                    ms_tick <= 1'b1;
                end else begin
                    ms_div  <= ms_div + 16'd1;
                end
            end else begin
                acc <= acc + FS;
            end
        end
    end
endmodule
