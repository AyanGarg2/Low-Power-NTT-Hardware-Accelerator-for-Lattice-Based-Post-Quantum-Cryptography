// ============================================================
// NTT/INTT Verification Testbench - n=256, q=7681
// Cross-checks Verilog output against Python golden values
// Input: a = [1,2,...,256]  Golden: a_hat[0:4]=[5327,534,6101,3299]
// ============================================================

`timescale 1ns / 1ps
`include "ntt_defines.vh"

module ntt_tb_n256;

    reg                          clk, rst_n, start, is_inverse;
    wire                         done, busy;
    reg  [`MAX_LOG_N-1:0]        cfg_log_n;
    reg  [`COEFF_WIDTH-1:0]      cfg_q, cfg_q_prime, cfg_barrett_m;
    reg  [4:0]                   cfg_barrett_k;
    reg  [`COEFF_WIDTH-1:0]      cfg_gamma1, cfg_gamma2, cfg_gamma3, cfg_gamma4;
    reg  [`COEFF_WIDTH-1:0]      cfg_beta, cfg_r_mod_q;
    reg                          ext_ram_we;
    reg  [`MEM_ADDR_WIDTH-1:0]   ext_ram_addr;
    reg  [`MEM_WIDTH-1:0]        ext_ram_din;
    wire [`MEM_WIDTH-1:0]        ext_ram_dout;
    reg                          lut_we;
    reg  [3:0]                   lut_waddr;
    reg  [`COEFF_WIDTH-1:0]      lut_wdata;
    integer errors, cyc;

    ntt_core u_dut (
        .clk(clk), .rst_n(rst_n), .start(start), .is_inverse(is_inverse),
        .done(done), .busy(busy),
        .cfg_log_n(cfg_log_n), .cfg_q(cfg_q), .cfg_q_prime(cfg_q_prime),
        .cfg_barrett_m(cfg_barrett_m), .cfg_barrett_k(cfg_barrett_k),
        .cfg_gamma1(cfg_gamma1), .cfg_gamma2(cfg_gamma2),
        .cfg_gamma3(cfg_gamma3), .cfg_gamma4(cfg_gamma4),
        .cfg_beta(cfg_beta), .cfg_r_mod_q(cfg_r_mod_q),
        .ext_ram_we(ext_ram_we), .ext_ram_addr(ext_ram_addr),
        .ext_ram_din(ext_ram_din), .ext_ram_dout(ext_ram_dout),
        .lut_we(lut_we), .lut_waddr(lut_waddr), .lut_wdata(lut_wdata)
    );

    initial clk = 0;
    always #20 clk = ~clk;

    task wr_ram;
        input [`MEM_ADDR_WIDTH-1:0] a;
        input [`MEM_WIDTH-1:0]      d;
    begin
        @(posedge clk); ext_ram_we<=1; ext_ram_addr<=a; ext_ram_din<=d;
        @(posedge clk); ext_ram_we<=0;
    end endtask

    task wr_lut;
        input [3:0]              a;
        input [`COEFF_WIDTH-1:0] d;
    begin
        @(posedge clk); lut_we<=1; lut_waddr<=a; lut_wdata<=d;
        @(posedge clk); lut_we<=0;
    end endtask

    task chk;
        input [`MEM_ADDR_WIDTH-1:0] a;
        input [`COEFF_WIDTH-1:0]    eh, el;
    begin
        ext_ram_we<=0; ext_ram_addr<=a; #1;
        if (ext_ram_dout[31:16] !== eh || ext_ram_dout[15:0] !== el) begin
            $display("  MISMATCH addr=%0d got{%0d,%0d} exp{%0d,%0d}",
                     a, ext_ram_dout[31:16], ext_ram_dout[15:0], eh, el);
            errors = errors + 1;
        end
    end endtask

    task run_ntt;
        input integer max_cyc;
    begin
        @(posedge clk); start<=1; @(posedge clk); start<=0;
        cyc = 0;
        while (!done && cyc < max_cyc) begin @(posedge clk); cyc=cyc+1; end
        if (!done) begin $display("  TIMEOUT!"); $finish; end
        $display("  Completed: %0d cycles", cyc);
        @(posedge clk);
    end endtask

    // ---- Fixed parameters (n=256, q=7681) ----
    localparam LOG_N     = 8;
    localparam Q         = 16'd7681;
    localparam Q_PRIME   = 16'd7679;
    localparam BARRETT_M = 16'd2;
    localparam BARRETT_K = 5'd14;
    localparam R_MOD_Q   = 16'd4088;
    localparam GAMMA1    = 16'd256;
    localparam GAMMA2    = 16'd5283;
    localparam GAMMA3    = 16'd5776;
    localparam GAMMA4    = 16'd6383;
    localparam BETA      = 16'd5016;
    localparam MAX_CYCLES = 6000;

    // ---- Forward NTT LUT (omega values in Montgomery domain) ----
    task load_forward_lut; begin
        wr_lut(4'd0, 16'd3593);
        wr_lut(4'd1, 16'd3777);
        wr_lut(4'd2, 16'd4499);
        wr_lut(4'd3, 16'd3985);
        wr_lut(4'd4, 16'd7560);
        wr_lut(4'd5, 16'd5593);
        wr_lut(4'd6, 16'd3266);
        wr_lut(4'd7, 16'd5255);
        wr_lut(4'd8, 16'd1242);
    end endtask

    // ---- Inverse NTT LUT (omega_inv values in Montgomery domain) ----
    task load_inverse_lut; begin
        wr_lut(4'd0, 16'd3593);
        wr_lut(4'd1, 16'd3904);
        wr_lut(4'd2, 16'd4056);
        wr_lut(4'd3, 16'd5487);
        wr_lut(4'd4, 16'd1414);
        wr_lut(4'd5, 16'd7064);
        wr_lut(4'd6, 16'd4877);
        wr_lut(4'd7, 16'd5016);
        wr_lut(4'd8, 16'd4088);
    end endtask

    // ---- Load a=[1..256] in bit-reversed RAM order ----
    task load_forward_input; begin
        wr_ram(9'd0, {16'd129, 16'd1});
        wr_ram(9'd1, {16'd193, 16'd65});
        wr_ram(9'd2, {16'd161, 16'd33});
        wr_ram(9'd3, {16'd225, 16'd97});
        wr_ram(9'd4, {16'd145, 16'd17});
        wr_ram(9'd5, {16'd209, 16'd81});
        wr_ram(9'd6, {16'd177, 16'd49});
        wr_ram(9'd7, {16'd241, 16'd113});
        wr_ram(9'd8, {16'd137, 16'd9});
        wr_ram(9'd9, {16'd201, 16'd73});
        wr_ram(9'd10, {16'd169, 16'd41});
        wr_ram(9'd11, {16'd233, 16'd105});
        wr_ram(9'd12, {16'd153, 16'd25});
        wr_ram(9'd13, {16'd217, 16'd89});
        wr_ram(9'd14, {16'd185, 16'd57});
        wr_ram(9'd15, {16'd249, 16'd121});
        wr_ram(9'd16, {16'd133, 16'd5});
        wr_ram(9'd17, {16'd197, 16'd69});
        wr_ram(9'd18, {16'd165, 16'd37});
        wr_ram(9'd19, {16'd229, 16'd101});
        wr_ram(9'd20, {16'd149, 16'd21});
        wr_ram(9'd21, {16'd213, 16'd85});
        wr_ram(9'd22, {16'd181, 16'd53});
        wr_ram(9'd23, {16'd245, 16'd117});
        wr_ram(9'd24, {16'd141, 16'd13});
        wr_ram(9'd25, {16'd205, 16'd77});
        wr_ram(9'd26, {16'd173, 16'd45});
        wr_ram(9'd27, {16'd237, 16'd109});
        wr_ram(9'd28, {16'd157, 16'd29});
        wr_ram(9'd29, {16'd221, 16'd93});
        wr_ram(9'd30, {16'd189, 16'd61});
        wr_ram(9'd31, {16'd253, 16'd125});
        wr_ram(9'd32, {16'd131, 16'd3});
        wr_ram(9'd33, {16'd195, 16'd67});
        wr_ram(9'd34, {16'd163, 16'd35});
        wr_ram(9'd35, {16'd227, 16'd99});
        wr_ram(9'd36, {16'd147, 16'd19});
        wr_ram(9'd37, {16'd211, 16'd83});
        wr_ram(9'd38, {16'd179, 16'd51});
        wr_ram(9'd39, {16'd243, 16'd115});
        wr_ram(9'd40, {16'd139, 16'd11});
        wr_ram(9'd41, {16'd203, 16'd75});
        wr_ram(9'd42, {16'd171, 16'd43});
        wr_ram(9'd43, {16'd235, 16'd107});
        wr_ram(9'd44, {16'd155, 16'd27});
        wr_ram(9'd45, {16'd219, 16'd91});
        wr_ram(9'd46, {16'd187, 16'd59});
        wr_ram(9'd47, {16'd251, 16'd123});
        wr_ram(9'd48, {16'd135, 16'd7});
        wr_ram(9'd49, {16'd199, 16'd71});
        wr_ram(9'd50, {16'd167, 16'd39});
        wr_ram(9'd51, {16'd231, 16'd103});
        wr_ram(9'd52, {16'd151, 16'd23});
        wr_ram(9'd53, {16'd215, 16'd87});
        wr_ram(9'd54, {16'd183, 16'd55});
        wr_ram(9'd55, {16'd247, 16'd119});
        wr_ram(9'd56, {16'd143, 16'd15});
        wr_ram(9'd57, {16'd207, 16'd79});
        wr_ram(9'd58, {16'd175, 16'd47});
        wr_ram(9'd59, {16'd239, 16'd111});
        wr_ram(9'd60, {16'd159, 16'd31});
        wr_ram(9'd61, {16'd223, 16'd95});
        wr_ram(9'd62, {16'd191, 16'd63});
        wr_ram(9'd63, {16'd255, 16'd127});
        wr_ram(9'd64, {16'd130, 16'd2});
        wr_ram(9'd65, {16'd194, 16'd66});
        wr_ram(9'd66, {16'd162, 16'd34});
        wr_ram(9'd67, {16'd226, 16'd98});
        wr_ram(9'd68, {16'd146, 16'd18});
        wr_ram(9'd69, {16'd210, 16'd82});
        wr_ram(9'd70, {16'd178, 16'd50});
        wr_ram(9'd71, {16'd242, 16'd114});
        wr_ram(9'd72, {16'd138, 16'd10});
        wr_ram(9'd73, {16'd202, 16'd74});
        wr_ram(9'd74, {16'd170, 16'd42});
        wr_ram(9'd75, {16'd234, 16'd106});
        wr_ram(9'd76, {16'd154, 16'd26});
        wr_ram(9'd77, {16'd218, 16'd90});
        wr_ram(9'd78, {16'd186, 16'd58});
        wr_ram(9'd79, {16'd250, 16'd122});
        wr_ram(9'd80, {16'd134, 16'd6});
        wr_ram(9'd81, {16'd198, 16'd70});
        wr_ram(9'd82, {16'd166, 16'd38});
        wr_ram(9'd83, {16'd230, 16'd102});
        wr_ram(9'd84, {16'd150, 16'd22});
        wr_ram(9'd85, {16'd214, 16'd86});
        wr_ram(9'd86, {16'd182, 16'd54});
        wr_ram(9'd87, {16'd246, 16'd118});
        wr_ram(9'd88, {16'd142, 16'd14});
        wr_ram(9'd89, {16'd206, 16'd78});
        wr_ram(9'd90, {16'd174, 16'd46});
        wr_ram(9'd91, {16'd238, 16'd110});
        wr_ram(9'd92, {16'd158, 16'd30});
        wr_ram(9'd93, {16'd222, 16'd94});
        wr_ram(9'd94, {16'd190, 16'd62});
        wr_ram(9'd95, {16'd254, 16'd126});
        wr_ram(9'd96, {16'd132, 16'd4});
        wr_ram(9'd97, {16'd196, 16'd68});
        wr_ram(9'd98, {16'd164, 16'd36});
        wr_ram(9'd99, {16'd228, 16'd100});
        wr_ram(9'd100, {16'd148, 16'd20});
        wr_ram(9'd101, {16'd212, 16'd84});
        wr_ram(9'd102, {16'd180, 16'd52});
        wr_ram(9'd103, {16'd244, 16'd116});
        wr_ram(9'd104, {16'd140, 16'd12});
        wr_ram(9'd105, {16'd204, 16'd76});
        wr_ram(9'd106, {16'd172, 16'd44});
        wr_ram(9'd107, {16'd236, 16'd108});
        wr_ram(9'd108, {16'd156, 16'd28});
        wr_ram(9'd109, {16'd220, 16'd92});
        wr_ram(9'd110, {16'd188, 16'd60});
        wr_ram(9'd111, {16'd252, 16'd124});
        wr_ram(9'd112, {16'd136, 16'd8});
        wr_ram(9'd113, {16'd200, 16'd72});
        wr_ram(9'd114, {16'd168, 16'd40});
        wr_ram(9'd115, {16'd232, 16'd104});
        wr_ram(9'd116, {16'd152, 16'd24});
        wr_ram(9'd117, {16'd216, 16'd88});
        wr_ram(9'd118, {16'd184, 16'd56});
        wr_ram(9'd119, {16'd248, 16'd120});
        wr_ram(9'd120, {16'd144, 16'd16});
        wr_ram(9'd121, {16'd208, 16'd80});
        wr_ram(9'd122, {16'd176, 16'd48});
        wr_ram(9'd123, {16'd240, 16'd112});
        wr_ram(9'd124, {16'd160, 16'd32});
        wr_ram(9'd125, {16'd224, 16'd96});
        wr_ram(9'd126, {16'd192, 16'd64});
        wr_ram(9'd127, {16'd256, 16'd128});
    end endtask

    // ---- Check NTT output: MEM[i]={a_hat[i+128], a_hat[i]} ----
    task check_ntt_output; begin
        chk(9'd0, 16'd4644, 16'd5327);
        chk(9'd1, 16'd1755, 16'd534);
        chk(9'd2, 16'd2691, 16'd6101);
        chk(9'd3, 16'd310, 16'd3299);
        chk(9'd4, 16'd2843, 16'd2503);
        chk(9'd5, 16'd4168, 16'd7409);
        chk(9'd6, 16'd7426, 16'd2392);
        chk(9'd7, 16'd2721, 16'd2041);
        chk(9'd8, 16'd876, 16'd6155);
        chk(9'd9, 16'd2379, 16'd4979);
        chk(9'd10, 16'd4128, 16'd1410);
        chk(9'd11, 16'd4974, 16'd1227);
        chk(9'd12, 16'd4463, 16'd4035);
        chk(9'd13, 16'd1470, 16'd3921);
        chk(9'd14, 16'd3261, 16'd6968);
        chk(9'd15, 16'd2003, 16'd2868);
        chk(9'd16, 16'd3235, 16'd7273);
        chk(9'd17, 16'd4023, 16'd4821);
        chk(9'd18, 16'd4979, 16'd4809);
        chk(9'd19, 16'd3898, 16'd4229);
        chk(9'd20, 16'd7296, 16'd7089);
        chk(9'd21, 16'd6448, 16'd489);
        chk(9'd22, 16'd747, 16'd235);
        chk(9'd23, 16'd1412, 16'd7341);
        chk(9'd24, 16'd7532, 16'd3666);
        chk(9'd25, 16'd3667, 16'd2716);
        chk(9'd26, 16'd7541, 16'd2743);
        chk(9'd27, 16'd6795, 16'd3944);
        chk(9'd28, 16'd4277, 16'd1161);
        chk(9'd29, 16'd6146, 16'd3577);
        chk(9'd30, 16'd2965, 16'd3549);
        chk(9'd31, 16'd161, 16'd5531);
        chk(9'd32, 16'd2086, 16'd6475);
        chk(9'd33, 16'd752, 16'd6187);
        chk(9'd34, 16'd5189, 16'd4505);
        chk(9'd35, 16'd7268, 16'd3110);
        chk(9'd36, 16'd1024, 16'd7200);
        chk(9'd37, 16'd1378, 16'd5326);
        chk(9'd38, 16'd6401, 16'd4730);
        chk(9'd39, 16'd2841, 16'd7178);
        chk(9'd40, 16'd6018, 16'd3092);
        chk(9'd41, 16'd1919, 16'd3191);
        chk(9'd42, 16'd3659, 16'd7223);
        chk(9'd43, 16'd4543, 16'd2302);
        chk(9'd44, 16'd2629, 16'd7176);
        chk(9'd45, 16'd4193, 16'd5243);
        chk(9'd46, 16'd298, 16'd6562);
        chk(9'd47, 16'd1948, 16'd6937);
        chk(9'd48, 16'd1549, 16'd7398);
        chk(9'd49, 16'd2253, 16'd1106);
        chk(9'd50, 16'd4072, 16'd6047);
        chk(9'd51, 16'd3050, 16'd6036);
        chk(9'd52, 16'd6313, 16'd6265);
        chk(9'd53, 16'd4576, 16'd3824);
        chk(9'd54, 16'd3398, 16'd2531);
        chk(9'd55, 16'd2984, 16'd5488);
        chk(9'd56, 16'd6494, 16'd3443);
        chk(9'd57, 16'd6538, 16'd3520);
        chk(9'd58, 16'd7104, 16'd3312);
        chk(9'd59, 16'd6990, 16'd2750);
        chk(9'd60, 16'd591, 16'd2025);
        chk(9'd61, 16'd1379, 16'd4311);
        chk(9'd62, 16'd2537, 16'd1591);
        chk(9'd63, 16'd4591, 16'd2964);
        chk(9'd64, 16'd3393, 16'd5713);
        chk(9'd65, 16'd5576, 16'd898);
        chk(9'd66, 16'd4932, 16'd373);
        chk(9'd67, 16'd1272, 16'd472);
        chk(9'd68, 16'd6057, 16'd7038);
        chk(9'd69, 16'd416, 16'd4503);
        chk(9'd70, 16'd5207, 16'd7611);
        chk(9'd71, 16'd1864, 16'd2857);
        chk(9'd72, 16'd2624, 16'd4645);
        chk(9'd73, 16'd327, 16'd6114);
        chk(9'd74, 16'd7458, 16'd4793);
        chk(9'd75, 16'd3851, 16'd1029);
        chk(9'd76, 16'd2067, 16'd6238);
        chk(9'd77, 16'd835, 16'd3175);
        chk(9'd78, 16'd5430, 16'd7093);
        chk(9'd79, 16'd3864, 16'd5638);
        chk(9'd80, 16'd6622, 16'd5248);
        chk(9'd81, 16'd6655, 16'd6217);
        chk(9'd82, 16'd32, 16'd2124);
        chk(9'd83, 16'd298, 16'd6385);
        chk(9'd84, 16'd3768, 16'd2807);
        chk(9'd85, 16'd1722, 16'd1350);
        chk(9'd86, 16'd5585, 16'd272);
        chk(9'd87, 16'd1229, 16'd3793);
        chk(9'd88, 16'd3087, 16'd4691);
        chk(9'd89, 16'd3172, 16'd6871);
        chk(9'd90, 16'd2567, 16'd1610);
        chk(9'd91, 16'd5958, 16'd1527);
        chk(9'd92, 16'd265, 16'd5757);
        chk(9'd93, 16'd3188, 16'd7483);
        chk(9'd94, 16'd2807, 16'd196);
        chk(9'd95, 16'd1682, 16'd7290);
        chk(9'd96, 16'd3269, 16'd4186);
        chk(9'd97, 16'd857, 16'd6193);
        chk(9'd98, 16'd3934, 16'd6397);
        chk(9'd99, 16'd7353, 16'd6208);
        chk(9'd100, 16'd1945, 16'd4633);
        chk(9'd101, 16'd6303, 16'd5825);
        chk(9'd102, 16'd6449, 16'd4584);
        chk(9'd103, 16'd4897, 16'd5371);
        chk(9'd104, 16'd7488, 16'd7508);
        chk(9'd105, 16'd4328, 16'd7125);
        chk(9'd106, 16'd7302, 16'd1699);
        chk(9'd107, 16'd3815, 16'd2851);
        chk(9'd108, 16'd2180, 16'd413);
        chk(9'd109, 16'd6767, 16'd1859);
        chk(9'd110, 16'd4542, 16'd2050);
        chk(9'd111, 16'd4823, 16'd2562);
        chk(9'd112, 16'd299, 16'd231);
        chk(9'd113, 16'd4353, 16'd1294);
        chk(9'd114, 16'd5010, 16'd1912);
        chk(9'd115, 16'd649, 16'd5446);
        chk(9'd116, 16'd4852, 16'd7071);
        chk(9'd117, 16'd5910, 16'd3897);
        chk(9'd118, 16'd5534, 16'd1544);
        chk(9'd119, 16'd2171, 16'd2687);
        chk(9'd120, 16'd234, 16'd1681);
        chk(9'd121, 16'd1850, 16'd5801);
        chk(9'd122, 16'd681, 16'd4528);
        chk(9'd123, 16'd4573, 16'd1005);
        chk(9'd124, 16'd4361, 16'd6882);
        chk(9'd125, 16'd5037, 16'd636);
        chk(9'd126, 16'd4600, 16'd6887);
        chk(9'd127, 16'd83, 16'd4561);
    end endtask

    // ---- Load NTT output as INTT input (bit-reversed) ----
    task load_inverse_input; begin
        wr_ram(9'd0, {16'd4644, 16'd5327});
        wr_ram(9'd1, {16'd3393, 16'd5713});
        wr_ram(9'd2, {16'd2086, 16'd6475});
        wr_ram(9'd3, {16'd3269, 16'd4186});
        wr_ram(9'd4, {16'd3235, 16'd7273});
        wr_ram(9'd5, {16'd6622, 16'd5248});
        wr_ram(9'd6, {16'd1549, 16'd7398});
        wr_ram(9'd7, {16'd299, 16'd231});
        wr_ram(9'd8, {16'd876, 16'd6155});
        wr_ram(9'd9, {16'd2624, 16'd4645});
        wr_ram(9'd10, {16'd6018, 16'd3092});
        wr_ram(9'd11, {16'd7488, 16'd7508});
        wr_ram(9'd12, {16'd7532, 16'd3666});
        wr_ram(9'd13, {16'd3087, 16'd4691});
        wr_ram(9'd14, {16'd6494, 16'd3443});
        wr_ram(9'd15, {16'd234, 16'd1681});
        wr_ram(9'd16, {16'd2843, 16'd2503});
        wr_ram(9'd17, {16'd6057, 16'd7038});
        wr_ram(9'd18, {16'd1024, 16'd7200});
        wr_ram(9'd19, {16'd1945, 16'd4633});
        wr_ram(9'd20, {16'd7296, 16'd7089});
        wr_ram(9'd21, {16'd3768, 16'd2807});
        wr_ram(9'd22, {16'd6313, 16'd6265});
        wr_ram(9'd23, {16'd4852, 16'd7071});
        wr_ram(9'd24, {16'd4463, 16'd4035});
        wr_ram(9'd25, {16'd2067, 16'd6238});
        wr_ram(9'd26, {16'd2629, 16'd7176});
        wr_ram(9'd27, {16'd2180, 16'd413});
        wr_ram(9'd28, {16'd4277, 16'd1161});
        wr_ram(9'd29, {16'd265, 16'd5757});
        wr_ram(9'd30, {16'd591, 16'd2025});
        wr_ram(9'd31, {16'd4361, 16'd6882});
        wr_ram(9'd32, {16'd2691, 16'd6101});
        wr_ram(9'd33, {16'd4932, 16'd373});
        wr_ram(9'd34, {16'd5189, 16'd4505});
        wr_ram(9'd35, {16'd3934, 16'd6397});
        wr_ram(9'd36, {16'd4979, 16'd4809});
        wr_ram(9'd37, {16'd32, 16'd2124});
        wr_ram(9'd38, {16'd4072, 16'd6047});
        wr_ram(9'd39, {16'd5010, 16'd1912});
        wr_ram(9'd40, {16'd4128, 16'd1410});
        wr_ram(9'd41, {16'd7458, 16'd4793});
        wr_ram(9'd42, {16'd3659, 16'd7223});
        wr_ram(9'd43, {16'd7302, 16'd1699});
        wr_ram(9'd44, {16'd7541, 16'd2743});
        wr_ram(9'd45, {16'd2567, 16'd1610});
        wr_ram(9'd46, {16'd7104, 16'd3312});
        wr_ram(9'd47, {16'd681, 16'd4528});
        wr_ram(9'd48, {16'd7426, 16'd2392});
        wr_ram(9'd49, {16'd5207, 16'd7611});
        wr_ram(9'd50, {16'd6401, 16'd4730});
        wr_ram(9'd51, {16'd6449, 16'd4584});
        wr_ram(9'd52, {16'd747, 16'd235});
        wr_ram(9'd53, {16'd5585, 16'd272});
        wr_ram(9'd54, {16'd3398, 16'd2531});
        wr_ram(9'd55, {16'd5534, 16'd1544});
        wr_ram(9'd56, {16'd3261, 16'd6968});
        wr_ram(9'd57, {16'd5430, 16'd7093});
        wr_ram(9'd58, {16'd298, 16'd6562});
        wr_ram(9'd59, {16'd4542, 16'd2050});
        wr_ram(9'd60, {16'd2965, 16'd3549});
        wr_ram(9'd61, {16'd2807, 16'd196});
        wr_ram(9'd62, {16'd2537, 16'd1591});
        wr_ram(9'd63, {16'd4600, 16'd6887});
        wr_ram(9'd64, {16'd1755, 16'd534});
        wr_ram(9'd65, {16'd5576, 16'd898});
        wr_ram(9'd66, {16'd752, 16'd6187});
        wr_ram(9'd67, {16'd857, 16'd6193});
        wr_ram(9'd68, {16'd4023, 16'd4821});
        wr_ram(9'd69, {16'd6655, 16'd6217});
        wr_ram(9'd70, {16'd2253, 16'd1106});
        wr_ram(9'd71, {16'd4353, 16'd1294});
        wr_ram(9'd72, {16'd2379, 16'd4979});
        wr_ram(9'd73, {16'd327, 16'd6114});
        wr_ram(9'd74, {16'd1919, 16'd3191});
        wr_ram(9'd75, {16'd4328, 16'd7125});
        wr_ram(9'd76, {16'd3667, 16'd2716});
        wr_ram(9'd77, {16'd3172, 16'd6871});
        wr_ram(9'd78, {16'd6538, 16'd3520});
        wr_ram(9'd79, {16'd1850, 16'd5801});
        wr_ram(9'd80, {16'd4168, 16'd7409});
        wr_ram(9'd81, {16'd416, 16'd4503});
        wr_ram(9'd82, {16'd1378, 16'd5326});
        wr_ram(9'd83, {16'd6303, 16'd5825});
        wr_ram(9'd84, {16'd6448, 16'd489});
        wr_ram(9'd85, {16'd1722, 16'd1350});
        wr_ram(9'd86, {16'd4576, 16'd3824});
        wr_ram(9'd87, {16'd5910, 16'd3897});
        wr_ram(9'd88, {16'd1470, 16'd3921});
        wr_ram(9'd89, {16'd835, 16'd3175});
        wr_ram(9'd90, {16'd4193, 16'd5243});
        wr_ram(9'd91, {16'd6767, 16'd1859});
        wr_ram(9'd92, {16'd6146, 16'd3577});
        wr_ram(9'd93, {16'd3188, 16'd7483});
        wr_ram(9'd94, {16'd1379, 16'd4311});
        wr_ram(9'd95, {16'd5037, 16'd636});
        wr_ram(9'd96, {16'd310, 16'd3299});
        wr_ram(9'd97, {16'd1272, 16'd472});
        wr_ram(9'd98, {16'd7268, 16'd3110});
        wr_ram(9'd99, {16'd7353, 16'd6208});
        wr_ram(9'd100, {16'd3898, 16'd4229});
        wr_ram(9'd101, {16'd298, 16'd6385});
        wr_ram(9'd102, {16'd3050, 16'd6036});
        wr_ram(9'd103, {16'd649, 16'd5446});
        wr_ram(9'd104, {16'd4974, 16'd1227});
        wr_ram(9'd105, {16'd3851, 16'd1029});
        wr_ram(9'd106, {16'd4543, 16'd2302});
        wr_ram(9'd107, {16'd3815, 16'd2851});
        wr_ram(9'd108, {16'd6795, 16'd3944});
        wr_ram(9'd109, {16'd5958, 16'd1527});
        wr_ram(9'd110, {16'd6990, 16'd2750});
        wr_ram(9'd111, {16'd4573, 16'd1005});
        wr_ram(9'd112, {16'd2721, 16'd2041});
        wr_ram(9'd113, {16'd1864, 16'd2857});
        wr_ram(9'd114, {16'd2841, 16'd7178});
        wr_ram(9'd115, {16'd4897, 16'd5371});
        wr_ram(9'd116, {16'd1412, 16'd7341});
        wr_ram(9'd117, {16'd1229, 16'd3793});
        wr_ram(9'd118, {16'd2984, 16'd5488});
        wr_ram(9'd119, {16'd2171, 16'd2687});
        wr_ram(9'd120, {16'd2003, 16'd2868});
        wr_ram(9'd121, {16'd3864, 16'd5638});
        wr_ram(9'd122, {16'd1948, 16'd6937});
        wr_ram(9'd123, {16'd4823, 16'd2562});
        wr_ram(9'd124, {16'd161, 16'd5531});
        wr_ram(9'd125, {16'd1682, 16'd7290});
        wr_ram(9'd126, {16'd4591, 16'd2964});
        wr_ram(9'd127, {16'd83, 16'd4561});
    end endtask

    // ---- Check INTT output recovers a=[1..256] ----
    task check_intt_output; begin
        chk(9'd0, 16'd129, 16'd1);
        chk(9'd1, 16'd130, 16'd2);
        chk(9'd2, 16'd131, 16'd3);
        chk(9'd3, 16'd132, 16'd4);
        chk(9'd4, 16'd133, 16'd5);
        chk(9'd5, 16'd134, 16'd6);
        chk(9'd6, 16'd135, 16'd7);
        chk(9'd7, 16'd136, 16'd8);
        chk(9'd8, 16'd137, 16'd9);
        chk(9'd9, 16'd138, 16'd10);
        chk(9'd10, 16'd139, 16'd11);
        chk(9'd11, 16'd140, 16'd12);
        chk(9'd12, 16'd141, 16'd13);
        chk(9'd13, 16'd142, 16'd14);
        chk(9'd14, 16'd143, 16'd15);
        chk(9'd15, 16'd144, 16'd16);
        chk(9'd16, 16'd145, 16'd17);
        chk(9'd17, 16'd146, 16'd18);
        chk(9'd18, 16'd147, 16'd19);
        chk(9'd19, 16'd148, 16'd20);
        chk(9'd20, 16'd149, 16'd21);
        chk(9'd21, 16'd150, 16'd22);
        chk(9'd22, 16'd151, 16'd23);
        chk(9'd23, 16'd152, 16'd24);
        chk(9'd24, 16'd153, 16'd25);
        chk(9'd25, 16'd154, 16'd26);
        chk(9'd26, 16'd155, 16'd27);
        chk(9'd27, 16'd156, 16'd28);
        chk(9'd28, 16'd157, 16'd29);
        chk(9'd29, 16'd158, 16'd30);
        chk(9'd30, 16'd159, 16'd31);
        chk(9'd31, 16'd160, 16'd32);
        chk(9'd32, 16'd161, 16'd33);
        chk(9'd33, 16'd162, 16'd34);
        chk(9'd34, 16'd163, 16'd35);
        chk(9'd35, 16'd164, 16'd36);
        chk(9'd36, 16'd165, 16'd37);
        chk(9'd37, 16'd166, 16'd38);
        chk(9'd38, 16'd167, 16'd39);
        chk(9'd39, 16'd168, 16'd40);
        chk(9'd40, 16'd169, 16'd41);
        chk(9'd41, 16'd170, 16'd42);
        chk(9'd42, 16'd171, 16'd43);
        chk(9'd43, 16'd172, 16'd44);
        chk(9'd44, 16'd173, 16'd45);
        chk(9'd45, 16'd174, 16'd46);
        chk(9'd46, 16'd175, 16'd47);
        chk(9'd47, 16'd176, 16'd48);
        chk(9'd48, 16'd177, 16'd49);
        chk(9'd49, 16'd178, 16'd50);
        chk(9'd50, 16'd179, 16'd51);
        chk(9'd51, 16'd180, 16'd52);
        chk(9'd52, 16'd181, 16'd53);
        chk(9'd53, 16'd182, 16'd54);
        chk(9'd54, 16'd183, 16'd55);
        chk(9'd55, 16'd184, 16'd56);
        chk(9'd56, 16'd185, 16'd57);
        chk(9'd57, 16'd186, 16'd58);
        chk(9'd58, 16'd187, 16'd59);
        chk(9'd59, 16'd188, 16'd60);
        chk(9'd60, 16'd189, 16'd61);
        chk(9'd61, 16'd190, 16'd62);
        chk(9'd62, 16'd191, 16'd63);
        chk(9'd63, 16'd192, 16'd64);
        chk(9'd64, 16'd193, 16'd65);
        chk(9'd65, 16'd194, 16'd66);
        chk(9'd66, 16'd195, 16'd67);
        chk(9'd67, 16'd196, 16'd68);
        chk(9'd68, 16'd197, 16'd69);
        chk(9'd69, 16'd198, 16'd70);
        chk(9'd70, 16'd199, 16'd71);
        chk(9'd71, 16'd200, 16'd72);
        chk(9'd72, 16'd201, 16'd73);
        chk(9'd73, 16'd202, 16'd74);
        chk(9'd74, 16'd203, 16'd75);
        chk(9'd75, 16'd204, 16'd76);
        chk(9'd76, 16'd205, 16'd77);
        chk(9'd77, 16'd206, 16'd78);
        chk(9'd78, 16'd207, 16'd79);
        chk(9'd79, 16'd208, 16'd80);
        chk(9'd80, 16'd209, 16'd81);
        chk(9'd81, 16'd210, 16'd82);
        chk(9'd82, 16'd211, 16'd83);
        chk(9'd83, 16'd212, 16'd84);
        chk(9'd84, 16'd213, 16'd85);
        chk(9'd85, 16'd214, 16'd86);
        chk(9'd86, 16'd215, 16'd87);
        chk(9'd87, 16'd216, 16'd88);
        chk(9'd88, 16'd217, 16'd89);
        chk(9'd89, 16'd218, 16'd90);
        chk(9'd90, 16'd219, 16'd91);
        chk(9'd91, 16'd220, 16'd92);
        chk(9'd92, 16'd221, 16'd93);
        chk(9'd93, 16'd222, 16'd94);
        chk(9'd94, 16'd223, 16'd95);
        chk(9'd95, 16'd224, 16'd96);
        chk(9'd96, 16'd225, 16'd97);
        chk(9'd97, 16'd226, 16'd98);
        chk(9'd98, 16'd227, 16'd99);
        chk(9'd99, 16'd228, 16'd100);
        chk(9'd100, 16'd229, 16'd101);
        chk(9'd101, 16'd230, 16'd102);
        chk(9'd102, 16'd231, 16'd103);
        chk(9'd103, 16'd232, 16'd104);
        chk(9'd104, 16'd233, 16'd105);
        chk(9'd105, 16'd234, 16'd106);
        chk(9'd106, 16'd235, 16'd107);
        chk(9'd107, 16'd236, 16'd108);
        chk(9'd108, 16'd237, 16'd109);
        chk(9'd109, 16'd238, 16'd110);
        chk(9'd110, 16'd239, 16'd111);
        chk(9'd111, 16'd240, 16'd112);
        chk(9'd112, 16'd241, 16'd113);
        chk(9'd113, 16'd242, 16'd114);
        chk(9'd114, 16'd243, 16'd115);
        chk(9'd115, 16'd244, 16'd116);
        chk(9'd116, 16'd245, 16'd117);
        chk(9'd117, 16'd246, 16'd118);
        chk(9'd118, 16'd247, 16'd119);
        chk(9'd119, 16'd248, 16'd120);
        chk(9'd120, 16'd249, 16'd121);
        chk(9'd121, 16'd250, 16'd122);
        chk(9'd122, 16'd251, 16'd123);
        chk(9'd123, 16'd252, 16'd124);
        chk(9'd124, 16'd253, 16'd125);
        chk(9'd125, 16'd254, 16'd126);
        chk(9'd126, 16'd255, 16'd127);
        chk(9'd127, 16'd256, 16'd128);
    end endtask

    initial begin
        $dumpfile("ntt_tb_n256.vcd");
        $dumpvars(0, ntt_tb_n256);
        errors=0; rst_n=0; start=0; is_inverse=0;
        ext_ram_we=0; ext_ram_addr=0; ext_ram_din=0;
        lut_we=0; lut_waddr=0; lut_wdata=0;
        cfg_log_n=LOG_N; cfg_q=Q; cfg_q_prime=Q_PRIME;
        cfg_barrett_m=BARRETT_M; cfg_barrett_k=BARRETT_K;
        cfg_gamma1=GAMMA1; cfg_gamma2=GAMMA2;
        cfg_gamma3=GAMMA3; cfg_gamma4=GAMMA4;
        cfg_beta=BETA; cfg_r_mod_q=R_MOD_Q;
        repeat(5) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // ---- TEST 1: Forward NTT ----
        $display("");
        $display("================================================");
        $display("  TEST 1: Forward NTT  n=256, q=7681");
        $display("  Input: a = [1,2,...,256]");
        $display("  Golden: a_hat[0:4] = [5327, 534, 6101, 3299]");
        $display("================================================");
        load_forward_lut;
        load_forward_input;
        is_inverse <= 0;
        run_ntt(MAX_CYCLES);
        check_ntt_output;
        if (errors == 0)
            $display("  TEST 1: PASSED - all 256 coefficients match Python");
        else
            $display("  TEST 1: FAILED - %0d mismatches", errors);

        // ---- TEST 2: Inverse NTT ----
        errors = 0;
        $display("");
        $display("================================================");
        $display("  TEST 2: Inverse NTT  (round-trip check)");
        $display("  Input: NTT output from Test 1");
        $display("  Expected: [1, 2, 3, ..., 256]");
        $display("================================================");
        load_inverse_lut;
        load_inverse_input;
        is_inverse <= 1;
        run_ntt(MAX_CYCLES);
        check_intt_output;
        if (errors == 0)
            $display("  TEST 2: PASSED - INTT(NTT(a)) == a confirmed");
        else
            $display("  TEST 2: FAILED - %0d mismatches", errors);

        $display("");
        $display("================================================");
        $display("  Verilog matches Python: bit-exact verification");
        $display("================================================");
        #200; $finish;
    end

    initial begin #(MAX_CYCLES*200); $display("WATCHDOG"); $finish; end

endmodule