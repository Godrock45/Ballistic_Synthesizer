module note(
    input [15:0] chord_data,
    output [15:0] freq1,freq2,freq3,freq4,
);
reg [15:0] freq;
always_comb begin
    case(chord_data[13:9])
        5'b00000: freq = 16'd130; // C3
        5'b00001: freq = 16'd138; // C#3
        5'b00010: freq = 16'd146; // D3
        5'b00011: freq = 16'd155; // D#3
        5'b00100: freq = 16'd164; // E3
        5'b00101: freq = 16'd174; // F3
        5'b00110: freq = 16'd185; // F#3
        5'b00111: freq = 16'd196; // G3
        5'b01000: freq = 16'd207; // G#3
        5'b01001: freq = 16'd220; // A3
        5'b01010: freq = 16'd233; // A#3
        5'b01011: freq = 16'd246; // B3
        5'b01100: freq = 16'd261; // C4
        5'b01101: freq = 16'd277; // C#4
        5'b01110: freq = 16'd293; // D4
        5'b01111: freq = 16'd311; // D#4
        5'b10000: freq = 16'd329; // E4
        5'b10001: freq = 16'd349; // F4
        5'b10010: freq = 16'd369; // F#4
        5'b10011: freq = 16'd392; // G4
        5'b10100: freq = 16'd415; // G#4
        5'b10101: freq = 16'd440; // A4
        5'b10110: freq = 16'd466; // A#4
        5'b10111: freq = 16'd493; // B4
        5'b11000: freq = 16'd523; // C5
        5'b11001: freq = 16'd554; // C#5
        5'b11010: freq = 16'd587; // D5
        5'b11011: freq = 16'd622; // D#5
        5'b11100: freq = 16'd659; // E5
        5'b11101: freq = 16'd698; // F5
        5'b11110: freq = 16'd739; // F#5
        5'b11111: freq = 16'd783; // G5
    endcase
end
always_ff @(posedge clk or posedge rst) begin
    if(rst)begin
        freq1<=0;
        freq2<=0;
        freq3<=0;
        freq4<=0;
    end
    else if(chord_data[14])begin
        freq1<=freq;
        freq2<=freq;
        freq3<=freq;
        freq4<=freq;
    end
end
endmodule
