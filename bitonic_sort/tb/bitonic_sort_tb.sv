/****************************************************************
* File name     : bitonic_sort_tb.sv
* Creation date : 08-08-2020
* Last modified : Sat 05 Sep 2020 04:08:20 PM MDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
*****************************************************************/
`timescale  1 ps / 1 ps
`default_nettype none

module bitonic_sort_tb();

localparam WIDTH_TB     = 4;    // no of entires in unsroted data
localparam BITS_TB      = 8;
localparam TYPE_TB      = 0;    // 0 - unsigned integer
                                // 1 - signed integer
                                // 2 - signed fixed point
                                // 3 - signed floating point

localparam WIDTH_SRAM   = WIDTH_TB*BITS_TB;    //SRAM width
localparam DEPTH_SRAM   = 1024;
localparam ADDR_TB      = $clog2(DEPTH_SRAM);    // width of addr bus
localparam PORTS_TB     = 2;


// test parameters
localparam INT_MIN = 0;
localparam INT_MAX = (2**BITS_TB)-1;
localparam START_ADDR_TB = 0;
localparam DATA_CNT_TB  = 100;

logic                             clk, clk_tb; 
logic                             rstb;
logic [WIDTH_TB-1:0][BITS_TB-1:0] unsorted_in;
logic                             read_valid_in;
logic                             sort_req_in;
logic [ADDR_TB-1:0]               start_addr_in;
logic [(2**ADDR_TB)-1:0]          data_count_in;

logic [ADDR_TB-1:0]               read_addr_out;
logic                             read_en_out;
logic                             sort_valid_out;
logic                             sort_active_out;
logic [WIDTH_TB-1:0][BITS_TB-1:0] sorted_out;
logic [ADDR_TB-1:0]               sorted_addr_out;

logic                             write_en_tb;
logic [WIDTH_TB-1:0][BITS_TB-1:0] write_data_tb;
logic [ADDR_TB-1:0]               write_addr_tb;

logic                             write_en;
logic [WIDTH_TB-1:0][BITS_TB-1:0] write_data;
logic [ADDR_TB-1:0]               write_addr;
logic                             write_sel;  // 1 - DUT, 0 - TB

// SRAM memory local signals
logic                             sram_clks     [0:PORTS_TB-1];
logic                             sram_rstb     [0:PORTS_TB-1];
logic                             sram_ce_b     [0:PORTS_TB-1];
logic                             sram_we_b     [0:PORTS_TB-1];
logic [WIDTH_SRAM-1:0]            sram_data_in  [0:PORTS_TB-1];
logic [ADDR_TB-1:0]               sram_addr_in  [0:PORTS_TB-1];
logic [WIDTH_SRAM-1:0]            sram_data_out [0:PORTS_TB-1];
int cnt;

logic [WIDTH_TB-1:0][BITS_TB-1:0] raw_data      [0:DATA_CNT_TB-1];
logic               [BITS_TB-1:0] unsorted_array[0:DATA_CNT_TB*WIDTH_TB-1];
logic               [BITS_TB-1:0] sorted_array  [0:DATA_CNT_TB*WIDTH_TB-1];

function logic[BITS_TB-1:0] get_rand_int();
  int rand_int;
  rand_int = $urandom_range(INT_MAX, INT_MIN);
  get_rand_int = rand_int[BITS_TB-1:0];
endfunction

initial begin
  #0;
  for(int i = 0; i<DATA_CNT_TB; i++) begin
    for(int j = 0; j<WIDTH_TB; j++) begin
      raw_data[i][j]                = get_rand_int();
      unsorted_array[i*WIDTH_TB+j]  = raw_data[i][j];
      //$display("raw data block [%d][%d] = %d", i, j, raw_data[i][j]);
    end
  end
  //for(int i = 0; i<DATA_CNT_TB*WIDTH_TB; i++)
  //  $display("unsorted array = %d", unsorted_array[i]);
end


assign write_en   = write_sel ? sort_valid_out  : write_en_tb;
assign write_addr = write_sel ? sorted_addr_out : write_addr_tb;
assign write_data = write_sel ? sorted_out      : write_data_tb;

assign data_count_in = DATA_CNT_TB;

