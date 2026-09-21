// Ballistic Synth top level.
//
//   sample_clock --sample_tick--> voice_engine --audio--> sigma_delta_dac --> dac_out pin
//        |                             ^
//        +--ms_tick--> sequencer --cmd-+   (program ROM loaded from PROGRAM_FILE)
module synth_top #(
    parameter CLK_HZ       = 50_000_000,
    parameter NUM_VOICES   = 8,
    parameter MIX_SHIFT    = 2,
    parameter PROGRAM_FILE = "build/program.hex"
)(
    input  logic               clk,
    input  logic               rst,          // active high, asynchronous
    output logic signed [15:0] audio,        // 48 kHz PCM
    output logic               audio_valid,  // one-clock strobe per new sample
    output logic               dac_out,      // 1-bit sigma-delta audio; RC low-pass this pin
    output logic               halted,       // program reached HALT
    output logic               overrun       // sticky: clock too slow for NUM_VOICES
);
    localparam FS = 48_000;   // the generated note and envelope tables assume this rate

    logic                  sample_tick, ms_tick;
    logic                  cmd_valid;
    logic [3:0]            cmd_op;
    logic [2:0]            cmd_voice;
    logic [16:0]           cmd_arg;
    logic [9:0]            pc;
    logic [NUM_VOICES-1:0] voice_active;

`ifndef SYNTHESIS
    initial if (CLK_HZ / FS < 4 * NUM_VOICES + 3)
        $error("CLK_HZ=%0d gives %0d clocks per sample; the voice engine needs %0d",
               CLK_HZ, CLK_HZ / FS, 4 * NUM_VOICES + 3);
`endif

    sample_clock #(.CLK_HZ(CLK_HZ), .FS(FS)) clocks(
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .ms_tick(ms_tick));

    sequencer #(.PROGRAM_FILE(PROGRAM_FILE)) seq(
        .clk(clk), .rst(rst), .ms_tick(ms_tick),
        .cmd_valid(cmd_valid), .cmd_op(cmd_op), .cmd_voice(cmd_voice), .cmd_arg(cmd_arg),
        .pc(pc), .halted(halted));

    voice_engine #(.NUM_VOICES(NUM_VOICES), .MIX_SHIFT(MIX_SHIFT)) engine(
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .cmd_valid(cmd_valid), .cmd_op(cmd_op), .cmd_voice(cmd_voice), .cmd_arg(cmd_arg),
        .sample_out(audio), .sample_valid(audio_valid), .overrun(overrun), .voice_active(voice_active));

    sigma_delta_dac dac(.clk(clk), .rst(rst), .sample(audio), .dac_out(dac_out));
endmodule
