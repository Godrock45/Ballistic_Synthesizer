module control(
    input clk,
    input rst
);
logic [16:0] IR;
logic [8:0] PC;
logic [1:0] voice_select;
logic [1:0] state,next_state;
logic [16:0] c_freq1,c_freq2,c_freq3,c_freq4,freq1,freq2,freq3,freq4,n_freq1,n_freq2,n_freq3,n_freq4;
logic [16:0] ampl1,ampl2,ampl3,ampl4;
logic [2:0] wave_type1,wave_type2,wave_type3,wave_type4;
parameter Fetch= 2'b00, Decode= 2'b01, Execute= 2'b10, WaveOut= 2'b11;

note ch(.chord_data(IR[13:9]),.ena(~IR[14]), .freq1(n_freq1), .freq2(n_freq2), .freq3(n_freq3), .freq4(n_freq4));
chord tf(.chord_data(IR[13:9]),.ena(IR[14]), .freq1(c_freq1), .freq2(c_freq2), .freq3(c_freq3), .freq4(c_freq4));
logic music_mode; // 0 for single note, 1 for chord
always_comb begin : 
    case(state)
        Fetch:begin
            next_state= Decode;
        end
        Decode:begin //next goal is to add a flag for other type of instructions such as wave_type amplitude and 
                next_state= Execute;
        end
        Execute:begin
            next_state= WaveOut;
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
        music_mode<=IR[15];

    end
    else if(state==EXECUTE)begin
        freq1=IN[14]?c_freq1:n_freq1;
        freq2=IN[14]?c_freq2:n_freq2;
        freq3=IN[14]?c_freq3:n_freq3;
        freq4=IN[14]?c_freq4:n_freq4; 
    end
       
end

endmodule