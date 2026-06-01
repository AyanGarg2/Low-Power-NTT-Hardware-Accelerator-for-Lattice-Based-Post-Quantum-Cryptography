// ============================================================================
// NTT Top-Level Wrapper  (synthesis-safe - no multi-driver nets)
//
// Register map (active when !busy):
//   0x000  Control   - [0] start (self-clearing), [1] is_inverse, [25:16] log_n
//   0x004  Status    - [0] done, [1] busy
//   0x008  q
//   0x00C  q_prime
//   0x010  barrett_m
//   0x014  barrett_k        ([4:0])
//   0x018  gamma1
//   0x01C  gamma2
//   0x020  gamma3
//   0x024  gamma4
//   0x028  beta
//   0x02C  r_mod_q          (R mod q)
//   0x100-0x12C  w-LUT      (12 x 16-bit entries)
//   0x200-0x9FF  Coeff. RAM (512 x 32-bit words)
// ============================================================================

`include "ntt_defines.vh"

module ntt_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [11:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    output wire        irq_done,
    output wire        busy
);

    // ---- configuration registers ----
    reg [`MAX_LOG_N-1:0]    cfg_log_n;
    reg [`COEFF_WIDTH-1:0]  cfg_q, cfg_qp, cfg_bm;
    reg [4:0]               cfg_bk;
    reg [`COEFF_WIDTH-1:0]  cfg_g1, cfg_g2, cfg_g3, cfg_g4;
    reg [`COEFF_WIDTH-1:0]  cfg_beta, cfg_rmq;
    reg                     start_pulse, inv_reg;

    wire done_w, busy_w;
    assign irq_done = done_w;
    assign busy     = busy_w;

    // ---- RAM signals ----
    reg                         ram_we_r;       // registered write enable
    reg  [`MEM_WIDTH-1:0]       ram_din_r;      // registered write data
    reg  [`MEM_ADDR_WIDTH-1:0]  ram_addr_wr;    // registered write address
    wire [`MEM_WIDTH-1:0]       ram_dout;

    // ---- LUT signals ----
    reg                         lut_we;
    reg  [3:0]                  lut_addr;
    reg  [`COEFF_WIDTH-1:0]     lut_data;

    // ---- RAM address: SINGLE combinational driver ----
    // Decodes bus address into RAM index
    wire                        bus_ram_sel  = (addr >= 12'h200);
    wire [`MEM_ADDR_WIDTH-1:0]  bus_ram_addr = (addr - 12'h200) >> 2;

    // Priority: registered write > bus read > hold 0
    wire [`MEM_ADDR_WIDTH-1:0]  ram_addr =
        ram_we_r                    ? ram_addr_wr  :
        (rd_en && bus_ram_sel)      ? bus_ram_addr  :
                                      {`MEM_ADDR_WIDTH{1'b0}};

    // ---- NTT core ----
    ntt_core u_core (
        .clk(clk), .rst_n(rst_n),
        .start(start_pulse), .is_inverse(inv_reg),
        .done(done_w), .busy(busy_w),
        .cfg_log_n(cfg_log_n), .cfg_q(cfg_q), .cfg_q_prime(cfg_qp),
        .cfg_barrett_m(cfg_bm), .cfg_barrett_k(cfg_bk),
        .cfg_gamma1(cfg_g1), .cfg_gamma2(cfg_g2),
        .cfg_gamma3(cfg_g3), .cfg_gamma4(cfg_g4),
        .cfg_beta(cfg_beta), .cfg_r_mod_q(cfg_rmq),
        .ext_ram_we(ram_we_r),
        .ext_ram_addr(ram_addr),
        .ext_ram_din(ram_din_r),
        .ext_ram_dout(ram_dout),
        .lut_we(lut_we), .lut_waddr(lut_addr), .lut_wdata(lut_data)
    );

    // ---- sequential: register writes only ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_log_n   <= 0; cfg_q  <= 0; cfg_qp <= 0;
            cfg_bm      <= 0; cfg_bk <= 0;
            cfg_g1      <= 0; cfg_g2 <= 0; cfg_g3 <= 0; cfg_g4 <= 0;
            cfg_beta    <= 0; cfg_rmq <= 0;
            start_pulse <= 0; inv_reg <= 0;
            ram_we_r    <= 0; ram_din_r <= 0; ram_addr_wr <= 0;
            lut_we      <= 0; lut_addr <= 0; lut_data <= 0;
        end else begin
            // Self-clearing defaults
            start_pulse <= 1'b0;
            ram_we_r    <= 1'b0;
            lut_we      <= 1'b0;

            if (wr_en) begin
                casez (addr)
                12'h000: begin
                    start_pulse <= wdata[0];
                    inv_reg     <= wdata[1];
                    cfg_log_n   <= wdata[`MAX_LOG_N+15:16];
                end
                12'h008: cfg_q    <= wdata[`COEFF_WIDTH-1:0];
                12'h00C: cfg_qp   <= wdata[`COEFF_WIDTH-1:0];
                12'h010: cfg_bm   <= wdata[`COEFF_WIDTH-1:0];
                12'h014: cfg_bk   <= wdata[4:0];
                12'h018: cfg_g1   <= wdata[`COEFF_WIDTH-1:0];
                12'h01C: cfg_g2   <= wdata[`COEFF_WIDTH-1:0];
                12'h020: cfg_g3   <= wdata[`COEFF_WIDTH-1:0];
                12'h024: cfg_g4   <= wdata[`COEFF_WIDTH-1:0];
                12'h028: cfg_beta <= wdata[`COEFF_WIDTH-1:0];
                12'h02C: cfg_rmq  <= wdata[`COEFF_WIDTH-1:0];
                12'h1??: begin
                    lut_we   <= 1'b1;
                    lut_addr <= addr[3:0];
                    lut_data <= wdata[`COEFF_WIDTH-1:0];
                end
                default: begin
                    if (bus_ram_sel) begin
                        ram_we_r    <= 1'b1;
                        ram_addr_wr <= bus_ram_addr;
                        ram_din_r   <= wdata;
                    end
                end
                endcase
            end
        end
    end

    // ---- combinational: register reads (no ram_addr assignment here!) ----
    always @(*) begin
        rdata = 32'd0;

        if (rd_en) begin
            casez (addr)
            12'h000: rdata = {6'd0, cfg_log_n, 14'd0, inv_reg, 1'b0};
            12'h004: rdata = {30'd0, busy_w, done_w};
            12'h008: rdata = {16'd0, cfg_q};
            12'h00C: rdata = {16'd0, cfg_qp};
            12'h010: rdata = {16'd0, cfg_bm};
            12'h014: rdata = {27'd0, cfg_bk};
            default: begin
                if (bus_ram_sel)
                    rdata = ram_dout;   // address already set by assign
            end
            endcase
        end
    end

endmodule