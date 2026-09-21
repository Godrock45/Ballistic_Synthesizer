module tb(
    input clk,
    input t,
    input rst
);
reg [1:0] state, nextstate;
parameter [1:0] Red=2'b10, Green=2'b00, Yellow=2'b01, Walking=2'b11;
always_comb begin
    case(state)
        2'b00:begin
            nextstate=t?Yellow:Green;
        end
        2'b01:begin
            nextstate=t?Red:Yellow;
        end
        2'b10:begin 
            nextstate=t?Walking:Red;
        end
        2'b11:begin
            nextstate=t?Green:Walking;
        end
        default:begin
            nextstate=Green;
        end        
    endcase
end
always_ff @(posedge clk)begin
    if(rst)begin
        state<=Green;
    end
    else begin
        state<=nextstate;
    end
end

endmodule