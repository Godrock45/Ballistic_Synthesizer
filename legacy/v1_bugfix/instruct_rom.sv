// Instruction ROM. 17-bit instructions (x = don't care):
//
//   WAIT   : [16]=1, [15:0]=len                        hold for len/1024 s (1024 = 1 s)
//   NOTE   : [16]=0 [15]=1 [14]=0 [12:11]=voice [10:6]=note     set one voice's pitch
//   CHORD  : [16]=0 [15]=1 [14]=1 [10:6]=chord                  set all four voices' pitches
//   WAVE   : [16]=0 [15]=0 [13]=1 [12:11]=voice [10:9]=wave [8:1]=volume
//   EFFECT : [16]=0 [15]=0 [13]=0 [12:11]=voice [10:6]=effect
//
// Build instructions with the op_* functions below rather than by hand, so the encoding
// can't drift from the comment next to it.
module instruct_rom(
    input [7:0] addr,
    output logic [16:0] data
);
    localparam [1:0]  SQUARE = 2'd0, SAW = 2'd1, TRIANGLE = 2'd2, SINE = 2'd3;
    localparam [4:0]  C4 = 5'd12, E4 = 5'd16, G4 = 5'd19, C5 = 5'd24;             // note_rom indices
    localparam [4:0]  C_MAJ = 5'd0, F_MAJ = 5'd10, G_MAJ = 5'd14, A_MIN = 5'd19;  // chord_rom indices
    localparam [15:0] HALF_SEC = 16'd512, QUARTER_SEC = 16'd256;

    function automatic [16:0] op_wait(input logic [15:0] len);
        op_wait = {1'b1, len};
    endfunction
    function automatic [16:0] op_note(input logic [1:0] voice, input logic [4:0] n);
        op_note = {3'b010, 1'b0, voice, n, 6'b0};
    endfunction
    function automatic [16:0] op_chord(input logic [4:0] c);
        op_chord = {3'b011, 1'b0, 2'b00, c, 6'b0};
    endfunction
    function automatic [16:0] op_wave(input logic [1:0] voice, input logic [1:0] wave, input logic [7:0] vol);
        op_wave = {3'b000, 1'b1, voice, wave, vol, 1'b0};
    endfunction
    function automatic [16:0] op_effect(input logic [1:0] voice, input logic [4:0] effect);
        op_effect = {3'b000, 1'b0, voice, effect, 6'b0};
    endfunction

    logic [16:0] rom [0:255];
    initial begin
        for (int i = 0; i < 256; i++) rom[i] = op_wait(16'd0); // unused slots are no-ops

        // Voice setup: all four voices sine at ~50% volume
        rom[0]  = op_wave(2'd0, SINE, 8'd128);
        rom[1]  = op_wave(2'd1, SINE, 8'd128);
        rom[2]  = op_wave(2'd2, SINE, 8'd128);
        rom[3]  = op_wave(2'd3, SINE, 8'd128);
        // Chord progression C - Am - F - G, half a second each
        rom[4]  = op_chord(C_MAJ);  rom[5]  = op_wait(HALF_SEC);
        rom[6]  = op_chord(A_MIN);  rom[7]  = op_wait(HALF_SEC);
        rom[8]  = op_chord(F_MAJ);  rom[9]  = op_wait(HALF_SEC);
        rom[10] = op_chord(G_MAJ);  rom[11] = op_wait(HALF_SEC);
        // Arpeggio on voice 0 alone: mute voices 1-3, then C4 E4 G4 C5
        rom[12] = op_wave(2'd1, SINE, 8'd0);
        rom[13] = op_wave(2'd2, SINE, 8'd0);
        rom[14] = op_wave(2'd3, SINE, 8'd0);
        rom[15] = op_note(2'd0, C4); rom[16] = op_wait(QUARTER_SEC);
        rom[17] = op_note(2'd0, E4); rom[18] = op_wait(QUARTER_SEC);
        rom[19] = op_note(2'd0, G4); rom[20] = op_wait(QUARTER_SEC);
        rom[21] = op_note(2'd0, C5); rom[22] = op_wait(QUARTER_SEC);
        // Rest: mute voice 0 for half a second, then the program loops
        rom[23] = op_wave(2'd0, SINE, 8'd0); rom[24] = op_wait(HALF_SEC);
    end
    assign data = rom[addr];

endmodule
