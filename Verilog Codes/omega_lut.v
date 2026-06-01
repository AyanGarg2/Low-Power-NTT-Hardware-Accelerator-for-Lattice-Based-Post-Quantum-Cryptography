// ============================================================================
// Omega LUT - Twiddle Factor Look-Up Table
//   Forward : LUT[i] = ω_{2^{i+1}} · R mod q   (i = 0 … log(n))
//   Inverse : LUT[i] = ω_{2^{i+1}}^{-1} · R mod q
//   Loaded externally before each NTT/NTT^{-1} operation.
// ============================================================================

`include "ntt_defines.vh"

module omega_lut (
    input  wire                         clk,
    input  wire                         we,
    input  wire [3:0]                   waddr,
    input  wire [`COEFF_WIDTH-1:0]      wdata,
    input  wire [3:0]                   raddr,
    output wire [`COEFF_WIDTH-1:0]      rdata
);

    reg [`COEFF_WIDTH-1:0] lut [0:`LUT_DEPTH-1];

    always @(posedge clk) begin
        if (we) lut[waddr] <= wdata;
    end

    assign rdata = lut[raddr];   // combinational read
endmodule