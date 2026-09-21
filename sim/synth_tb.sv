`timescale 1ns/1ps
// Runs a program on synth_top, writes every audio sample to SAMPLE_FILE (for the Python
// checks and WAV export) and checks clock-level invariants in SystemVerilog:
//   - exactly CLK_HZ/FS clocks per sample on average, no X on the audio bus, no engine overrun
//   - the sigma-delta DAC's ones-density matches the PCM stream
// Normally driven by scripts/run.py, which passes the parameters with iverilog -P.
module synth_tb;
    parameter CLK_HZ       = 1_680_000;           // 35 clocks per sample: the minimum for 8 voices, fastest to simulate
    parameter NUM_VOICES   = 8;
    parameter MIX_SHIFT    = 2;
    parameter PROGRAM_FILE = "build/program.hex";
    parameter SAMPLE_FILE  = "build/samples.txt";
    parameter MAX_MS       = 120_000;             // hard stop if the program never halts
    parameter TAIL_MS      = 0;                   // keep running this long after HALT (release tails)

    localparam FS = 48_000;
    localparam real HALF_PERIOD_NS = 1.0e9 / CLK_HZ / 2.0;

    logic clk = 1'b0, rst = 1'b1;
    logic signed [15:0] audio;
    logic audio_valid, dac_out, halted, overrun;

    synth_top #(.CLK_HZ(CLK_HZ), .NUM_VOICES(NUM_VOICES), .MIX_SHIFT(MIX_SHIFT), .PROGRAM_FILE(PROGRAM_FILE)) dut(
        .clk(clk), .rst(rst), .audio(audio), .audio_valid(audio_valid),
        .dac_out(dac_out), .halted(halted), .overrun(overrun));

    always #(HALF_PERIOD_NS) clk = ~clk;

    integer fd;
    longint clocks = 0, samples = 0, x_samples = 0, halt_sample = -1;
    longint first_sample_clock = -1, last_sample_clock = -1;
    longint dac_ones = 0, dac_level_sum = 0;      // DAC check in integers: ones * 65536 should track the level sum
    int     errors = 0;

    always @(posedge clk) if (!rst) begin
        clocks        <= clocks + 1;
        dac_ones      <= dac_ones + dac_out;
        dac_level_sum <= dac_level_sum + (audio + 32768);
        if (audio_valid) begin
            samples <= samples + 1;
            if (first_sample_clock < 0) first_sample_clock <= clocks;
            last_sample_clock <= clocks;
            if ($isunknown(audio)) x_samples <= x_samples + 1;
            $fdisplay(fd, "%0d", audio);
        end
    end

    initial begin
        real clocks_per_sample, dac_err;
        fd = $fopen(SAMPLE_FILE, "w");
        if (fd == 0) begin
            $display("ERROR: cannot open %s", SAMPLE_FILE);
            $finish;
        end
        repeat (5) @(posedge clk);
        rst = 1'b0;

        wait (halted || samples >= longint'(MAX_MS) * FS / 1000);
        if (halted) begin
            halt_sample = samples;
            while (samples < halt_sample + longint'(TAIL_MS) * FS / 1000) @(posedge clk);
        end else begin
            $display("ERROR: program did not halt within %0d ms", MAX_MS);
            errors++;
        end
        @(posedge clk);
        #1;
        $fclose(fd);

        clocks_per_sample = real'(last_sample_clock - first_sample_clock) / real'(samples - 1);
        dac_err           = (real'(dac_ones) * 65536.0 - real'(dac_level_sum)) / (65536.0 * real'(clocks));
        if (overrun) begin
            $display("ERROR: voice engine overran its sample period");
            errors++;
        end
        if (x_samples != 0) begin
            $display("ERROR: %0d audio samples contained X/Z", x_samples);
            errors++;
        end
        if (clocks_per_sample < real'(CLK_HZ) / FS - 0.01 || clocks_per_sample > real'(CLK_HZ) / FS + 0.01) begin
            $display("ERROR: %f clocks per sample, expected %f", clocks_per_sample, real'(CLK_HZ) / FS);
            errors++;
        end
        if (dac_err > 1.0e-4 || dac_err < -1.0e-4) begin
            $display("ERROR: DAC ones-density off by %e of full scale", dac_err);
            errors++;
        end

        $display("STATS samples=%0d clocks=%0d halt_sample=%0d clocks_per_sample=%f dac_density_error=%e errors=%0d",
                 samples, clocks, halt_sample, clocks_per_sample, dac_err, errors);
        if (errors == 0) $display("TB PASS");
        else             $display("TB FAIL");
        $finish;
    end
endmodule
