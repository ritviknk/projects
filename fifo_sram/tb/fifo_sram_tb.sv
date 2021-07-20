/****************************************************************
* File name     : 
* Creation date : 12-07-2020
* Last modified : Mon 19 Jul 2021 11:10:58 PM PDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
*****************************************************************/
`timescale  1 ps / 1 ps

module fifo_sram_tb();

// structutal paramerters
parameter DEPTH = 8;    // max no of entries
parameter WIDTH = 8;    // no of bits in each entry

//  write side
logic               wr_clk, wr_rstb;
logic [WIDTH-1:0]   wr_data;
logic               wr_en;
logic               wr_full;

// read side
logic               rd_clk, rd_rstb;
logic               rd_en;
logic [WIDTH-1:0]   rd_data;
logic               rd_val;
logic               rd_empty;

// common
logic rstb, clk, clk_tb;
logic full, empty;

tb_clk_rst #(.CLK_WDT(10), .TB_CLK_DLY(2), .RST_TIME(12)) 
tb_clk_rst_inst (
  .rtl_clk    (clk),
  .tb_clk_neg (),
  .tb_clk_dly (clk_tb),
  .rstb       (rstb)
);

fifo_sram #(.DEPTH(DEPTH), .WIDTH(WIDTH), .SYNCH(1)) 
fifo_inst (
  .wr_clk   (clk),
  .wr_rstb  (rstb),
  .wr_data  (wr_data),
  .wr_en    (wr_en),

// output write side
  .wr_full  (full),

// input read side
  .rd_clk   (clk), 
  .rd_rstb  (rstb),
  .rd_en    (rd_en),

// output read side
  .rd_data  (rd_data),
  //.rd_val   (rd_val),
  .rd_empty (empty)
);

initial begin
  wait (test_end == 1);
  $stop;
end

// write side
integer wr_cnt, rd_cnt;
logic test_end;
localparam CNT_MAX = DEPTH+2;

always_ff @(posedge clk_tb or negedge rstb)
  if (~rstb) begin
    wr_cnt <= 0;
    wr_data <= 0;
  end
  else
    if(wr_cnt <= CNT_MAX) begin
      wr_data <= wr_data + 1;
      wr_en <= 1;
      wr_cnt <= wr_cnt + 1;
    end
    else begin
      wr_en <= 0;
    end

// read side
always_ff @(posedge clk_tb or negedge rstb)
  if(~rstb) begin
    test_end <= 0;
    rd_en <= 0;
    rd_cnt <= 0;
  end
  else
    if(rd_cnt <= CNT_MAX+4) begin
      rd_en <= 1;
      rd_cnt <= rd_cnt + 1;
    end
    else begin
      rd_en <= 0;
      test_end <= 1;
    end

endmodule
