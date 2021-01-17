/****************************************************************
* File name     : bitonic_sort.sv
* Creation date : 08-08-2020
* Last modified : Sat 05 Sep 2020 03:57:17 PM MDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
  *
* file:///home/ritvik/projects/hdl/design/bitonic_sort/prj/BitonicSort1.svg
* Image courtesy - https://en.wikipedia.org/wiki/Bitonic_sorter
*
*****************************************************************/

`timescale  1 ps / 1 ps
`default_nettype none

module bitonic_sort #(
  parameter WIDTH   = 4,      // no of entires in one read
  parameter ADDR    = 12,     // width of addr bus
  parameter BITS    = 8,      // no of bits in each entry
  parameter MAXCNT  = 1024,   // max no of entries in complete array(SRAM)
  parameter TYPE    = 0       // 0 - unsigned integer
                              // 1 - signed integer
                              // 2 - signed fixed point
                              // 3 - signed floating point 
                              // IEEE single precision 32-b floating point representation
                              // bit 31       : sign
                              // bits [30:23] : exponent (true exponent = exponent - bias
                              // bits [22:0]  : mantissa
                              // real number = (-1)^sign * 2^(exp-bias) * 1.{mantissa}
)(                            
                              
  input wire  logic                       clk, 
  input wire  logic                       rstb,
  input wire  logic [WIDTH-1:0][BITS-1:0] unsorted,
  input wire  logic                       sort_req,
  input wire  logic [ADDR-1:0]            start_addr,
  input wire  logic [(2**ADDR)-1:0]       data_count,   // total number of entries
  
  output      logic [ADDR-1:0]            read_addr,
  output      logic                       read_en,
  output      logic                       sort_valid,
  output      logic                       sort_active,
  output      logic [WIDTH-1:0][BITS-1:0] sorted,
  output      logic [ADDR-1:0]            sorted_addr
);

localparam MAXRD = MAXCNT/WIDTH;  // max no of reads required to read MAXCNT no of entries
localparam MAXSTAGE = MAXRD -1;

localparam SIGN_BIT = BITS-1;
localparam EXP_BIT  = BITS-2;
localparam MANT_BIT = BITS-10;

// no of entries    = N       = data_count
// no of stages     = N-1
// no of iterations = N * (N-1) 
// end count        = N * (N-1)

/************** local signals *******************/
int b;
int a0, d0;
int a1, d1;
int a2, d2;
int a3, a4, a5;

logic                         read_valid, read_valid_p0, read_valid_p1;
logic                         sorter4_valid, stage0_asc_valid, stage0_desc_valid;

logic [WIDTH-1:0][BITS-1:0]   sort4_pr1;
logic                         sort4_pr1_valid;

logic [WIDTH-1:0][BITS-1:0]   uns_s0; // stage0 sorted data
logic [WIDTH-1:0][BITS-1:0]   uns_s1; // stage1 sorted data
logic [WIDTH-1:0][BITS-1:0]   uns_s2; // stage2 sorted data
logic [2*WIDTH-1:0][BITS-1:0] uns8_s2; // stage3 sorted data : pr2 + sort4 out
logic [2*WIDTH-1:0][BITS-1:0] uns_s3; // stage3 sorted data
logic [2*WIDTH-1:0][BITS-1:0] uns_s4; // stage4 sorted data
logic [2*WIDTH-1:0][BITS-1:0] uns_s5; // stage5 sorted data
logic [WIDTH-1:0][BITS-1:0]   sort8_pr2;
logic                         sort8_pr2_valid;
logic                         sorter8_valid;
logic [$clog2(MAXRD)-1:0]     read_counter;
logic [$clog2(MAXRD)-1:0]     write_counter;
logic                         read_counter_active;
logic                         mux1_sel, mux2_sel, mux3_sel;
logic                         mux1_sel_p;
logic                         byte_order_inv;
logic [ADDR-1:0]              stage;
logic [(2**ADDR)-1:0]         end_cnt;

/************** functional section **************/

/* Control path : mux1_sel, mux2_sel, mux3_sel, read_en, write_en, write addr, sorting stage */

