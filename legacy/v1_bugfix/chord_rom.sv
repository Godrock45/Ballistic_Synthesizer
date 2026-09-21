// Chord ROM. chord_data = {root[3:0], minor}: root 0 = C ... 11 = B, bit 0 selects minor.
// 0-23 are the 24 major/minor triads; 24-31 are silent.
// Voicing: freq1 = root (4th oct), freq2 = third, freq3 = fifth, freq4 = root (3rd oct).
// Pitches come from the note table so chords and single notes always agree.
module chord(
    input [4:0] chord_data,
    input ena,
    output logic [15:0] freq1,freq2,freq3,freq4
);
logic [4:0]  root;   // note index of the root in the 3rd octave (0 = C3 ... 11 = B3)
logic        valid;
logic [15:0] f_root4, f_third, f_fifth, f_root3;

assign root  = {1'b0, chord_data[4:1]};
assign valid = ena && (chord_data < 5'd24);

note n_root4(.note_idx(root + 5'd12),                        .freq(f_root4));
note n_third(.note_idx(root + (chord_data[0] ? 5'd15 : 5'd16)), .freq(f_third)); // minor 3rd : major 3rd
note n_fifth(.note_idx(root + 5'd19),                        .freq(f_fifth));
note n_root3(.note_idx(root),                                .freq(f_root3));

always_comb begin
    freq1 = valid ? f_root4 : 16'd0;
    freq2 = valid ? f_third : 16'd0;
    freq3 = valid ? f_fifth : 16'd0;
    freq4 = valid ? f_root3 : 16'd0;
end
endmodule
