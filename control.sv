module control(
    input clk,
    input rst,
    output [1:0]oscillator_select,
    
);
reg [16:0] IR;
reg [8:0] PC;
reg [1:0] voice_select;
reg [1:0] state,next_state;
reg [4:0] opcode;
reg chords_notes;
reg voice_effects;
reg [16:0] freq1,freq2,freq3,freq4;
reg [16:0] ampl1,ampl2,ampl3,ampl4;
reg [2:0] wave_type1,wave_type2,wave_type3,wave_type4;
parameter Fetch= 2'b00, Decode= 2'b01, Execute= 2'b10, WaveOut= 2'b11;

always_comb begin : 
    case(state)
        Fetch:begin
            next_state= Decode;
        end
        Decode:begin
            next_state= Execute;
        end
        Execute:begin
            next_state= WaveOut;
        end
    endcase
end

always_comb begin
    case(IR[15:14])
        2'b00:begin
            chord tf(.chord_data(IR), .freq1(freq1), .freq2(freq2), .freq3(freq3), .freq4(freq4));
        end

        2'b01:begin // play notes
            note ch(.chord_data(IR), .freq1(freq1), .freq2(freq2), .freq3(freq3), .freq4(freq4));
        end
        2'b10:begin // play effect
            effect ef(.effect_data(IR), .freq1(freq1), .freq2(freq2), .freq3(freq3), .freq4(freq4));
        end
        default:begin
            freq1=16'd0;
            freq2=16'd0;
            freq3=16'd0;
            freq4=16'd0;
        end
    endcase
end


always_ff(posedge clk or posedge rst) begin
    if(rst)begin
        PC<=0;
        state<=FETCH;
    end
    else begin
        state<=nextstate;
    end
    if(state==FETCH)begin
        PC<=PC+1;
    end
    else if(state==DECODE)begin
        chord_notes<=~IR[15];
        voice_effects<=IR[15];
        opcode<=IR[15:11];
    end
    else if(state==EXECUTE)begin
        if(chord_notes)begin
            voice_select<=2'b00; //chord
        end
        else if(voice_effects)begin
            voice_select<=2'b01; //effect
        end
        else begin
            voice_select<=2'b10; //single note
        end
end
end









endmodule