// New sorting starts when sort_req signal is high
always_ff @(posedge clk or negedge rstb)
  if(~rstb) begin
      sort_active <= 0;
      end_cnt     <= 0;
  end
  else begin
    if((sort_req && ~sort_active) || (sort_req && read_counter == end_cnt-1 && stage== end_cnt-1)) begin
      sort_active <= 1;
      end_cnt     <= data_count;
    end
    // if sort_req is low when read_counter is wrapping arround, stop sorting
    else if (~sort_req && sort_active && read_counter == end_cnt-1 && stage== end_cnt-1)
      sort_active <= 0;
  end

// pipeline read data with correct no of clocks based on SRAM latency
always_ff @(posedge clk or negedge rstb)
  if(~rstb) begin
    read_valid_p0  <= 0;
    read_valid_p1  <= 0;
    read_valid     <= 0;
  end 
  else begin
    read_valid  <= read_en;
    //read_valid     <= read_valid_p0;
  end

// read counter
//
// start incrementing counter one clock before read data is valid
// select one pipe stage before read_valid based on SRAM read delay
assign read_counter_active = read_en;

always_ff @(posedge clk or negedge rstb)
  if(~rstb) read_counter <= 0;
  else if (read_counter_active)
    if (read_counter == end_cnt-1)
      read_counter <= 0;
    else if(read_counter < end_cnt-1)
      read_counter <= read_counter + 1;

// sorting stage counter
always_ff @(posedge clk or negedge rstb)
  if(~rstb) 
      stage <= 0;
  else if (read_counter_active) begin

    // increment stage after one pass of all entries are read and sorted
    if(read_counter == end_cnt-1 && (sort_valid & mux3_sel))
      // wrap around after all stages are completed 
      if (stage==end_cnt-1)
        stage <= 0;
      else
        stage <= stage + 1;
  end

  // stay at 0 is read counter is not incrementing
  else
      stage <= 0;

// read enable, read addr update
assign read_en    = sort_active;
assign read_addr  = read_counter + start_addr;

// write enable, write addr update
//
//assign write_en = sort_valid;
//assign write_data = sorted[3:0];
//
assign sorted_addr = write_counter + start_addr;
always_ff @(posedge clk or negedge rstb)
  if (~rstb) 
      write_counter <= 0;
  else if (write_counter == end_cnt-1)
      write_counter <= 0;
  else if (sort_valid)
      write_counter <= write_counter + 1;

// mux selection
assign mux1_sel = (read_counter==1);
assign mux2_sel = ~mux1_sel_p;
assign mux3_sel = mux2_sel & (sort4_pr1_valid & sort8_pr2_valid);

always_ff @(posedge clk or negedge rstb)
begin
  mux1_sel_p  <= mux1_sel;
end

// use simple byte order invert after first pass of sort4, or in stage 1,2,3
assign byte_order_inv = (stage != 0);

/************** Sort4 ***************************/

// Bitonic Sorting of 4 entries - Ascending

/* Stage0 sorter: common for ascending and descending sort4
* sort in alternating ascending and descending order
* ascending   : 0-1, 4-5, 8-9, 12-13.....
* descending  : 2-3, 6-7, 10-11, 14-15...
*/
always_comb begin
  stage0_asc_valid = 0;
  if(read_valid) begin
    /* WIDTH/2 compares with ascending order sort */
    for(a0=0;a0<WIDTH;a0=a0+4)
      {uns_s0[a0], uns_s0[a0+1]} = asc_sorter(unsorted[a0], unsorted[a0+1]);
    stage0_asc_valid = 1;
  end
end

always_comb begin
  stage0_desc_valid = 0;
  if(read_valid) begin
    /* WIDTH/2 compares with descending order sort */
    for(d0=2;d0<WIDTH;d0=d0+4)
      {uns_s0[d0], uns_s0[d0+1]} = desc_sorter(unsorted[d0], unsorted[d0+1]);
    stage0_desc_valid = 1;
  end
end

/* stage 1 and 2 sort4: 
  * stage0_*_valid have to be set before stage 1 and 2 can begin
  * no need for read_valid as it is combined in stage0_*_valid
*/
always_comb begin
  sorter4_valid = 0;
  if(stage0_desc_valid & stage0_asc_valid & mux1_sel) begin

    /* Stage1 sorter:
    * sort top half in ascending order, compare even entries with even, odd indexed entries with odd
    * sort bottom half in descending order, compare even entries with even, odd indexed entries with odd
    * ascending   : 0-2, 1-3
    * descending  : 4-6, 5-7
    */ 
    /* WIDTH/2 compares with ascending order sort */
    for(a1=0;a1<WIDTH/2;a1=a1+1)
      {uns_s1[a1], uns_s1[a1+WIDTH/2]} = asc_sorter(uns_s0[a1], uns_s0[a1+WIDTH/2]);

    /* Stage2 sorter:
    * sort top half in ascending order, compare even entries with odd
    * sort bottom half in descending order, compare even entries with odd
    */
    for(a2=0;a2<WIDTH;a2=a2+2)
      {uns_s2[a2], uns_s2[a2+1]} = asc_sorter(uns_s1[a2], uns_s1[a2+1]);

    sorter4_valid = 1;
  end

