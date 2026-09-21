`timescale 1ns/1ps
// Self-checking testbench: runs the demo program in instruct_rom and checks pitches, timing and audio.
//   iverilog -g2012 -o synth_tb.vvp synth_tb.sv control.sv instruct_rom.sv note_rom.sv chord_rom.sv oscillator.sv sine_LUT.sv DSP.sv mixer.sv
//   vvp synth_tb.vvp
module synth_tb;
    localparam int CLK_DIV        = 4;   // short sample period for speed; audio checks count sample ticks, so results match hardware
    localparam int TICKS_PER_UNIT = 64;  // sample ticks per WAIT unit (65,536 / 1,024)

    logic clk = 1'b0, rst = 1'b1;
    logic signed [15:0] audio_out;
    logic sample_tick;
    int errors = 0;
    int x_samples = 0;

    control #(.CLK_DIV(CLK_DIV)) dut(.clk(clk), .rst(rst), .audio_out(audio_out), .sample_tick(sample_tick));

    // Standalone effect stage for saturation checks
    logic signed [15:0] dsp_in = 16'sd0, dsp_res;
    logic [4:0] dsp_op = 5'd0;
    dsp u_dsp(.clk(clk), .rst(rst), .wave_out(dsp_in), .effect_op(dsp_op), .dsp_out(dsp_res));

    always #10 clk = ~clk; // 50 MHz

    always @(negedge clk) if (!rst && sample_tick && $isunknown(audio_out)) x_samples++;

    task automatic expect_eq(input string what, input logic signed [31:0] got, input logic signed [31:0] exp);
        if (got !== exp) begin
            $display("FAIL  %s: got %0d, expected %0d", what, got, exp);
            errors++;
        end else
            $display("ok    %s = %0d", what, got);
    endtask

    task automatic expect_range(input string what, input int got, input int lo, input int hi);
        if (got < lo || got > hi) begin
            $display("FAIL  %s: got %0d, expected %0d..%0d", what, got, lo, hi);
            errors++;
        end else
            $display("ok    %s = %0d (expected %0d..%0d)", what, got, lo, hi);
    endtask

    task automatic expect_freqs(input string what, input int f1, input int f2, input int f3, input int f4);
        if (dut.freq1 !== f1 || dut.freq2 !== f2 || dut.freq3 !== f3 || dut.freq4 !== f4) begin
            $display("FAIL  %s: freqs %0d %0d %0d %0d, expected %0d %0d %0d %0d",
                     what, dut.freq1, dut.freq2, dut.freq3, dut.freq4, f1, f2, f3, f4);
            errors++;
        end else
            $display("ok    %s: freqs %0d %0d %0d %0d", what, f1, f2, f3, f4);
    endtask

    task automatic dsp_check(input logic [4:0] op, input int in, input int exp);
        dsp_op = op;
        dsp_in = in;
        @(negedge clk);
        if (dsp_res !== exp) begin
            $display("FAIL  dsp op=%0d in=%0d: got %0d, expected %0d", op, in, dsp_res, exp);
            errors++;
        end else
            $display("ok    dsp op=%0d in=%0d -> %0d", op, in, exp);
    endtask

    // Block until instruction `addr` has executed (FSM in WaveOut, PC one past it).
    task automatic run_to(input int addr);
        @(negedge clk);
        while (!(dut.state == 2'b11 && dut.PC == addr + 1)) @(negedge clk);
    endtask

    int ticks, crossings, peak, n, mean;
    longint sum;
    logic signed [15:0] prev;

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // ROM and LUT contents fully defined
        n = 0;
        for (int i = 0; i < 256; i++) begin
            if ($isunknown(dut.ir.rom[i]))       n++;
            if ($isunknown(dut.w1.lut.lut[i]))   n++;
        end
        expect_eq("undefined ROM/LUT entries", n, 0);
        expect_eq("sine lut[0]", dut.w1.lut.lut[0], 32'h7FFF);

        // Effects saturate instead of wrapping
        dsp_check(5'b00000,  12345,  12345);
        dsp_check(5'b00001,  20000,  32767);
        dsp_check(5'b00001, -20000, -32768);
        dsp_check(5'b00010, -20000, -10000);
        dsp_check(5'b00011,   1000,   4000);
        dsp_check(5'b00011,  10000,  32767);
        dsp_check(5'b00100,   8000,   8000);
        dsp_check(5'b00100,  32767,  20479);
        dsp_check(5'b00100, -32768, -20480);

        // WAVE instructions set volume and waveform per voice
        run_to(3);
        expect_eq("ampl1..4 all 0x8000", {dut.ampl1, dut.ampl2, dut.ampl3, dut.ampl4} === {4{16'h8000}}, 1);
        expect_eq("wave_type1..4 all sine", {dut.wave_type1, dut.wave_type2, dut.wave_type3, dut.wave_type4} === 8'hFF, 1);

        // Chords set all four voices
        run_to(4);  expect_freqs("C major chord", 262, 330, 392, 131);

        // WAIT 512 holds for 512 units of 64 sample ticks
        run_to(5);
        ticks = 0;
        while (dut.state == 2'b11 && dut.PC == 6) begin
            if (sample_tick) ticks++;
            @(negedge clk);
        end
        expect_range("WAIT 512 length in sample ticks", ticks, 511*TICKS_PER_UNIT + 1, 512*TICKS_PER_UNIT);

        run_to(6);  expect_freqs("A minor chord", 440, 523, 659, 220);
        run_to(8);  expect_freqs("F major chord", 349, 440, 523, 175);
        run_to(10); expect_freqs("G major chord", 392, 494, 587, 196);

        // Notes change only the selected voice, and take effect on their own instruction
        run_to(15); expect_freqs("note C4 on voice 0", 262, 494, 587, 196);

        // Voice 0 alone: check pitch, level and DC at the mixer output
        run_to(16);
        crossings = 0; peak = 0; sum = 0; n = 0; prev = 16'sd0;
        while (dut.state == 2'b11 && dut.PC == 17) begin
            if (sample_tick) begin
                if (prev < 0 && audio_out >= 0) crossings++;
                if (audio_out > peak) peak = audio_out;
                sum += audio_out;
                n++;
                prev = audio_out;
            end
            @(negedge clk);
        end
        mean = sum / n;
        expect_range("C4 upward zero crossings in 0.25 s", crossings, 64, 67);
        expect_range("C4 peak at mixer output", peak, 4000, 4096);
        expect_range("C4 mean (DC offset)", mean, -64, 64);

        run_to(17); expect_freqs("note E4 on voice 0", 330, 494, 587, 196);
        run_to(19); expect_freqs("note G4 on voice 0", 392, 494, 587, 196);
        run_to(21); expect_freqs("note C5 on voice 0", 523, 494, 587, 196);

        // All voices muted -> exact digital silence
        run_to(24);
        n = 0;
        while (dut.state == 2'b11 && dut.PC == 25) begin
            if (sample_tick && audio_out !== 16'sd0) n++;
            @(negedge clk);
        end
        expect_eq("non-zero samples during rest", n, 0);

        // Runs through the no-op slots and loops back to the start
        run_to(4);  expect_freqs("C major chord after loop", 262, 330, 392, 131);

        expect_eq("X samples on audio_out", x_samples, 0);
        if (errors == 0) $display("PASS: all checks passed");
        else             $display("FAILED: %0d check(s)", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
