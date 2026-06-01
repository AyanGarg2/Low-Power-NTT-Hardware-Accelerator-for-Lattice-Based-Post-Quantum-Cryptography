// ============================================================================
// NTT Core - Complete NTT / NTT^{-1} Processor
//
// Paper : "Efficient and Flexible Low-Power NTT for Lattice-Based Cryptography"
//         Tim Fritzmann, Johanna Sepulveda - IEEE HOST 2019
//
// Architecture (Fig. 2):
//   • Single-port async-read RAM  (2 × 16-bit coefficients per word)
//   • Shared Montgomery multiplier  (butterfly + ω update)
//   • Barrett add / sub  for butterfly
//   • Two dedicated inverse-NTT multipliers with operand isolation  (Fig. 5)
//   • Four alpha-update Montgomery units  (Alg. 5, lines 19-20)
//
// Power optimizations (Section VII):
//   • H1 / L1 only loaded during read phases  → clock gating  (Fig. 4 left)
//   • Latch after first multiplier blocks propagation during idle
//     → operand isolation  (Fig. 4 right)
//   • Inverse-NTT multiplier inputs forced to zero when inactive
//     → operand isolation  (Fig. 5)
//
// Timing :  n · log₂(n)  +  3 · log₂(n)  startup  clock cycles
//
// Verified against cycle-accurate Python model for:
//   n =    8, q =  7681   ✓
//   n =  256, q =  7681   ✓
//   n = 1024, q = 12289   ✓
// ============================================================================