// Bitonic Sorting of 4 entries - Descending
// when unsorted is sorted in ascending order, and needs to be sorted in
// descending, a simple byte order inversion is sufficient
  else if(stage0_desc_valid & stage0_asc_valid & ~mux1_sel) begin

    /* Stage1 sorter:
    * sort top half in ascending order, compare even entries with even, odd indexed entries with odd
    * sort bottom half in descending order, compare even entries with even, odd indexed entries with odd
    * ascending   : 0-2, 1-3
    * descending  : 4-6, 5-7
    */
    /* WIDTH/2 compares with descending order sort */
    for(a1=0;a1<WIDTH/2;a1=a1+1)
      {uns_s1[a1], uns_s1[a1+WIDTH/2]} = desc_sorter(uns_s0[a1], uns_s0[a1+WIDTH/2]);

    /* Stage2 sorter:
    * sort top half in ascending order, compare even entries with odd
    * sort bottom half in descending order, compare even entries with odd
    */
    for(a2=0;a2<WIDTH;a2=a2+2)
      {uns_s2[a2], uns_s2[a2+1]} = desc_sorter(uns_s1[a2], uns_s1[a2+1]);

    sorter4_valid = 1;
  end
end


/* Sort4 : first pipeline stage PipeReg1 / PR1 */
always_ff @(posedge clk or negedge rstb)
  if(~rstb) begin
    sort4_pr1       <= 0;
    sort4_pr1_valid <= 0;
  end
  else if (sorter4_valid) begin
    sort4_pr1       <= uns_s2;
    sort4_pr1_valid <= 1;
  end
  else
    sort4_pr1_valid <= 0;

/************** Sort8 ***************************/

// Bitonic sorting of 8 entries - [3:0] ascending order, [7:4] descending

/* Sort8 : second pipeline stage PipeReg2 / PR2 */
always_ff @(posedge clk or negedge rstb)
  if(~rstb) begin
    sort8_pr2       <= 0;
    sort8_pr2_valid <= 0;
  end
  else if (mux2_sel & sorter8_valid) begin
    sort8_pr2       <= uns_s5[WIDTH-1:0];
    sort8_pr2_valid <= 1;
  end
  else if (~mux2_sel & sort4_pr1_valid) begin
    sort8_pr2       <= sort4_pr1;
    sort8_pr2_valid <= 1;
  end
  else      
    sort8_pr2_valid <= 0;

// Sort8: sorting block

// concatenate current sort4 output with previous sort8 [7:0] to form 8 entries
assign uns8_s2 = {sort8_pr2,sort4_pr1};

// sort8 is active only when both pr2 stage has valid data and pr1 has valid data
always_comb begin
  sorter8_valid = 0;
  if (sort8_pr2_valid & sort4_pr1_valid & mux3_sel) begin

    /* Stage3 sorter:
    * sort in ascending order, compare top half with bottom half
    * ascending   : 0-4, 1-5, 2-6, 3-7
    * WIDTH compares with ascending order sort */
    for(a3=0;a3<WIDTH;a3++)
      {uns_s3[a3], uns_s3[a3+WIDTH]} = asc_sorter(uns8_s2[a3], uns8_s2[a3+WIDTH]);
  
    /* Stage4 sorter:
    * sort in ascending order, 
    *   compare top half even to even, odd to odd
    *   compare bottom half even to even, odd to odd
    * ascending   : 0-2, 1-3, 4-6, 5-7
    * WIDTH compares with ascending order sort */
    for(a4=0;a4<WIDTH/2;a4++)
      {uns_s4[a4], uns_s4[a4+WIDTH/2]} = asc_sorter(uns_s3[a4], uns_s3[a4+WIDTH/2]);
  
    for(a4=WIDTH;a4<WIDTH+WIDTH/2;a4=a4+1)
      {uns_s4[a4], uns_s4[a4+WIDTH/2]} = asc_sorter(uns_s3[a4], uns_s3[a4+WIDTH/2]);
  
    /* Stage4 sorter:
    * sort in ascending order, 
    *   compare top half even to even, odd to odd
    *   compare bottom half even to even, odd to odd
    * ascending   : 0-2, 1-3, 4-6, 5-7
    * WIDTH compares with ascending order sort */
    for(a5=0;a5<2*WIDTH;a5=a5+2)
      {uns_s5[a5], uns_s5[a5+1]} = asc_sorter(uns_s4[a5], uns_s4[a5+1]);
  
    sorter8_valid = 1;
  end
