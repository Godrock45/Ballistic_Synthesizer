module control(
    input clk,
    input rst
);
logic [15:0] IR_wire,IR_reg;
logic [7:0] PC;
logic [1:0] voice_select_d,voice_select_r;
logic [1:0] state,next_state;
logic [16:0] c_freq1,c_freq2,c_freq3,c_freq4,freq1,freq2,freq3,freq4,n_freq1,n_freq2,n_freq3,n_freq4;
logic [16:0] ampl1,ampl2,ampl3,ampl4;
logic [1:0] wave_type1,wave_type2,wave_type3,wave_type4;
parameter Fetch= 2'b00, Decode= 2'b01, Execute= 2'b10, WaveOut= 2'b11;
logic music_mode_d,music_mode_r,effect_mode_d,effect_mode_r,wave_mode_d,wave_mode_r;
logic cho_or_no_d,cho_or_no_r;
logic [4:0] cho_data_d,cho_data_r;
logic [15:0] wave_out1,wave_out2,wave_out3,wave_out4;
logic [15:0] ampl_d,ampl_r;
logic [1:0]wave_type_d,wave_type_r;
logic [4:0] effect_op_d,effect_op_r;
logic [4:0] effect_op_1, effect_op_2, effect_op_3, effect_op_4;
logic exec_en;

instruct_rom ir(.addr(PC), .data(IR_wire));
note ch(.chord_data(cho_data_r),.ena(~cho_or_no_r), .freq1(n_freq1), .freq2(n_freq2), .freq3(n_freq3), .freq4(n_freq4));
chord tf(.chord_data(cho_data_r),.ena(cho_or_no_r), .freq1(c_freq1), .freq2(c_freq2), .freq3(c_freq3), .freq4(c_freq4));
wavegen w1(.clk(clk),.rst(rst),.effect_op(effect_op_1),.freq1(freq1),.ampl(ampl1),.wave_type(wave_type1),.wave_out(wave_out1));
wavegen w2(.clk(clk),.rst(rst),.effect_op(effect_op_2),.freq1(freq2),.ampl(ampl2),.wave_type(wave_type2),.wave_out(wave_out2));
wavegen w3(.clk(clk),.rst(rst),.effect_op(effect_op_3),.freq1(freq3),.ampl(ampl3),.wave_type(wave_type3),.wave_out(wave_out3));
wavegen w4(.clk(clk),.rst(rst),.effect_op(effect_op_4),.freq1(freq4),.ampl(ampl4),.wave_type(wave_type4),.wave_out(wave_out4));
always_comb begin
    music_mode_d=IR_reg[15];
    wave_mode_d=IR_reg[13]&&~IR_reg[15];
    effect_mode_d=~IR_reg[13]&&~IR_reg[15];
    cho_or_no_d=1'b0;
    cho_data_d=5'b0;
    voice_select_d=2'b0;
    wave_type_d=2'b0;
    ampl_d=16'b0;
    effect_op_d=5'b0;
    if(music_mode_d)begin
        cho_or_no_d=IR_reg[14];
        cho_data_d=IR_reg[10:6];
        voice_select_d=IR_reg[12:11];
    end
    else if(wave_mode_d)begin
        wave_type_d=IR_reg[10:9];
        ampl_d={IR_reg[8:1],8'b0};
        voice_select_d=IR_reg[12:11]; 
    end
    else if(effect_mode_d)begin
        effect_op_d=IR_reg[10:6];
        voice_select_d=IR_reg[12:11];
    end
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
        WaveOut:begin
            next_state= Fetch;
        end
    endcase
end
assign exec_en=(state==Execute);

always_ff @(posedge clk or posedge rst) begin
    if(rst)begin
        PC<=0;
        state<=Fetch;
        IR_reg<=0;
        // Decode Registers
        music_mode_r<=0; wave_mode_r<=0;
        effect_mode_r<=0; cho_or_no_r<=0;
        cho_data_r<=0; voice_select_r<=0;
        wave_type_r<=0; ampl_r<=0; effect_op_1<=0;
         effect_op_2<=0; effect_op_3<=0; effect_op_4<=0;
        //Oscillator Registers
        freq1<=0;freq2<=0;freq3<=0;freq4<=0;
        ampl1<=0;ampl2<=0;ampl3<=0;ampl4<=0;
    end
    else begin
        state<=next_state;
        if(state==Fetch)begin
            IR_reg<=IR_wire;
            PC<=PC+1;
        end
        else if(state==Decode)begin
            music_mode_r<=music_mode_d;
            wave_mode_r<=wave_mode_d;
            effect_mode_r<=effect_mode_d;
            cho_or_no_r<=cho_or_no_d;
            cho_data_r<=cho_data_d;
            voice_select_r<=voice_select_d;
            wave_type_r<=wave_type_d;
            ampl_r<=ampl_d;
            effect_op_r<=effect_op_d;
        end
        else if(state==Execute)begin
            if(music_mode_r)begin
                if(cho_or_no_r)begin
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
            else if(wave_mode_r)begin
                case(voice_select_r)
                    2'b00:begin
                        wave_type1<=wave_type_r;
                        ampl1<=ampl_r;
                    end
                    2'b01:begin
                        wave_type2<=wave_type_r;
                        ampl2<=ampl_r;
                    end
                    2'b10:begin
                        wave_type3<=wave_type_r;
                        ampl3<=ampl_r;
                    end
                    2'b11:begin
                        wave_type4<=wave_type_r;
                        ampl4<=ampl_r;
                    end
                endcase 
            end
            else if(effect_mode_r)begin
                case(voice_select_r)
                    2'b00: effect_op1<=effect_op_r;
                    2'b01: effect_op2<=effect_op_r;
                    2'b10: effect_op3<=effect_op_r;
                    2'b11: effect_op4<=effect_op_r;
                endcase
            end
        end
    end
end
endmodule