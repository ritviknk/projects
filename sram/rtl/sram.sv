/****************************************************************
* File name     : sram.sv
* Creation date : 21-06-2020
* Last modified : Tue 11 Aug 2020 09:57:58 PM MDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
*****************************************************************/
`timescale  1 ps / 1 ps

module sram(clk, rstb, data_in, addr_in, we_b, ce_b, data_out);
// strunctural parameters
  parameter PORTS = 1;    // port = 1 : single port sram
                          // port = 2 : true dual port sram,
                          //            both ports can be used for read/write

  parameter DEPTH = 1024; // depth indicates total addresses available
  parameter WIDTH = 8;    // width indicates no. of bits at each address

// behavioural parameters
  parameter SYNCH = 1;    // 1 : synchronous sram
                          // 0 : asynch sram, functionality to be added later

  // read after write, read data available after 1 clk
  // when read and write address are same, new data is returned after write


input logic clk[0:PORTS-1]; 
input logic rstb[0:PORTS-1];
input logic ce_b[0:PORTS-1];
input logic we_b [0:PORTS-1];
input logic [WIDTH-1:0] data_in [0:PORTS-1];
input logic [$clog2(DEPTH)-1:0] addr_in [0:PORTS-1];
// input logic [1:0] sram_read_mode;
// 00: flow thru read, no burst
// 01: pipelined read, no burst
// 10: flow thru read with burst
// 11: pipelined read with burst

output logic [WIDTH-1:0] data_out [0:PORTS-1];

// sram memory - DEPTH X WIDTH matrix
logic [WIDTH-1:0] SRAM_MEM [0:DEPTH-1];

// functional section //

// synchronous sram behavioral logic
if (SYNCH==1) begin

// single port sram
if(PORTS==1) begin
  logic we;
  logic [WIDTH-1:0] d;
  logic [$clog2(DEPTH)-1:0] addr, read_addr;

  assign we = we_b[0];
  assign d = data_in[0];
  assign addr = addr_in[0];
  assign data_out[0] = SRAM_MEM[read_addr];
  // read after write, new data is returned always

  always_ff @(posedge clk[0])
    // sram active only when chip enable is low
    if (!ce_b[0]) begin
      if(!we) SRAM_MEM[addr] <= d;    // write data when we is low
      
      read_addr <= addr;        // store the addr for read after write op
                                // return new data at mem[addr] via cont. assign
    end

end

// dual port sram
else if (PORTS==2) begin
  
  // port0
  always_ff @(posedge clk[0])
    if (!ce_b[0])
      if (!we_b[0]) begin
        SRAM_MEM[addr_in[0]] <= data_in[0];
        data_out[0] <= data_in[0];
      end

      else begin
        data_out[0] <= SRAM_MEM[addr_in[0]];
      end


  // port 1
  always_ff @(posedge clk[1])
    if (!ce_b[1])
      if (!we_b[1]) begin
        SRAM_MEM[addr_in[1]] <= data_in[1];
        data_out[1] <= data_in[1];
      end

      else begin
        data_out[1] <= SRAM_MEM[addr_in[1]];
      end

end

// multi port sram
else if (PORTS>2) begin
end
end

// asynchronous sram behavioral logic
else if (SYNCH==0) begin
end

endmodule