end

/* final sort8 output stage */
always_ff @(posedge clk or negedge rstb)
  if(~rstb) begin 
    sorted      <= 0;
    sort_valid  <= 0;
  end
  else if (sort8_pr2_valid & ~mux3_sel) begin
    sorted[WIDTH-1:0] <= sort8_pr2;
    sort_valid  <= 1;
  end
  else if (sorter8_valid & mux3_sel) begin
    sorted[WIDTH-1:0] <= uns_s5[2*WIDTH-1:WIDTH];
    sort_valid <= 1;
  end
  else
    sort_valid <= 0;


/************** Common Functions ****************/

/* ascending sorter : Sn-1 > Sn-2, ... S1 > S0
*/
function logic [1:0][BITS-1:0] asc_sorter(
  input logic [BITS-1:0] uns0, 
  input logic [BITS-1:0] uns1);
        logic            cmp; // 1- uns0 win1
                              // 0- uns1 wins

// unsigned integer
  if(TYPE==0) begin
    cmp       = (uns0 > uns1);
  end 

// signed integer or fixed point
  else if (TYPE==1 || TYPE==2) begin

    // same signs, simple magnitude compare
    if(uns0[BITS-1] ^ uns1[BITS-1]) 
      cmp = (uns0[BITS-2:0]>uns1[BITS-2:0]);

    // different signs, +ve number wins
    else
      cmp = uns1[BITS-2:0];
  
  end

// signed floating point
  else if (TYPE==3) begin

    logic cmp_exp_0, cmp_exp_1, cmp_mant_0;

    /* 
    * step 1: check for sign
    * if signs are different, +ve number wins
      *
    * If signs are same:
    * step 2: check for exponent
    * larger exponent wins
    *
    * If exponents are same:
    * step 3: check for manitssa
    * larger mantissa wins
    */
    case({uns1[BITS-1], uns0[BITS-1]})
      // different signs, +ve number wins
      2'b01: cmp = 0;
      2'b10: cmp = 1;

      // same signs, priority order magnitude compare
      // exp magnitude compare
      // mantissa magnitude compare
      2'b00,
      2'b11:
                  if (cmp_exp_0)  cmp = 1;  // uns0 exp > uns1 exp, uns0 wins
             else if (cmp_exp_1)  cmp = 0;  // uns0 exp < uns1 exp, uns1 wins
             else if (cmp_mant_0) cmp = 1;  // uns0 exp == uns1 exp, uns0 mant > uns1 mant , uns0 wins
             else                 cmp = 0;  // uns0 exp == uns1 exp, uns0 mant ~> uns1 mant , uns1 wins
    endcase

    cmp_exp_0     = uns0[EXP_BIT:MANT_BIT+1]  >  uns1[EXP_BIT:MANT_BIT+1];
    cmp_exp_1     = uns0[EXP_BIT:MANT_BIT+1]  < uns1[EXP_BIT:MANT_BIT+1];
    cmp_mant_0    = uns0[MANT_BIT:0]          >  uns1[MANT_BIT:0];

  end

  asc_sorter  = cmp ? {uns0, uns1} : {uns1, uns0};
endfunction

/* descending sorter : Sn-1 < Sn-2, ... S1 < S0
*/
function logic [1:0][BITS-1:0] desc_sorter(
  input logic [BITS-1:0] uns0, 
  input logic [BITS-1:0] uns1);

  logic [1:0][BITS-1:0] asc_sort;

  // reuse ascending sorter and reverse byte order
  asc_sort = asc_sorter(uns0, uns1);
  for(int i= 0;i<2;i++)
    desc_sorter[i] = asc_sort[1-i];

endfunction

endmodule
`default_nettype wire
