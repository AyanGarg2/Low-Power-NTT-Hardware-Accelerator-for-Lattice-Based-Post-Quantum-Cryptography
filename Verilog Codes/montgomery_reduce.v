// ============================================================================
// Montgomery Modular Reduction  (Algorithm 3)
//
//   Input  : a  (32-bit product, range [0, R·q-1])
//   Output : a · R^{-1} mod q   (16 bits)
//
//   Constants loaded at run-time:
//     q       - prime modulus
//     q_prime - -q^{-1} mod R       (R = 2^16)
// ============================================================================

`include "ntt_defines.vh"

module montgomery_reduce (
    input  wire [`COEFF_WIDTH-1:0]  q,
    input  wire [`COEFF_WIDTH-1:0]  q_prime,   // -q^{-1} mod R
    input  wire [`MULT_WIDTH-1:0]   a_in,
    output wire [`COEFF_WIDTH-1:0]  result
);

    // Step 1 : u = (a · q') mod R   - keep lower 16 bits only
    wire [`MULT_WIDTH-1:0] a_times_qp = a_in[`COEFF_WIDTH-1:0] * q_prime;
    wire [`COEFF_WIDTH-1:0] u         = a_times_qp[`COEFF_WIDTH-1:0];

    // Step 2 : t = (a + u·q) >> log(R)
    wire [`MULT_WIDTH-1:0]  u_times_q = u * q;
    wire [`MULT_WIDTH+1:0]  t_full    = {2'b0, a_in} + {2'b0, u_times_q};
    wire [`COEFF_WIDTH:0]   t_shifted = t_full[`MULT_WIDTH:`COEFF_WIDTH];  // 17 bits

    // Step 3 : conditional subtraction
    wire [`COEFF_WIDTH:0] t_minus_q = t_shifted - {1'b0, q};

    assign result = t_minus_q[`COEFF_WIDTH] ? t_shifted[`COEFF_WIDTH-1:0]
                                             : t_minus_q[`COEFF_WIDTH-1:0];
endmodule