module control(
    input clk,
    input rst
);
logic [15:0] IR;
logic [8:0] PC;
logic [1:0] voice_select;
logic [1:0] state,next_state;
logic [16:0] c_freq1,c_freq2,c_freq3,c_freq4,freq1,freq2,freq3,freq4,n_freq1,n_freq2,n_freq3,n_freq4;
logic [16:0] ampl1,ampl2,ampl3,ampl4;
logic [2:0] wave_type1,wave_type2,wave_type3,wave_type4;
parameter Fetch= 2'b00, Decode= 2'b01, Execute= 2'b10, WaveOut= 2'b11;
logic music_mode,effect_mode,wave_mode;
logic cho_or_no;
logic [4:0] cho_data;
logic [15:0] wave_out1,wave_out2,wave_out3,wave_out4;
logic [15:0] ampl;
logic [1:0]wave_type;

instruct_rom ir(.addr(PC), .data(IR));
note ch(.chord_data(cho_data),.ena(~cho_or_no), .freq1(n_freq1), .freq2(n_freq2), .freq3(n_freq3), .freq4(n_freq4));
chord tf(.chord_data(cho_data),.ena(cho_or_no), .freq1(c_freq1), .freq2(c_freq2), .freq3(c_freq3), .freq4(c_freq4));
always_comb begin
    music_mode=IR[15];
    wave_mode=IR[13]&&~IR[15];
    effect_mode=~IR[13]&&~IR[15];
end
always_comb begin 
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



always_ff @(posedge clk or posedge rst) begin
    if(rst)begin
        PC<=0;
        state<=Fetch;
    end
    else begin
        state<=next_state;
    if(state==Fetch)begin
        PC<=PC+1;
    end
    else if(state==Decode)begin
        if(music_mode)begin
            cho_data<=IR[10:6];
            cho_or_no<=IR[14];
            voice_select<=IR[12:11];
        end
        else if(wave_mode)begin
            wave_type<=IR[10:9];
            ampl<={IR[8:1],8'b0};
            voice_select<=IR[12:11]; 
        end
        else if(effect_mode)begin
            voice_select<=IR[12:11];
        end
        
    end
    else if(state==Execute)begin
        if(music_mode)begin
            if(cho_or_no)begin
                freq1<=c_freq1;
                freq2<=c_freq2;
                freq3<=c_freq3;
                freq4<=c_freq4;
            end
            else begin
                freq1<=n_freq1;
                freq2<=n_freq2;
                freq3<=n_freq3;
                freq4<=n_freq4;
            end
        end
        else if(wave_mode)begin
           ampl1 
        end
    end
    end
       
end

endmodule