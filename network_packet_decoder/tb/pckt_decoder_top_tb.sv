/****************************************************************
* File name     : 
* Creation date : 14-06-2020
* Last modified : Sun 02 Aug 2020 05:19:45 PM MDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
*****************************************************************/
`timescale  1 ns/1 ps

module pckt_decoder_top_tb();

  parameter               IWIDTH_TB = 8; // 8*8=64
  parameter               OWIDTH_TB = 16;// 8*32=256B
  parameter logic [15:0]  MINLEN_TB = 'h8;
  parameter               FIFO_DEPTH_TB = 8;

  logic clk, rstb;
  logic [OWIDTH_TB*8-1:0] out_data;
  logic in_valid, in_sop, in_eop,in_error, fifo_empty, ready_out_b;
  logic [IWIDTH_TB*8-1:0] in_data;
  logic [IWIDTH_TB-1:0] in_empty;

  logic out_valid, read_en, read_valid;
  logic [OWIDTH_TB-1:0] out_bytemask;

  logic [IWIDTH_TB-1:0][7:0] input_data [0:7];
  logic test_end, clk_tb;
  int i;

  initial begin
  input_data[0] = {8'h0,  8'h4,   8'h0,   8'h19,  8'h1,   8'h2,   8'h3,   8'h4};    // S0
  input_data[1] = {8'h5,  8'h6,   8'h7,   8'h8,   8'h9,   8'ha,   8'hb,   8'hc};    // S2
  input_data[2] = {8'hd,  8'he,   8'hf,   8'h1,   8'h2,   8'h3,   8'h4,   8'h5};    // S2
  input_data[3] = {8'hd,  8'he,   8'hf,   8'h6,   8'h7,   8'h0,   8'h8,   8'h11};   // S1, S1_P
  input_data[4] = {8'h12, 8'h13,  8'h14,  8'h15,  8'h16,  8'h17,  8'h18,  8'h0};    // S4
  input_data[5] = {8'h8,  8'h21,  8'h22,  8'h23,  8'h24,  8'h25,  8'h26,  8'h27};   // S3
  input_data[6] = {8'h28, 8'h0,   8'h8,   8'h31,  8'h32,  8'h33,  8'h34,  8'h35};   // S1, S1_P
  input_data[7] = {8'h36, 8'h37,  8'h38,  8'bx,   8'bx,   8'bx,   8'bx,   8'bx};    // S1
  end

  initial begin
    //in_empty = 0;
    in_error = 0;
    wait(rstb==1);
    @(posedge clk_tb);
    @(posedge clk_tb);
    @(posedge clk_tb);
    while(i<$size(input_data)*2) begin
      @(posedge clk_tb);
    end
    $stop;

  end

/*
  always_ff @(posedge clk or negedge rstb)
    if(!rstb) begin
      in_data <= 'bx;
      read_valid <= 'bx;
      i <= 0;
      in_sop <= 'bx;
      in_eop <= 'bx;
      fifo_empty <= 1;
    end
    else begin
      fifo_empty <= 0;

      if(read_en & !fifo_empty) begin
        if(i==0)  in_sop <= 1;
        else      in_sop <= 0;

        if(i==$size(input_data)-1) begin
          in_eop <= 1;
          //fifo_empty <= 1;
        end
        else begin
          in_eop <= 0;
          fifo_empty <= 0;
        end

        in_data <= input_data[i];
        i <= i+1;
        read_valid <= 1;
      end
      else
        read_valid <= 0;

    end

  pckt_decoder #(.IWIDTH(IWIDTH_TB), .OWIDTH(OWIDTH_TB), .MINLEN(MINLEN_TB)) 
  dut (
    .clk              (clk), 
    .rstb             (rstb), 
    .in_sop           (in_sop), 
    .in_eop           (in_eop), 
    .in_data          (in_data), 
    .in_empty         (in_empty), 
    .in_error         (in_error), 
    .out_valid        (out_valid), 
    .out_data         (out_data), 
    .out_bytemask     (out_bytemask), 
    .read_en          (read_en),
    .read_data_valid  (read_valid),
    .fifo_empty       (fifo_empty)
  );
*/

  always_ff @(posedge clk_tb or negedge rstb)
    if(!rstb) begin
      i <= 0;
      in_sop    <= 'bx;
      in_eop    <= 'bx;
      in_empty  <= 'bx;
      in_data   <= 'bx;
      in_valid  <= 'bx;
    end
    else begin
      in_empty <= 0;

      // ready_out_b is active low
      if(~ready_out_b) begin
        if(i==0)  in_sop    <= 1;
        else      in_sop    <= 0;

        if(i==$size(input_data)-1) begin
          in_eop <= 1;
          in_empty <= 'b0001_1111;
        end
        else begin
          in_eop <= 0;
          in_empty <= 0;
        end
        
        if(i<$size(input_data)) begin
          in_valid  <= 1;
          in_data   <= input_data[i];
        end
        else begin
          in_valid  <= 0;
        end
        i <= i+1;
      end
      else
        in_valid  <= 0;

    end

  pckt_decoder_top #(.IWIDTH(IWIDTH_TB), .OWIDTH(OWIDTH_TB), .MINLEN(MINLEN_TB), .FIFO_DEPTH(FIFO_DEPTH_TB))
  dut (
    .clk            (clk),
    .rstb           (rstb),
    .in_valid       (in_valid),
    .in_sop         (in_sop),
    .in_eop         (in_eop),
    .in_data        (in_data),
    .in_empty       (in_empty),
    .in_error       (in_error),
    .out_valid      (out_valid),
    .out_data       (out_data),
    .out_bytemask   (out_bytemask),
    .ready_out_b    (ready_out_b)
  );

  tb_clk_rst #(.CLK_WDT(10), .TB_CLK_DLY(2), .RST_TIME(12)) 
  tb_clk_rst_inst (
  .rtl_clk    (clk),
  .tb_clk_neg (),
  .tb_clk_dly (clk_tb),
  .rstb       (rstb)
  );

endmodule

