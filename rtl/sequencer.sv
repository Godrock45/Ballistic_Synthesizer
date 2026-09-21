// Program sequencer. Fetches 24-bit instructions from a block-RAM ROM and executes them
// back to back (two clocks each) until a WAIT, which sleeps for a number of 1 ms ticks.
// Voice instructions are forwarded to the voice engine as one-clock commands.
// See scripts/asm.py for the instruction set.
module sequencer #(
    parameter PROGRAM_FILE = "build/program.hex",
    parameter ADDR_BITS    = 10
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 ms_tick,
    output logic                 cmd_valid,
    output logic [3:0]           cmd_op,
    output logic [2:0]           cmd_voice,
    output logic [16:0]          cmd_arg,
    output logic [ADDR_BITS-1:0] pc,
    output logic                 halted
);
    localparam [3:0] OP_NOTE_ON = 4'h1, OP_NOTE_OFF = 4'h2, OP_WAVE = 4'h3, OP_ENV = 4'h4,
                     OP_FX = 4'h5, OP_WAIT = 4'h6, OP_JUMP = 4'h7, OP_HALT = 4'hF;
    localparam [1:0] S_FETCH = 2'd0, S_EXEC = 2'd1, S_WAIT = 2'd2, S_HALT = 2'd3;

    logic [23:0] rom [0:(1<<ADDR_BITS)-1];
    initial $readmemh(PROGRAM_FILE, rom);

    logic [23:0] instr;
    logic [1:0]  state;
    logic [15:0] wait_left;

    always_ff @(posedge clk) instr <= rom[pc];   // synchronous read -> block RAM

    assign halted = (state == S_HALT);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_FETCH;
            pc        <= '0;
            wait_left <= 16'd0;
            cmd_valid <= 1'b0;
            cmd_op    <= 4'd0;
            cmd_voice <= 3'd0;
            cmd_arg   <= 17'd0;
        end else begin
            cmd_valid <= 1'b0;
            case (state)
                S_FETCH: state <= S_EXEC;         // instr is valid next cycle
                S_EXEC: begin
                    pc    <= pc + 1'b1;
                    state <= S_FETCH;
                    case (instr[23:20])
                        OP_NOTE_ON, OP_NOTE_OFF, OP_WAVE, OP_ENV, OP_FX: begin
                            cmd_valid <= 1'b1;
                            cmd_op    <= instr[23:20];
                            cmd_voice <= instr[19:17];
                            cmd_arg   <= instr[16:0];
                        end
                        OP_WAIT:
                            if (instr[15:0] != 16'd0) begin
                                wait_left <= instr[15:0];
                                state     <= S_WAIT;
                            end
                        OP_JUMP: pc <= instr[ADDR_BITS-1:0];
                        OP_HALT: begin
                            pc    <= pc;
                            state <= S_HALT;
                        end
                        default: ;                // NOP and unused opcodes
                    endcase
                end
                S_WAIT:
                    if (ms_tick) begin
                        wait_left <= wait_left - 16'd1;
                        if (wait_left == 16'd1) state <= S_FETCH;
                    end
                default: ;                        // S_HALT: stay
            endcase
        end
    end
endmodule
