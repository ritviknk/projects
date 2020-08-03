/****************************************************************
* File name     : 
* Creation date : 12-07-2020
* Last modified : Sun 02 Aug 2020 08:08:24 PM MDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
*****************************************************************/
`timescale  1 ps / 1 ps

module fifo_sram(wr_clk, wr_rstb, wr_data, wr_en, wr_full, rd_clk, rd_rstb, rd_en, rd_data, /*rd_val,*/ rd_empty);

// structutal paramerters
parameter DEPTH = 8;    // max no of entries
parameter WIDTH = 128;  // no of bits in each entry

// behavioral paramerters
parameter SYNCH     = 1;      // 1 - synchrnous fifo
                              // 0 - asynch fifo
parameter PREFETCH  = 1;      // 1 - FIFO prefetches read data when not empty,
                              //   - behaves as a register based FIFO,
                              //   - read data available for current read pointer,
                              // 0 - no prefetch of read data when FIFO not empty,
                              //   - each read data has 1 read clk delay from read req
parameter PIPELINED_READ = 0; // 0 - prefetched read data will be available on the same clock
                              // 1 - prefetched read data will be avaialable
                              //     after 1 clock pipelined delay

localparam PORTS = 2;

// I/O
// inputs write side
input logic               wr_clk, wr_rstb;
input logic [WIDTH-1:0]   wr_data;
input logic               wr_en;
// output write side
output logic              wr_full;

// input read side
input logic               rd_clk, rd_rstb;
input logic               rd_en;
// output read side
output logic [WIDTH-1:0]  rd_data;
//output logic              rd_val;
output logic              rd_empty;

// local signals
logic [$clog2(DEPTH):0]   rd_ptr; // pointer includes roll over bit
logic [$clog2(DEPTH):0]   wr_ptr; // pointer includes roll over bit
logic [$clog2(DEPTH)-1:0] rd_addr; // addr excludes roll over bit
logic [$clog2(DEPTH)-1:0] wr_addr; // addr excludes roll over bit
logic                     rd_inc, wr_inc;
// pre fetch signals
logic                     pre_empty, pre_fetch, pre_fetch_rdy;
logic [WIDTH-1:0]         pre_data;

// SRAM memory local signals
logic                     sram_clks     [0:PORTS-1];
logic                     sram_rstb     [0:PORTS-1];
logic                     sram_ce_b     [0:PORTS-1];
logic                     sram_we_b     [0:PORTS-1];
logic [WIDTH-1:0]         sram_data_in  [0:PORTS-1];
logic [$clog2(DEPTH)-1:0] sram_addr_in  [0:PORTS-1];
logic [WIDTH-1:0]         sram_data_out [0:PORTS-1];


/*** SRAM module inst ******/

// Port 0 - read side
assign sram_rstb[0]     = 1;
assign sram_clks[0]     = rd_clk;
assign sram_ce_b[0]     = !rd_inc;
assign sram_we_b[0]     = 1'b1;     // read only port
assign sram_data_in[0]  = 'bx;      // sim only assing, undriven net otherwise
assign sram_addr_in[0]  = rd_addr;
assign pre_data         = sram_data_out[0];

// Port 1 - write side
assign sram_rstb[1]     = 1;
assign sram_clks[1]     = wr_clk;
assign sram_ce_b[1]     = !wr_inc;
assign sram_we_b[1]     = 1'b0;     // write only port
assign sram_data_in[1]  = wr_data;      
assign sram_addr_in[1]  = wr_addr;
// assign sram_data_out[1] = rd_data;  unconn net otherwise

// synchronous sram module
sram #(.PORTS(PORTS), .DEPTH(DEPTH), .WIDTH(WIDTH/8), .SYNCH(1))
FIFO_SRAM_MEM (
    .clk(sram_clks),
    .rstb(),                // unused in sram
    .data_in(sram_data_in), 
    .addr_in(sram_addr_in), 
    .we_b(sram_we_b), 
    .ce_b(sram_ce_b), 
    .data_out(sram_data_out)
);


/******* FIFO controller logic :: write side *************/

  // write addr for sram
assign wr_addr = wr_ptr[$clog2(DEPTH)-1:0];

  // increment wr ptr only when FIFO is not ful
assign wr_inc = wr_en & !wr_full;

  // full when pointers are equal and roll over bits are diff
assign wr_full = (rd_addr == wr_addr) && (rd_ptr[$clog2(DEPTH)] != wr_ptr[$clog2(DEPTH)]);

always_ff @(posedge wr_clk or negedge wr_rstb)
       if (!wr_rstb)  wr_ptr <= 0;
  else if (wr_inc)    wr_ptr <= wr_ptr + 1;

/******* FIFO controller logic :: read side *************/

// pre-fetch logic
if (PREFETCH == 1 ) begin
  localparam PF_EMPTY     = 4'b0001;
  localparam PF_PREFETCH  = 4'b0010;
  localparam PF_FLOW      = 4'b0100;
  localparam PF_FLUSH     = 4'b1000;
  localparam PF_ST_BITS   = 4;

  logic [PF_ST_BITS-1:0] pf_state, nx_pf_state;
  logic [10*8-1:0] state_ascii; // 10 chars

/* 
Pre-Fetch buffer state:
  Empty     : pre_empty = 1 && rd_empty = 1
  Pre-Fetch : pre_empty = 0 && rd_empty = 0 && read_en = 0
  Flow      : pre_empty = 0 && rd_empty = 0 && read_en = 1
  Flush     : pre_empty = 1 && rd_empty = 0 && read_en = 1

State outputs:
  Empty     : pre_fetch = 0, pre_fetch_rdy = 0, rd_empty = 1
  Pre-Fetch : if pfr : pre_fetch = 1 else 0, pre_fetch_rdy = 1, rd_empty = 0
  Flow      : if rd_en = 1 : pre_fetch = 1 else 0, pre_fetch_rdy = 1, rd_empty = 0
  Flush     : pre_fetch = 0, if rd_en = 1 : pre_fetch_rdy = 0 else 1, rd_empty = !pre_fetch_rdy
*/


  // state register
  always_ff @(posedge rd_clk or negedge rd_rstb)
    if (!rd_rstb) pf_state <= PF_EMPTY;
    else          pf_state <= nx_pf_state;
  
  // output registers
  always_ff @(posedge rd_clk or negedge rd_rstb)
    if(~rd_rstb) begin
      pre_fetch <= 0; 
      pre_fetch_rdy <= 0; 
      rd_empty <= 1;
    end
    else begin
      case(nx_pf_state)
        PF_EMPTY    : 
        begin 
          pre_fetch_rdy <= 0; 
          rd_empty <= 1;
        end
        PF_PREFETCH : 
        begin 
          pre_fetch_rdy <= 1;
          rd_empty <= 0;
        end
        PF_FLOW     : 
        begin 
          pre_fetch_rdy <= 1; 
          rd_empty <= pre_empty;
        end
        PF_FLUSH    : 
        begin 
          if (rd_en) begin
            pre_fetch_rdy <= 0;
            rd_empty <= 1;
          end
          else begin
            pre_fetch_rdy <= 1;
            rd_empty <= 0;
          end
        end
      endcase

/*  
      case(nx_pf_state)
        PF_EMPTY    : pre_fetch <= 0; 
        PF_PREFETCH : pre_fetch <= ~pre_fetch_rdy | rd_en;
        PF_FLOW     : pre_fetch <= rd_en; 
        PF_FLUSH    : pre_fetch <= 0;
      endcase
*/
    end

  always_comb
    case(nx_pf_state)
      PF_EMPTY    : pre_fetch <= pre_empty; 
      PF_PREFETCH : pre_fetch <= ~pre_fetch_rdy | rd_en;
      PF_FLOW     : pre_fetch <= rd_en; 
      PF_FLUSH    : pre_fetch <= 0;
    endcase

  // state transition
  always_comb begin
    case(pf_state)
      PF_EMPTY    : 
      begin
          nx_pf_state = PF_EMPTY;
        if (~pre_empty & rd_empty)
          nx_pf_state = PF_PREFETCH;
      end
  
      PF_PREFETCH : 
      begin
          nx_pf_state = PF_PREFETCH;
        if (pre_empty & rd_en)
          nx_pf_state = PF_EMPTY;

        if (~pre_empty /*& ~rd_empty*/ & rd_en)
          nx_pf_state = PF_FLOW;
      end
  
      PF_FLOW     : 
      begin
          nx_pf_state = PF_FLOW;

        if (pre_empty & ~rd_empty & ~rd_en)
          nx_pf_state = PF_FLUSH;
        else if (pre_empty & ~rd_empty & rd_en)
          nx_pf_state = PF_EMPTY;
      end
  
      PF_FLUSH    : 
      begin
          nx_pf_state = PF_FLUSH;
        if(~pre_empty)
          nx_pf_state = PF_FLOW;
        else if (pre_empty & rd_en)
          nx_pf_state = PF_EMPTY;
      end
      
      default     : nx_pf_state = pf_state;
    endcase
  end
  
    // read addr for sram
  assign rd_addr = rd_ptr[$clog2(DEPTH)-1:0];
  
    // increment read ptr only when fifo is not rd_empty
  assign rd_inc = pre_fetch & ~pre_empty;
  
    // rd_empty when pointers are equal including roll over bit
  assign pre_empty = (wr_ptr == rd_ptr);
  
  always_ff @(posedge rd_clk or negedge rd_rstb)
         if (!rd_rstb)  rd_ptr <= 0;
    else if (rd_inc)    rd_ptr <= rd_ptr + 1;
  
if (PIPELINED_READ==1) begin
    // read data out after prefetch
  always_ff @(posedge rd_clk or negedge rd_rstb)
          if (~rd_rstb)               rd_data <= 0;
    else  if (pre_fetch_rdy)  rd_data <= pre_data;
end

else if (PIPELINED_READ==0) begin
  assign rd_data = pre_data;
end
  
  // state ascii values
  always_comb
    case(pf_state)
      PF_EMPTY    : state_ascii = "Empty";
      PF_PREFETCH : state_ascii = "PreFetch";
      PF_FLOW     : state_ascii = "Flow";
      PF_FLUSH    : state_ascii = "Flush";
      default: state_ascii = state_ascii;
    endcase
 
end

// non-pre-fetch logic, read pointer increment has to 
else if (PREFETCH==0) begin

end
// non-pre-fetch logic

endmodule
