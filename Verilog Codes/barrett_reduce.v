// ============================================================================
// Barrett Modular Reduction  (Algorithm 2)
//
//   Input  : a  (17-bit, result of add/sub, range [0, 2q-1])
//   Output : a mod q  (16 bits)
//
//   Constants loaded at run-time:
//     q         - prime modulus
//     barrett_m - floor(2^k / q)
//     barrett_k - shift amount
// ============================================================================

`include "ntt_defines.vh"

module barrett_reduce (
    input  wire [`COEFF_WIDTH-1:0]  q,
    input  wire [`COEFF_WIDTH-1:0]  barrett_m,
    input  wire [4:0]               barrett_k,
    input  wire [`COEFF_WIDTH:0]    a_in,       // 17 bits
    output wire [`COEFF_WIDTH-1:0]  result
);

    // Step 1 : u = (a · m) >> k
    wire [2*`COEFF_WIDTH:0] a_times_m = a_in * barrett_m;
    wire [`COEFF_WIDTH:0]   u         = a_times_m >> barrett_k;

    // Step 2 : a = a - u·q
    wire [`MULT_WIDTH:0] u_times_q = u[`COEFF_WIDTH-1:0] * q;
    wire [`COEFF_WIDTH:0] a_reduced = a_in - u_times_q[`COEFF_WIDTH:0];

    // Step 3 : conditional subtraction
    wire [`COEFF_WIDTH:0] a_minus_q = a_reduced - {1'b0, q};

    assign result = a_minus_q[`COEFF_WIDTH] ? a_reduced[`COEFF_WIDTH-1:0]
                                             : a_minus_q[`COEFF_WIDTH-1:0];
endmodule