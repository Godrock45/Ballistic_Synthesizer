module control #(
    parameter CLK_DIV = 763  // master_clk_hz / 65,536. 50 MHz -> 763, 100 MHz -> 1526, 27 MHz -> 412.
)(
    input clk,
    input rst,
    output logic signed [15:0] audio_out,   // mixed audio, signed 16-bit; latch it on sample_tick
    output logic               sample_tick  // ~65,536 Hz strobe, one clk wide
);
logic [15:0] tick_count;
logic [5:0]  wait_div;
logic        wait_tick;
logic [15:0] wait_count;
logic music_mode_d,music_mode_r,effect_mode_d,effect_mode_r,wave_mode_d,wave_mode_r,wait_mode_d,wait_mode_r;
logic cho_or_no_d,cho_or_no_r;
logic [7:0] PC;
logic [1:0] voice_select_d,voice_select_r;
logic [1:0] state,next_state;
logic [1:0] wave_type1,wave_type2,wave_type3,wave_type4;
logic [1:0]wave_type_d,wave_type_r;
logic [4:0] effect_op_d,effect_op_r;
logic [4:0] effect_op_1, effect_op_2, effect_op_3, effect_op_4;
logic [4:0] cho_data_d,cho_data_r;
logic [15:0] c_freq1,c_freq2,c_freq3,c_freq4,freq1,freq2,freq3,freq4,n_freq;
logic [15:0] ampl1,ampl2,ampl3,ampl4;
logic [15:0] ampl_d,ampl_r;
logic [15:0] wait_len_d,wait_len_r;
logic signed [15:0] wave_out1,wave_out2,wave_out3,wave_out4;
logic signed [15:0] dsp_out1,dsp_out2,dsp_out3,dsp_out4;
logic [16:0] IR_wire,IR_reg;
parameter Fetch= 2'b00, Decode= 2'b01, Execute= 2'b10, WaveOut= 2'b11;

instruct_rom ir(.addr(PC), .data(IR_wire));
note nt(.note_idx(cho_data_r), .freq(n_freq));
chord tf(.chord_data(cho_data_r),.ena(cho_or_no_r), .freq1(c_freq1), .freq2(c_freq2), .freq3(c_freq3), .freq4(c_freq4));
wavegen w1(.clk(clk),.rst(rst),.sample_tick(sample_tick),.freq1(freq1),.ampl(ampl1),.wave_type(wave_type1),.wave_out(wave_out1));
wavegen w2(.clk(clk),.rst(rst),.sample_tick(sample_tick),.freq1(freq2),.ampl(ampl2),.wave_type(wave_type2),.wave_out(wave_out2));
wavegen w3(.clk(clk),.rst(rst),.sample_tick(sample_tick),.freq1(freq3),.ampl(ampl3),.wave_type(wave_type3),.wave_out(wave_out3));
wavegen w4(.clk(clk),.rst(rst),.sample_tick(sample_tick),.freq1(freq4),.ampl(ampl4),.wave_type(wave_type4),.wave_out(wave_out4));
dsp d1(.clk(clk),.rst(rst),.wave_out(wave_out1),.effect_op(effect_op_1),.dsp_out(dsp_out1));
dsp d2(.clk(clk),.rst(rst),.wave_out(wave_out2),.effect_op(effect_op_2),.dsp_out(dsp_out2));
dsp d3(.clk(clk),.rst(rst),.wave_out(wave_out3),.effect_op(effect_op_3),.dsp_out(dsp_out3));
dsp d4(.clk(clk),.rst(rst),.wave_out(wave_out4),.effect_op(effect_op_4),.dsp_out(dsp_out4));
mixer mx(.wave_out1(dsp_out1),.wave_out2(dsp_out2),.wave_out3(dsp_out3),.wave_out4(dsp_out4),.mixed_out(audio_out));

always_comb begin
    wait_mode_d=IR_reg[16];
    music_mode_d=IR_reg[15]&&~IR_reg[16];
    wave_mode_d=IR_reg[13]&&~IR_reg[15]&&~IR_reg[16];
    effect_mode_d=~IR_reg[13]&&~IR_reg[15]&&~IR_reg[16];
    cho_or_no_d=1'b0;
    cho_data_d=5'b0;
    voice_select_d=2'b0;
    wave_type_d=2'b0;
    ampl_d=16'b0;
    effect_op_d=5'b0;
    wait_len_d=16'b0;
    if(wait_mode_d)begin
        wait_len_d=IR_reg[15:0];
    end
    else if(music_mode_d)begin
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
            next_state= (wait_count==0) ? Fetch : WaveOut; // hold here while a WAIT counts down
        end
    endcase
end

// Audio sample-rate tick: pulses once every CLK_DIV master cycles (~65,536 Hz).
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        tick_count  <= 16'b0;
        sample_tick <= 1'b0;
    end else if (tick_count == CLK_DIV - 1) begin
        tick_count  <= 16'b0;
        sample_tick <= 1'b1;
    end else begin
        tick_count  <= tick_count + 1;
        sample_tick <= 1'b0;
    end
end

// WAIT time base: one wait_tick every 64 sample ticks (65,536 / 64 = 1,024 Hz).
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        wait_div <= 6'b0;
    end else if (sample_tick) begin
        wait_div <= wait_div + 1;
    end
end
assign wait_tick = sample_tick && (wait_div == 6'd63);

always_ff @(posedge clk or posedge rst) begin
    if(rst)begin
        PC<=0;
        state<=Fetch;
        IR_reg<=0;
        // Decode Registers
        music_mode_r<=0; wave_mode_r<=0;
        effect_mode_r<=0; cho_or_no_r<=0;
        wait_mode_r<=0; wait_len_r<=0;
        cho_data_r<=0; voice_select_r<=0;
        wave_type_r<=0; ampl_r<=0; effect_op_r<=0;
        effect_op_1<=0; effect_op_2<=0; effect_op_3<=0; effect_op_4<=0;
        wave_type1<=0; wave_type2<=0; wave_type3<=0; wave_type4<=0;
        wait_count<=0;
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
            wait_mode_r<=wait_mode_d;
            wait_len_r<=wait_len_d;
            cho_or_no_r<=cho_or_no_d;
            cho_data_r<=cho_data_d;
            voice_select_r<=voice_select_d;
            wave_type_r<=wave_type_d;
            ampl_r<=ampl_d;
            effect_op_r<=effect_op_d;
        end
        else if(state==Execute)begin
            if(wait_mode_r)begin
                wait_count<=wait_len_r;
            end
            else if(music_mode_r)begin
                if(cho_or_no_r)begin
                    freq1<=c_freq1;
                    freq2<=c_freq2;
                    freq3<=c_freq3;
                    freq4<=c_freq4;
                end
                else begin
                    case(voice_select_r)
                        2'b00: freq1<=n_freq;
                        2'b01: freq2<=n_freq;
                        2'b10: freq3<=n_freq;
                        2'b11: freq4<=n_freq;
                    endcase
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
                    2'b00: effect_op_1<=effect_op_r;
                    2'b01: effect_op_2<=effect_op_r;
                    2'b10: effect_op_3<=effect_op_r;
                    2'b11: effect_op_4<=effect_op_r;
                endcase
            end
        end
        else if(state==WaveOut)begin
            if(wait_tick && wait_count!=0)begin
                wait_count<=wait_count-1;
            end
        end
    end
end
endmodule