`include "ntt_defines.vh"

module ntt_core (
    input  wire                         clk,
    input  wire                         rst_n,

    // ---- control ----
    input  wire                         start,
    input  wire                         is_inverse,
    output reg                          done,
    output reg                          busy,

    // ---- run-time parameters ----
    input  wire [`MAX_LOG_N-1:0]        cfg_log_n,       // log₂(n)
    input  wire [`COEFF_WIDTH-1:0]      cfg_q,           // prime modulus
    input  wire [`COEFF_WIDTH-1:0]      cfg_q_prime,     // -q⁻¹ mod R
    input  wire [`COEFF_WIDTH-1:0]      cfg_barrett_m,   // Barrett m
    input  wire [4:0]                   cfg_barrett_k,   // Barrett k

    // NTT⁻¹ post-processing  (Algorithm 5 lines 4-7)
    input  wire [`COEFF_WIDTH-1:0]      cfg_gamma1,      // n⁻¹·R mod q
    input  wire [`COEFF_WIDTH-1:0]      cfg_gamma2,      // n⁻¹·γ_n⁻¹·R mod q
    input  wire [`COEFF_WIDTH-1:0]      cfg_gamma3,      // n⁻¹·γ^{-n/2}·R mod q
    input  wire [`COEFF_WIDTH-1:0]      cfg_gamma4,      // n⁻¹·γ^{-n/2-1}·R mod q
    input  wire [`COEFF_WIDTH-1:0]      cfg_beta,        // ω_n⁻¹·R mod q
    input  wire [`COEFF_WIDTH-1:0]      cfg_r_mod_q,     // R mod q  (= "1" in Mont. domain)

    // ---- external RAM access (active when !busy) ----
    input  wire                         ext_ram_we,
    input  wire [`MEM_ADDR_WIDTH-1:0]   ext_ram_addr,
    input  wire [`MEM_WIDTH-1:0]        ext_ram_din,
    output wire [`MEM_WIDTH-1:0]        ext_ram_dout,

    // ---- ω-LUT load interface ----
    input  wire                         lut_we,
    input  wire [3:0]                   lut_waddr,
    input  wire [`COEFF_WIDTH-1:0]      lut_wdata
);

    // ================================================================
    //  FSM encoding
    // ================================================================
    localparam [3:0]
        S_IDLE     = 4'd0,
        S_LOAD_OM  = 4'd1,   // read ω_m from LUT
        S_LOAD_GM  = 4'd2,   // read γ_m from LUT, init ω
        S_FR_P0    = 4'd3,   // first rounds - phase 0  (read 1)
        S_FR_P1    = 4'd4,   //                 phase 1  (butterfly 1 + read 2)
        S_FR_P2    = 4'd5,   //                 phase 2  (butterfly 2 + write 1)
        S_FR_P3    = 4'd6,   //                 phase 3  (write 2 + ω update)
        S_LR_P0    = 4'd7,   // last round  - phase 0  (read 1 + deferred ω upd.)
        S_LR_P1    = 4'd8,   //               phase 1  (butterfly 1 + read 2)
        S_LR_P2    = 4'd9,   //               phase 2  (write 1 + ω update)
        S_LR_P3    = 4'd10,  //               phase 3  (butterfly 2 + write 2)
        S_DONE     = 4'd11;

    reg [3:0] state;

    // ================================================================
    //  Latched configuration
    // ================================================================
    reg [`MAX_LOG_N-1:0]    log_n;
    reg [`MAX_LOG_N:0]      n_val;       // 2^{log_n}
    reg [`MAX_LOG_N-1:0]    n_half;      // n / 2
    reg [`COEFF_WIDTH-1:0]  q, q_prime, bm;
    reg [4:0]               bk;
    reg                     inv;
    reg [`COEFF_WIDTH-1:0]  beta;
    reg [`COEFF_WIDTH-1:0]  r_mod_q;     // R mod q

    // ================================================================
    //  Loop state
    // ================================================================
    reg [`MAX_LOG_N:0]      m;           // butterfly span  (2 → n)
    reg [`MAX_LOG_N-1:0]    mh;          // m / 2
    reg [3:0]               li;          // LUT index
    reg [`MAX_LOG_N-1:0]    j, k;
    reg                     lr;          // 1 = last round
    reg                     first_lr;    // 1 = first iter of last round

    // ================================================================
    //  Datapath registers  (Fig. 2)
    // ================================================================
    reg [`COEFF_WIDTH-1:0]  H1, L1;                  // input regs
    reg [`COEFF_WIDTH-1:0]  R1, R2, R3, R4, R5;      // swap regs
    reg [`COEFF_WIDTH-1:0]  omega, omega_m;           // twiddle factors
    reg [`COEFF_WIDTH-1:0]  al1, al2, al3, al4;       // inverse scaling
    reg [`COEFF_WIDTH-1:0]  tval;                     // latch (Fig. 4 right)

    // ================================================================
    //  RAM  - muxed between external and internal access
    // ================================================================
    reg                         irwe;
    reg  [`MEM_ADDR_WIDTH-1:0]  iraddr;
    reg  [`MEM_WIDTH-1:0]       irdin;
    wire [`MEM_WIDTH-1:0]       rdo;

    wire                        rwe = busy ? irwe     : ext_ram_we;
    wire [`MEM_ADDR_WIDTH-1:0]  ra  = busy ? iraddr   : ext_ram_addr;
    wire [`MEM_WIDTH-1:0]       rdi = busy ? irdin    : ext_ram_din;
    assign ext_ram_dout = rdo;

    ntt_ram u_ram (
        .clk(clk), .we(rwe), .addr(ra), .din(rdi), .dout(rdo)
    );

    // ================================================================
    //  ω LUT
    // ================================================================
    reg  [3:0]              lra;
    wire [`COEFF_WIDTH-1:0] lrd;

    omega_lut u_lut (
        .clk(clk), .we(lut_we), .waddr(lut_waddr),
        .wdata(lut_wdata), .raddr(lra), .rdata(lrd)
    );

    // ================================================================
    //  Main multiplier  (shared: butterfly, ω update, α update)
    // ================================================================
    reg  [`COEFF_WIDTH-1:0] ma, mb;
    wire [`MULT_WIDTH-1:0]  mp   = ma * mb;
    wire [`COEFF_WIDTH-1:0] mout;

    montgomery_reduce u_mont_main (
        .q(q), .q_prime(q_prime), .a_in(mp), .result(mout)
    );

    // ================================================================
    //  Butterfly  -  Barrett-reduced add / sub
    //
    //  Operand isolation (Fig. 4 right):
    //    tv = mout   during active butterfly phases   (transparent)
    //    tv = tval   during all other phases           (latched, no toggle)
    // ================================================================
    wire bf_act = (state == S_FR_P1) | (state == S_FR_P2) |
                  (state == S_LR_P1) | (state == S_LR_P3);

    wire [`COEFF_WIDTH-1:0] tv = bf_act ? mout : tval;

    wire [`COEFF_WIDTH:0] bfai = {1'b0, L1} + {1'b0, tv};
    wire [`COEFF_WIDTH:0] bfsi = {1'b0, L1} + {1'b0, q} - {1'b0, tv};

    wire [`COEFF_WIDTH-1:0] bfa, bfs;

    barrett_reduce u_ba (
        .q(q), .barrett_m(bm), .barrett_k(bk),
        .a_in(bfai), .result(bfa)
    );
    barrett_reduce u_bs (
        .q(q), .barrett_m(bm), .barrett_k(bk),
        .a_in(bfsi), .result(bfs)
    );

    // ================================================================
    //  Inverse-NTT multipliers  (Fig. 2 red,  Fig. 5 operand isolation)
    //
    //  Two Montgomery multipliers scale the butterfly outputs by α_i.
    //  Inputs forced to zero when not in the active inverse-last-round
    //  phase, eliminating unnecessary switching  (Fig. 5).
    // ================================================================
    wire iact = inv & lr & (state == S_LR_P1 | state == S_LR_P3);

    wire [`COEFF_WIDTH-1:0] iop_a = iact ? bfa  : 16'd0;
    wire [`COEFF_WIDTH-1:0] iop_s = iact ? bfs  : 16'd0;

    wire [`COEFF_WIDTH-1:0] ial_a = (state == S_LR_P1) ? (iact ? al1 : 16'd0) :
                                    (state == S_LR_P3) ? (iact ? al2 : 16'd0) :
                                                          16'd0;
    wire [`COEFF_WIDTH-1:0] ial_s = (state == S_LR_P1) ? (iact ? al3 : 16'd0) :
                                    (state == S_LR_P3) ? (iact ? al4 : 16'd0) :
                                                          16'd0;

    wire [`MULT_WIDTH-1:0]  ipa = iop_a * ial_a;
    wire [`MULT_WIDTH-1:0]  ips = iop_s * ial_s;
    wire [`COEFF_WIDTH-1:0] imo_a, imo_s;

    montgomery_reduce u_inv_a (
        .q(q), .q_prime(q_prime), .a_in(ipa), .result(imo_a)
    );
    montgomery_reduce u_inv_s (
        .q(q), .q_prime(q_prime), .a_in(ips), .result(imo_s)
    );

    // ================================================================
    //  α update :  α_i ← mont(α_i · β)   (Alg. 5 lines 19-20)
    // ================================================================
    wire [`MULT_WIDTH-1:0]  a1p = al1 * beta;
    wire [`MULT_WIDTH-1:0]  a2p = al2 * beta;
    wire [`MULT_WIDTH-1:0]  a3p = al3 * beta;
    wire [`MULT_WIDTH-1:0]  a4p = al4 * beta;

    wire [`COEFF_WIDTH-1:0] a1u, a2u, a3u, a4u;

    montgomery_reduce u_au1 (.q(q),.q_prime(q_prime),.a_in(a1p),.result(a1u));
    montgomery_reduce u_au2 (.q(q),.q_prime(q_prime),.a_in(a2p),.result(a2u));
    montgomery_reduce u_au3 (.q(q),.q_prime(q_prime),.a_in(a3p),.result(a3u));
    montgomery_reduce u_au4 (.q(q),.q_prime(q_prime),.a_in(a4p),.result(a4u));

    // ================================================================
    //  Address generation  (combinational)
    // ================================================================
    wire [`MEM_ADDR_WIDTH-1:0] fa1 = k[`MEM_ADDR_WIDTH-1:0]
                                   + j[`MEM_ADDR_WIDTH-1:0];
    wire [`MEM_ADDR_WIDTH-1:0] fa2 = fa1 + mh[`MEM_ADDR_WIDTH-1:0];
    wire [`MEM_ADDR_WIDTH-1:0] la1 = j[`MEM_ADDR_WIDTH-1:0];
    wire [`MEM_ADDR_WIDTH-1:0] la2 = j[`MEM_ADDR_WIDTH-1:0] + 1;

    // ================================================================
    //  Loop termination  (combinational, uses CURRENT register values)
    // ================================================================
    wire k_end = (k + m[`MAX_LOG_N-1:0] >= n_half);
    wire j_end = (j >= mh - 1);
    wire m_end = (m >= n_half);          // after this round → last round

    // ================================================================
    //  Combinational output logic  - multiplier mux + RAM control
    // ================================================================
    always @(*) begin
        ma     = 16'd0;
        mb     = 16'd0;
        irwe   = 1'b0;
        iraddr = {`MEM_ADDR_WIDTH{1'b0}};
        irdin  = {`MEM_WIDTH{1'b0}};

        case (state)
            // ---- first rounds -----------------------------------------
            S_FR_P0: begin
                iraddr = fa1;                    // read  MEMk+j
            end
            S_FR_P1: begin
                iraddr = fa2;                    // read  MEMk+j+m/2
                ma = H1;  mb = omega;            // butterfly 1 : H1 · ω
            end
            S_FR_P2: begin
                iraddr = fa1;                    // write MEMk+j
                irwe   = 1'b1;
                ma = H1;  mb = omega;            // butterfly 2 : H1 · ω
                irdin  = {bfa, R4};              // {u2+t2 , u1+t1}
            end
            S_FR_P3: begin
                iraddr = fa2;                    // write MEMk+j+m/2
                irwe   = 1'b1;
                ma = omega;  mb = omega_m;       // ω update : ω · ω_m
                irdin  = {R2, R3};               // {u2-t2 , u1-t1}
            end
            // ---- last round -------------------------------------------
            S_LR_P0: begin
                iraddr = la1;                    // read  MEMj
                ma = omega;  mb = omega_m;       // deferred ω update
            end
            S_LR_P1: begin
                iraddr = la2;                    // read  MEMj+1
                ma = H1;  mb = omega;            // butterfly 1
            end
            S_LR_P2: begin
                iraddr = la1;                    // write MEMj
                irwe   = 1'b1;
                ma = omega;  mb = omega_m;       // ω update (Alg 5 line 12)
                irdin  = {R1, R4};               // {a_{j+n/2} , a_j}
            end
            S_LR_P3: begin
                iraddr = la2;                    // write MEMj+1
                irwe   = 1'b1;
                ma = H1;  mb = omega;            // butterfly 2
                if (inv)
                    irdin = {imo_s, imo_a};      // inverse-scaled
                else
                    irdin = {bfs, bfa};          // {a_{j+n/2+1} , a_{j+1}}
            end
            default: begin end
        endcase
    end

    // ================================================================
    //  Main FSM  - sequential
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            done     <= 1'b0;   busy     <= 1'b0;
            log_n    <= 0;      n_val    <= 0;      n_half   <= 0;
            q        <= 0;      q_prime  <= 0;      bm       <= 0;
            bk       <= 0;      inv      <= 0;      beta     <= 0;
            r_mod_q  <= 0;
            m        <= 0;      mh       <= 0;      li       <= 0;
            j        <= 0;      k        <= 0;
            lr       <= 0;      first_lr <= 0;
            H1       <= 0;      L1       <= 0;
            R1       <= 0;      R2       <= 0;      R3       <= 0;
            R4       <= 0;      R5       <= 0;
            omega    <= 0;      omega_m  <= 0;
            al1      <= 0;      al2      <= 0;
            al3      <= 0;      al4      <= 0;
            tval     <= 0;      lra      <= 0;
        end
        else begin
            done <= 1'b0;

            case (state)
            // ==========================================================
            S_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    log_n   <= cfg_log_n;
                    n_val   <= (11'd1 << cfg_log_n);
                    n_half  <= (10'd1 << (cfg_log_n - 1));
                    q       <= cfg_q;
                    q_prime <= cfg_q_prime;
                    bm      <= cfg_barrett_m;
                    bk      <= cfg_barrett_k;
                    inv     <= is_inverse;
                    beta    <= cfg_beta;
                    r_mod_q <= cfg_r_mod_q;
                    busy    <= 1'b1;

                    m       <= 11'd2;
                    mh      <= 10'd1;
                    li      <= 4'd0;
                    lr      <= 1'b0;
                    first_lr<= 1'b0;

                    lra     <= 4'd0;       // request LUT[0]
                    state   <= S_LOAD_OM;
                end
            end

            // ==========================================================
            //  S_LOAD_OM :  ω_m now available from LUT[li]
            // ==========================================================
            S_LOAD_OM: begin
                omega_m <= lrd;            // ω_m = LUT[li]
                lra     <= li + 4'd1;      // request LUT[li+1]  (γ_m)
                state   <= S_LOAD_GM;
            end

            // ==========================================================
            //  S_LOAD_GM :  γ_m available ; initialise ω and counters
            //
            //  NTT   :  ω ← LUT[li+1]   = γ_m   (Alg 4 line 6)
            //  NTT⁻¹ :  ω ← R mod q     = "1"   (Alg 4 line 6 / Alg 5 line 3)
            // ==========================================================
            S_LOAD_GM: begin
                omega <= inv ? r_mod_q : lrd;

                j <= 0;
                k <= 0;

                if (lr) begin
                    if (inv) begin
                        al1 <= cfg_gamma1;
                        al2 <= cfg_gamma2;
                        al3 <= cfg_gamma3;
                        al4 <= cfg_gamma4;
                    end
                    first_lr <= 1'b1;
                    state    <= S_LR_P0;
                end
                else begin
                    state <= S_FR_P0;
                end
            end

            // ==========================================================
            //  FIRST ROUNDS  (Alg. 4,  m = 2 … n/2)
            // ==========================================================

            // -- phase 0 : read MEMk+j → H1 / L1  (clock gating ON)
            S_FR_P0: begin
                H1    <= rdo[`MEM_WIDTH-1:`COEFF_WIDTH];
                L1    <= rdo[`COEFF_WIDTH-1:0];
                state <= S_FR_P1;
            end

            // -- phase 1 : butterfly 1  +  read MEMk+j+m/2 → H1 / L1
            S_FR_P1: begin
                R4   <= bfa;              // u1 + t1
                R1   <= bfs;              // u1 - t1
                tval <= mout;             // latch  (operand isolation)

                H1   <= rdo[`MEM_WIDTH-1:`COEFF_WIDTH];
                L1   <= rdo[`COEFF_WIDTH-1:0];
                state <= S_FR_P2;
            end

            // -- phase 2 : butterfly 2  +  write MEMk+j = {bfa, R4}
            S_FR_P2: begin
                R5   <= bfa;              // u2 + t2
                R2   <= bfs;              // u2 - t2
                R3   <= R1;               // save for write 2
                tval <= mout;
                state <= S_FR_P3;
            end

            // -- phase 3 : write MEMk+j+m/2 = {R2, R3}  +  ω update
            S_FR_P3: begin
                // ω update ONLY when k-loop finishes  (Alg 4 line 18)
                if (k_end)
                    omega <= mout;

                // advance loop counters
                if (k_end) begin
                    k <= 0;
                    if (j_end) begin
                        j  <= 0;
                        m  <= m << 1;
                        mh <= m[`MAX_LOG_N-1:0];  // new mh = old m
                        li <= li + 4'd1;
                        lra<= li + 4'd1;
                        if (m_end) lr <= 1'b1;
                        state <= S_LOAD_OM;
                    end
                    else begin
                        j     <= j + 1;
                        state <= S_FR_P0;
                    end
                end
                else begin
                    k     <= k + m[`MAX_LOG_N-1:0];
                    state <= S_FR_P0;
                end
            end

            // ==========================================================
            //  LAST ROUND  (Alg. 5,  m = n)
            //
            //  Two butterflies per iteration (j, j+1).
            //  Section V-A : saves n/4 cycles.
            // ==========================================================

            // -- phase 0 : read MEMj  +  deferred ω update from prev iter
            S_LR_P0: begin
                if (!first_lr)
                    omega <= mout;         // deferred ω·ω_m

                H1    <= rdo[`MEM_WIDTH-1:`COEFF_WIDTH];
                L1    <= rdo[`COEFF_WIDTH-1:0];

                first_lr <= 1'b0;
                state    <= S_LR_P1;
            end

            // -- phase 1 : butterfly 1  +  read MEMj+1
            S_LR_P1: begin
                tval <= mout;

                if (inv) begin
                    R4 <= imo_a;           // mont(bfa · α1)
                    R1 <= imo_s;           // mont(bfs · α3)
                end
                else begin
                    R4 <= bfa;             // a_j
                    R1 <= bfs;             // a_{j+n/2}
                end

                H1    <= rdo[`MEM_WIDTH-1:`COEFF_WIDTH];
                L1    <= rdo[`COEFF_WIDTH-1:0];
                state <= S_LR_P2;
            end

            // -- phase 2 : write MEMj  +  ω update (Alg 5 line 12)
            S_LR_P2: begin
                omega <= mout;             // ω ← mont(ω · ω_m)
                state <= S_LR_P3;
            end

            // -- phase 3 : butterfly 2  +  write MEMj+1  +  α update
            S_LR_P3: begin
                tval <= mout;

                if (inv) begin
                    al1 <= a1u;  al2 <= a2u;
                    al3 <= a3u;  al4 <= a4u;
                end

                // second ω update (Alg 5 line 24) deferred to next LR_P0

                if (j + 2 >= n_half)
                    state <= S_DONE;
                else begin
                    j     <= j + 2;
                    state <= S_LR_P0;
                end
            end

            // ==========================================================
            S_DONE: begin
                done <= 1'b1;
                busy <= 1'b0;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule