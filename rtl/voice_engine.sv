// Time-multiplexed voice engine.
//
// Every voice shares one datapath. On each sample_tick the engine walks voices 0..N-1,
// spending four clocks on each:
//   LOAD  select the voice's phase, look up the two neighbouring sine entries, advance the phase
//   OSC   interpolate / generate the waveform, step the ADSR envelope
//   ENV   sample x envelope level
//   MIX   x voice volume, per-voice effect (saturating); registered, then added into the mix
//         during the next voice's LOAD (keeps the multiplier and the mix adder in separate clocks)
// then SUM adds the last voice and OUT publishes the saturated mix. Adding a voice costs
// registers only, not multipliers. Needs at least 4*NUM_VOICES + 3 clocks per sample period.
module voice_engine #(
    parameter NUM_VOICES = 8,   // 1..8
    parameter MIX_SHIFT  = 2    // mix = sum(voices) >>> MIX_SHIFT, saturated to 16 bits
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  sample_tick,
    // Command bus from the sequencer (one-clock strobes)
    input  logic                  cmd_valid,
    input  logic [3:0]            cmd_op,
    input  logic [2:0]            cmd_voice,
    input  logic [16:0]           cmd_arg,
    output logic signed [15:0]    sample_out,
    output logic                  sample_valid,  // one-clock pulse when sample_out updates
    output logic                  overrun,       // sticky: a sample_tick arrived before the mix finished
    output logic [NUM_VOICES-1:0] voice_active   // envelope not idle
);
    localparam [3:0]  OP_NOTE_ON = 4'h1, OP_NOTE_OFF = 4'h2, OP_WAVE = 4'h3, OP_ENV = 4'h4, OP_FX = 4'h5;
    localparam [2:0]  W_SINE = 3'd0, W_SQUARE = 3'd1, W_SAW = 3'd2, W_TRIANGLE = 3'd3, W_NOISE = 3'd4;
    localparam [3:0]  FX_BOOST = 4'd1, FX_CUT = 4'd2, FX_DRIVE = 4'd3, FX_CRUSH = 4'd4, FX_COMP = 4'd5;
    localparam [2:0]  ST_IDLE = 3'd0, ST_ATTACK = 3'd1, ST_DECAY = 3'd2, ST_SUSTAIN = 3'd3, ST_RELEASE = 3'd4;
    localparam [2:0]  P_IDLE = 3'd0, P_LOAD = 3'd1, P_OSC = 3'd2, P_ENV = 3'd3, P_MIX = 3'd4, P_SUM = 3'd5, P_OUT = 3'd6;
    localparam [23:0] LEVEL_MAX = 24'hFFFFFF;

    // ---------------- Per-voice state ----------------
    logic [NUM_VOICES-1:0][31:0] phase, tuning;
    logic [NUM_VOICES-1:0][23:0] level;
    logic [NUM_VOICES-1:0][2:0]  stage, wave;
    logic [NUM_VOICES-1:0][7:0]  volume;
    logic [NUM_VOICES-1:0][3:0]  attack, decay, sustain, release_t, effect;   // ("release" is a keyword)

    // ---------------- Shared datapath ----------------
    logic [2:0]         pstate;
    logic [2:0]         v;              // voice being processed
    logic [15:0]        lfsr;
    logic [31:0]        ph_q;           // LOAD -> OSC pipeline registers
    logic signed [15:0] sin_a_q, sin_b_q;
    logic signed [15:0] osc_s, env_s, fx_q;
    logic signed [18:0] mix_acc;

    function automatic signed [15:0] sat16(input signed [18:0] x);
        if (x > 19'sd32767)       sat16 = 16'sh7FFF;
        else if (x < -19'sd32768) sat16 = 16'sh8000;
        else                      sat16 = x[15:0];
    endfunction

    // Fields of the voice being processed
    logic [31:0] ph;
    logic [23:0] lvl, sus_level;
    assign ph        = phase[v];
    assign lvl       = level[v];
    assign sus_level = {6{sustain[v]}};     // 0..15 -> 0x000000..0xFFFFFF

    // ---- LOAD: sine table lookups ----
    logic signed [15:0] sin_a, sin_b;
    sine_table sin_lo(.addr(ph[31:24]),        .value(sin_a));
    sine_table sin_hi(.addr(ph[31:24] + 8'd1), .value(sin_b));

    // ---- OSC: waveform from the registered phase ----
    logic signed [15:0] osc_raw;
    logic signed [16:0] sin_diff;
    logic signed [25:0] sin_step;
    logic [15:0]        tri_u;

    always_comb begin
        sin_diff = sin_b_q - sin_a_q;
        sin_step = sin_diff * $signed({1'b0, ph_q[23:16]});
        tri_u    = ph_q[31] ? ~ph_q[30:15] : ph_q[30:15];
        case (wave[v])
            W_SINE:     osc_raw = sin_a_q + (sin_step >>> 8);   // linear interpolation between entries
            W_SQUARE:   osc_raw = ph_q[31] ? -16'sd32767 : 16'sd32767;
            W_SAW:      osc_raw = ph_q[31:16] ^ 16'h8000;
            W_TRIANGLE: osc_raw = tri_u ^ 16'h8000;
            W_NOISE:    osc_raw = lfsr;
            default:    osc_raw = 16'sd0;
        endcase
    end

    // ---- OSC: ADSR envelope step (linear segments) ----
    logic [23:0] inc_a, inc_d, inc_r, lvl_next;
    logic [2:0]  stg_next;

    env_rate rate_a(.code(attack[v]),    .inc(inc_a));
    env_rate rate_d(.code(decay[v]),     .inc(inc_d));
    env_rate rate_r(.code(release_t[v]), .inc(inc_r));

    always_comb begin
        lvl_next = lvl;
        stg_next = stage[v];
        case (stage[v])
            ST_ATTACK:
                if ({1'b0, lvl} + {1'b0, inc_a} >= {1'b0, LEVEL_MAX}) begin
                    lvl_next = LEVEL_MAX;
                    stg_next = ST_DECAY;
                end else begin
                    lvl_next = lvl + inc_a;
                end
            ST_DECAY:
                if ({1'b0, lvl} <= {1'b0, sus_level} + {1'b0, inc_d}) begin
                    lvl_next = sus_level;
                    stg_next = ST_SUSTAIN;
                end else begin
                    lvl_next = lvl - inc_d;
                end
            ST_SUSTAIN:
                lvl_next = sus_level;
            ST_RELEASE:
                if (lvl <= inc_r) begin
                    lvl_next = 24'd0;
                    stg_next = ST_IDLE;
                end else begin
                    lvl_next = lvl - inc_r;
                end
            default: begin
                lvl_next = 24'd0;
                stg_next = ST_IDLE;
            end
        endcase
    end

    // ---- ENV and MIX: VCA, effect ----
    logic signed [32:0] env_mult;
    logic signed [24:0] vol_mult;
    logic signed [15:0] vol_w;
    logic signed [18:0] fx_wide;
    logic signed [15:0] fx_out;
    assign env_mult = osc_s * $signed({1'b0, lvl[23:8]});
    assign vol_mult = env_s * $signed({1'b0, volume[v]});
    assign vol_w    = vol_mult[23:8];

    always_comb begin
        case (effect[v])
            FX_BOOST: fx_wide = vol_w <<< 1;                        // x2
            FX_CUT:   fx_wide = vol_w >>> 1;                        // x0.5
            FX_DRIVE: fx_wide = vol_w <<< 2;                        // x4 into hard clipping
            FX_CRUSH: fx_wide = $signed({vol_w[15:12], 12'd0});     // 4-bit bitcrush
            FX_COMP:                                                // static 4:1 above half scale
                if (vol_w > 16'sd16384)       fx_wide = 19'sd16384 + ((vol_w - 19'sd16384) >>> 2);
                else if (vol_w < -16'sd16384) fx_wide = -19'sd16384 + ((vol_w + 19'sd16384) >>> 2);
                else                          fx_wide = vol_w;
            default:  fx_wide = vol_w;
        endcase
        fx_out = sat16(fx_wide);
    end

    // ---- Note table for NOTE_ON ----
    logic [31:0] note_tw;
    note_table notes(.note(cmd_arg[6:0]), .tuning_word(note_tw));

    genvar gi;
    generate
        for (gi = 0; gi < NUM_VOICES; gi = gi + 1) begin : g_active
            assign voice_active[gi] = (stage[gi] != ST_IDLE);
        end
    endgenerate

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pstate       <= P_IDLE;
            v            <= 3'd0;
            lfsr         <= 16'hACE1;
            ph_q         <= 32'd0;
            sin_a_q      <= 16'sd0;
            sin_b_q      <= 16'sd0;
            osc_s        <= 16'sd0;
            env_s        <= 16'sd0;
            fx_q         <= 16'sd0;
            mix_acc      <= 19'sd0;
            sample_out   <= 16'sd0;
            sample_valid <= 1'b0;
            overrun      <= 1'b0;
            phase        <= '0;
            tuning       <= '0;
            level        <= '0;
            stage        <= '0;
            wave         <= '0;
            volume       <= '0;
            effect       <= '0;
            attack       <= '0;
            decay        <= '0;
            sustain      <= '1;
            release_t    <= '0;
        end else begin
            sample_valid <= 1'b0;
            if (sample_tick && pstate != P_IDLE) overrun <= 1'b1;

            case (pstate)
                P_IDLE:
                    if (sample_tick) begin
                        v       <= 3'd0;
                        mix_acc <= 19'sd0;
                        fx_q    <= 16'sd0;
                        pstate  <= P_LOAD;
                    end
                P_LOAD: begin
                    mix_acc  <= mix_acc + fx_q;            // previous voice's output
                    ph_q     <= ph;
                    sin_a_q  <= sin_a;
                    sin_b_q  <= sin_b;
                    phase[v] <= ph + tuning[v];
                    lfsr     <= {1'b0, lfsr[15:1]} ^ (lfsr[0] ? 16'hB400 : 16'h0000);
                    pstate   <= P_OSC;
                end
                P_OSC: begin
                    osc_s    <= osc_raw;
                    level[v] <= lvl_next;
                    stage[v] <= stg_next;
                    pstate   <= P_ENV;
                end
                P_ENV: begin
                    env_s  <= env_mult[31:16];
                    pstate <= P_MIX;
                end
                P_MIX: begin
                    fx_q <= fx_out;
                    if (v == NUM_VOICES - 1) begin
                        pstate <= P_SUM;
                    end else begin
                        v      <= v + 3'd1;
                        pstate <= P_LOAD;
                    end
                end
                P_SUM: begin
                    mix_acc <= mix_acc + fx_q;
                    pstate  <= P_OUT;
                end
                P_OUT: begin
                    sample_out   <= sat16(mix_acc >>> MIX_SHIFT);
                    sample_valid <= 1'b1;
                    pstate       <= P_IDLE;
                end
                default: pstate <= P_IDLE;
            endcase

            // Sequencer commands, applied after the datapath so they win when both touch a voice
            if (cmd_valid && cmd_voice < NUM_VOICES) begin
                case (cmd_op)
                    OP_NOTE_ON: begin
                        tuning[cmd_voice] <= note_tw;
                        stage[cmd_voice]  <= ST_ATTACK;       // attack from the current level: no click
                    end
                    OP_NOTE_OFF:
                        if (stage[cmd_voice] != ST_IDLE) stage[cmd_voice] <= ST_RELEASE;
                    OP_WAVE: begin
                        wave[cmd_voice]   <= cmd_arg[10:8];
                        volume[cmd_voice] <= cmd_arg[7:0];
                    end
                    OP_ENV: begin
                        attack[cmd_voice]    <= cmd_arg[15:12];
                        decay[cmd_voice]     <= cmd_arg[11:8];
                        sustain[cmd_voice]   <= cmd_arg[7:4];
                        release_t[cmd_voice] <= cmd_arg[3:0];
                    end
                    OP_FX:
                        effect[cmd_voice] <= cmd_arg[3:0];
                    default: ;
                endcase
            end
        end
    end
endmodule
