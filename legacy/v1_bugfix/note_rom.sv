// Pitch table: note index -> frequency in Hz (equal temperament, A4 = 440, rounded).
// Combinational so the sequencer sees the new pitch in the same cycle it decodes it.
// Also the single source of pitches for the chord ROM.
module note(
    input  [4:0] note_idx,
    output logic [15:0] freq
);
always_comb begin
    case(note_idx)
        5'b00000: freq = 16'd131; // C3
        5'b00001: freq = 16'd139; // C#3
        5'b00010: freq = 16'd147; // D3
        5'b00011: freq = 16'd156; // D#3
        5'b00100: freq = 16'd165; // E3
        5'b00101: freq = 16'd175; // F3
        5'b00110: freq = 16'd185; // F#3
        5'b00111: freq = 16'd196; // G3
        5'b01000: freq = 16'd208; // G#3
        5'b01001: freq = 16'd220; // A3
        5'b01010: freq = 16'd233; // A#3
        5'b01011: freq = 16'd247; // B3
        5'b01100: freq = 16'd262; // C4
        5'b01101: freq = 16'd277; // C#4
        5'b01110: freq = 16'd294; // D4
        5'b01111: freq = 16'd311; // D#4
        5'b10000: freq = 16'd330; // E4
        5'b10001: freq = 16'd349; // F4
        5'b10010: freq = 16'd370; // F#4
        5'b10011: freq = 16'd392; // G4
        5'b10100: freq = 16'd415; // G#4
        5'b10101: freq = 16'd440; // A4
        5'b10110: freq = 16'd466; // A#4
        5'b10111: freq = 16'd494; // B4
        5'b11000: freq = 16'd523; // C5
        5'b11001: freq = 16'd554; // C#5
        5'b11010: freq = 16'd587; // D5
        5'b11011: freq = 16'd622; // D#5
        5'b11100: freq = 16'd659; // E5
        5'b11101: freq = 16'd698; // F5
        5'b11110: freq = 16'd740; // F#5
        5'b11111: freq = 16'd784; // G5
        default:  freq = 16'd0;
    endcase
end
endmodule
