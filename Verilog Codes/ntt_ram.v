// ============================================================================
// Single-Port RAM - Asynchronous Read, Synchronous Write
//   Each 32-bit word stores two 16-bit polynomial coefficients:
//     [31:16] = odd-index coefficient   (DOH in Fig. 2)
//     [15: 0] = even-index coefficient  (DOL in Fig. 2)
// ============================================================================

`include "ntt_defines.vh"

module ntt_ram (
    input  wire                         clk,
    input  wire                         we,
    input  wire [`MEM_ADDR_WIDTH-1:0]   addr,
    input  wire [`MEM_WIDTH-1:0]        din,
    output wire [`MEM_WIDTH-1:0]        dout
);

    reg [`MEM_WIDTH-1:0] mem [0:`MEM_DEPTH-1];

    always @(posedge clk) begin
        if (we) mem[addr] <= din;
    end

    assign dout = mem[addr];   // combinational read
endmodule