always_ff @(posedge clk_tb or negedge rstb)
  if(~rstb) begin
    write_sel     <= 0;
    write_en_tb   <= 0;
    sort_req_in   <= 0;
  end
  else begin
    // select TB as source initially
    if(cnt < DATA_CNT_TB-1) begin
      write_en_tb <= 1;
      write_sel   <= 0;
    end

    // after writing all raw data to SRAM, select dut as source
    else if (cnt == DATA_CNT_TB-1) begin
      write_en_tb <= 0;
      write_sel   <= 1;      
    end
  end

always_ff @(posedge clk_tb or negedge rstb)
  if(~rstb) begin
    cnt           <= 0;
    write_addr_tb <= START_ADDR_TB;
  end
  // increment SRAM addr when TB is writing raw data
  else if(write_en_tb) begin
    write_addr_tb <= write_addr_tb + 1;
    cnt           <= cnt + 1;
  end

assign write_data_tb = raw_data[cnt];


always_ff @(posedge clk_tb)
  // when DUT is writng data to SRAM, increment cnt
  if(write_sel) begin
    cnt             <= cnt + 1;

    // assert sort request for one cycle
    if(~sort_req_in && cnt <= DATA_CNT_TB+10) begin
      sort_req_in   <= 1;
      start_addr_in <= START_ADDR_TB;
    end
    else if (sort_req_in && cnt > DATA_CNT_TB + 20 /*DATA_CNT_TB*(DATA_CNT_TB-1) + DATA_CNT_TB + 10*/)
      sort_req_in   <= 0;

  end

initial begin

  wait(write_sel==1);       // wait for TB write to end
  wait(sort_valid_out==1);  // wait for DUT sorting to begin
  wait(sort_valid_out==0);  // wait for DUT sorting to end

  @(posedge clk); 
  @(posedge clk); 
  @(posedge clk); 
  @(posedge clk); 
  @(posedge clk); 
  $finish;
end



/************* DUT inst *********/

bitonic_sort #(.WIDTH(WIDTH_TB), .ADDR(ADDR_TB), .BITS(BITS_TB), .MAXCNT(1024), .TYPE(TYPE_TB)) sorter (
  .clk          (clk), 
  .rstb         (rstb), 
  .unsorted     (unsorted_in),
  .sort_req     (sort_req_in),
  .start_addr   (start_addr_in),
  .data_count   (data_count_in),   // total number of entries
  .read_addr    (read_addr_out),
  .read_en      (read_en_out),
  .sort_valid   (sort_valid_out),
  .sort_active  (sort_active_out),
  .sorted       (sorted_out),
  .sorted_addr  (sorted_addr_out)
);

/*** SRAM module inst ******/

// Port 0 - read side
assign sram_rstb[0]     = 1;
assign sram_clks[0]     = clk;
assign sram_ce_b[0]     = ~read_en_out;
assign sram_we_b[0]     = read_en_out;     // read only port
assign sram_data_in[0]  = 'bx;      // sim only assing, undriven net otherwise
assign sram_addr_in[0]  = read_addr_out;
assign unsorted_in      = sram_data_out[0];

// Port 1 - write side
assign sram_rstb[1]     = 1;
assign sram_clks[1]     = clk;
assign sram_ce_b[1]     = ~write_en;
assign sram_we_b[1]     = ~write_en;     // write only port
assign sram_data_in[1]  = write_data;      
assign sram_addr_in[1]  = write_addr;
// assign sram_data_out[1] = rd_data;  unconn net otherwise

// synchronous sram module
sram #(.PORTS(PORTS_TB), .DEPTH(DEPTH_SRAM), .WIDTH(WIDTH_SRAM), .SYNCH(1))
SRAM_MEM (
    .clk(sram_clks),
    .rstb(),                // unused in sram
    .data_in(sram_data_in), 
    .addr_in(sram_addr_in), 
    .we_b(sram_we_b), 
    .ce_b(sram_ce_b), 
    .data_out(sram_data_out)
);

tb_clk_rst #(.CLK_WDT(10), .TB_CLK_DLY(2), .RST_TIME(12))
tb_clk_rst_inst (
  .rtl_clk    (clk),
  .tb_clk_neg (),
  .tb_clk_dly (clk_tb),
  .rstb       (rstb)
);

endmodule
