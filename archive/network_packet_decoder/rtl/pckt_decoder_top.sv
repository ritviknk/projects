/****************************************************************
* File name     : 
* Creation date : 06-07-2020
* Last modified : Sun 02 Aug 2020 04:55:26 PM MDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
*****************************************************************/
`timescale  1 ps / 1 ps

/* inputs
  * All inputs are registered/pipelined for timing. 
  * This adds one entry to FIFO depth calculation.

* in_sop    : start of packt
* in_eop    : end of packet
* in_data   : IWIDTH bytes of input data on every clock
* in_valid  : valid for in_data, serves as FIFO write enable within pckt_decoder module
* in_empty  : 0 - all IWIDTH bytes of in_data are valid, 
*           : [1:IWDITH-1] - no. of bytes of in_data not valid
*
* outputs
* out_data      : OWIDTH bytes of data message output
* out_bytemask  : valid for each byte in out_data
* out_valid     : message out_data valid, 
*               : 1 - indicates out_data has full OWIDTH bytes of message but not full message
*                   - or out_data has full message but less than OWIDTH bytes valid
* ready_out_b   : 0 - pckt_decoder module is ready to accept new in_data
*                 (FIFO is not full)
*               : 1 - pckt_decoder module is not ready
*                 (FIFO is full)
*/

module pckt_decoder_top (clk, rstb, in_valid, in_sop, in_eop, in_data, in_empty, in_error, out_valid, out_data, out_bytemask, ready_out_b);

parameter               IWIDTH      = 8; // 8*8=64B
parameter               OWIDTH      = 32;// 8*32=256B
parameter logic [15:0]  MINLEN      = 'h8;
parameter               FIFO_DEPTH  = 8;
  
input logic clk, rstb;

input logic                   in_sop, in_eop,in_error, in_valid;
input logic [IWIDTH-1:0][7:0] in_data;
input logic [IWIDTH-1:0]      in_empty;

// outputs
output logic                    out_valid, ready_out_b;
output logic [OWIDTH-1:0][7:0]  out_data;
output logic [OWIDTH-1:0]       out_bytemask;

// data type to pack and upack input data stream and side back signals
// for FIFO reads and writes
typedef struct packed {
  logic [IWIDTH-1:0][7:0] data;
  logic                   sop;
  logic                   eop;
  logic [IWIDTH-1:0]      empty;
  logic                   error;
  logic [4:0]             reserved;
} fifo_data_t;

fifo_data_t write_data, read_data;

localparam  FIFO_WIDTH  = $size(write_data);
/* 8*IWIDTH : in_data
*  IWDITH   : in_empty
*  1        : in_sop
*  1        : in_eop
*  1        : in_error
*  5        : reserved (to make 80 bits or 10B data)
*/

logic                   read_valid, fifo_empty, read_en;
logic [IWIDTH-1:0][7:0] data;
logic                   data_en;

logic [$clog2(IWIDTH):0] i;

always_comb begin
  if(|in_empty) begin
    for(int i=0;i<IWIDTH;i++)
      if(~in_empty[i])  data[i] = in_data[i];
      else              data[i] = 'b0;
  end
   
  else 
    data = in_data;
end

// when in_sop=1 and in_empty>0, FIFO write data bytes that are not valid 
// will be driven to '0'.

// register all inputs for timing
always_ff @(posedge clk or negedge rstb)
  if(~rstb) begin
    write_data          <= {FIFO_WIDTH{'b0}};
    data_en             <= 0;
  end

  else if (in_valid) begin
    write_data.data     <= data;
    write_data.sop      <= in_sop;
    write_data.eop      <= in_eop;
    write_data.empty    <= in_empty;
    write_data.error    <= in_error;
    write_data.reserved <= 0;
    data_en             <= 1'b1;
  end
  else
    data_en             <= 1'b0;

/* Clock domains:
* Write and Read domains are the same, operate on clk and rstb.
*/

fifo_sram #(.DEPTH(FIFO_DEPTH), .WIDTH(FIFO_WIDTH), .SYNCH(1), .PREFETCH(1)) 
sync_sram_fifo (
  .wr_clk     (clk),
  .wr_rstb    (rstb),
  .wr_data    (write_data),
  .wr_en      (data_en),
  .wr_full    (ready_out_b),
  .rd_clk     (clk),
  .rd_rstb    (rstb),
  .rd_en      (read_en),
  .rd_data    (read_data),
  /*.rd_val     (),*/
  .rd_empty   (fifo_empty)
);

  pckt_decoder #(.IWIDTH(IWIDTH), .OWIDTH(OWIDTH), .MINLEN(MINLEN)) 
  pckt_decoder (
    .clk                (clk),
    .rstb               (rstb),
    .in_sop             (read_data.sop),
    .in_eop             (read_data.eop),
    .in_data            (read_data.data),
    .in_empty           (read_data.empty),
    .in_error           (read_data.error),
    .out_valid          (out_valid),
    .out_data           (out_data),
    .out_bytemask       (out_bytemask),
    .read_en            (read_en),
    .read_data_valid    (read_valid),
    .fifo_empty         (fifo_empty)
  );

endmodule

