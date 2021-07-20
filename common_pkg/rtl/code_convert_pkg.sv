/*
* file name: code_convert_pkg.sv
* author: ritvik nadig krishnamuthy
* Functional description :Asyncronous FIFO
*/

package code_convert_pkg;

  task bin2grey;
    parameter bit_width=8;
    input logic [bit_width-1:0]bin;
    output [bit_width-1:0]bin2grey_out;

    bin2grey_out = bin ^ {1'b0,bin[bit_width-1:1]};

  endtask

  task grey2bin;
    parameter bit_width=8;
    input logic [bit_width-1:0]grey;
    output [bit_width-1:0]grey2bin_out;
    
    grey2bin_out[bit_width-1] = grey[bit_width-1];
    for(int i=bit_width-2;i>=0;i=i-1) begin
      grey2bin_out[i] = grey2bin_out[i+1] ^ grey[i];
    end
  endtask


endpackage
