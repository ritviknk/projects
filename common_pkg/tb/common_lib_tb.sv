/****************************************************************
* File name     : common_lib_tb.sv
* Creation date : 25-01-2020
* Last modified : Tue 19 May 2020 04:33:55 PM MDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
*****************************************************************/

module tb_clk_rst(rtl_clk, tb_clk_neg, tb_clk_dly, rstb);
parameter CLK_WDT = 10;
parameter TB_CLK_DLY = 2;
parameter RST_TIME = 15;

output logic rtl_clk;
output logic tb_clk_neg;
output logic tb_clk_dly;
output logic rstb;


  always
    #(CLK_WDT/2) rtl_clk = !rtl_clk;
  
  always_comb
    tb_clk_dly <= #(TB_CLK_DLY) rtl_clk;
  
  assign tb_clk_neg = !rtl_clk;

  initial begin
    rtl_clk=0;
    rstb=0;
    #(RST_TIME);
    rstb=1;
  end
endmodule
