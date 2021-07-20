/*
* file name: common_lib.sv
* author: ritvik nadig krishnamuthy
* Functional description :Asyncronous FIFO
*/

/*
* N-flop synchronizer for clock crossing
*/
module metasync_Nflop
  (
    clk,      // receiving clock
    rstb,     // async reset in receiving clock
    data_in,  // data input from sending clock
    data_out  // data output in receiving clock
  );
  parameter META_EN = 1;              // meta stability modelling enable
  parameter DATA_WIDTH = 1;           // width of data inpur, not to be used for bus, 
                                      // to be only used for ease of instantiation
  parameter META_SYNCFLOP_DEPTH = 2;  // N-flop synch depth

  // input
  input logic clk;
  input logic rstb;
  input logic [DATA_WIDTH-1:0] data_in;

  // out
  output logic [DATA_WIDTH-1:0] data_out; 

  // local signals
  wire [DATA_WIDTH-1:0] data_d[META_SYNCFLOP_DEPTH-1:0];
  reg [DATA_WIDTH-1:0] data_q[META_SYNCFLOP_DEPTH-1:0];

  genvar i;
  generate
  for (i=0;i<META_SYNCFLOP_DEPTH;i=i+1)
  begin

    if(i==0) begin  
      assign data_d[0] = data_in;
    end else begin                
      assign data_d[i] = data_q[i-1];
    end

  end // for
  endgenerate

  genvar Nflop;
  generate
  for (Nflop=0;Nflop<META_SYNCFLOP_DEPTH;Nflop=Nflop+1)
  begin
    always_ff @(posedge clk or negedge rstb)
    begin
      if(!rstb)
        data_q[Nflop] <= 0;
      else
        data_q[Nflop] <= data_d[Nflop];
    end

  end // for
  endgenerate

  assign data_out = data_q[META_SYNCFLOP_DEPTH-1];

endmodule
/**********************************************************************************/

/*
* D-Latch
*/
module d_latch(
  set,    // set q_out=1, q_n_out=0
  reset,  // reset q_out=0, q_n_out=1
  enable, // clock enable for latch
  d_in,   // data input
  q_out,  // q output, active high
  q_n_out // q_n output, active low
);

  parameter WIDTH = 1;

  input logic set, reset, enable;
  input logic   [WIDTH-1:0] d_in;
  output logic  [WIDTH-1:0] q_out;
  output logic  [WIDTH-1:0] q_n_out;

/*************************************************
* Logical section
*************************************************/

always @(*)
begin : d_latch
  if (!reset) begin
    q_out <= 0;
    q_n_out <= 1;
  end else if (set) begin
    q_out <= 1;
    q_n_out <= 0;
  end else if (enable) begin
    q_out   <= d_in;
    q_n_out <= !(d_in);
  end
end

endmodule
/**********************************************************************************/

/*
* Asynchrnous Reset synchronozer
  * Active low reset
  * asynchornous de-assert, synchronous assert
  * N-flop synchrnonization
*/
module reset_sync(
  clk,              // clock for synch assert
  async_rst_n_in,   // asynchronous reset input
  sync_rst_n_out    // synchronous rest output
);
  parameter SYNC_DEPTH = 2;

  input logic clk;              // clock for synch assert
  input logic async_rst_n_in;   // asynchronous reset input
  output logic sync_rst_n_out;  // synchronous rest output

/*************************************************
* Logical section
*************************************************/
  logic [SYNC_DEPTH-1:0] rst_n;
  logic VDD = 1'b1;

  // sample flop
  always_ff @(posedge clk or negedge async_rst_n_in)
  begin
    if (!async_rst_n_in) begin
      rst_n[0] <= 0;
    end else begin
      rst_n[0] <= VDD;
    end 
  end
  
  /*
  // sync flops 
  genvar i;
  generate 
    for (i=1;i<SYNC_DEPTH-1;i=i+1) begin
      always_ff @(posedge clk or negedge async_rst_n_in) begin
        if(!async_rst_n_in) begin
          rst_n[i] <= 0;
        end else begin
          rst_n[i] <= rst_n[i-1];
        end
    end
  endgenerate
  */
  metasync_Nflop #(.META_EN(1), .DATA_WIDTH(1), .META_SYNCFLOP_DEPTH(SYNC_DEPTH-1)) synch_reset (
    .clk(clk),                  
    .rstb(async_rst_n_in),      
    .data_in(rst_n[0]),         
    .data_out(sync_rst_n_out)   
  );
  //assign sync_rst_n_out = rst_n[SYNC_DEPTH-1];

endmodule
/**********************************************************************************/


/* Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog */

/*
* N-flop synN_pgen
  * N-flop synchronizer
  * 1-clock pulse for every input change
  * level out with N-flop synch
*/
module syncN_pgen(
  clk,      // clock
  rstb,     // active low reset
  async_in, // asynchronous input, level
  sync_out, // synchronous output, level
  sync_pulse // synchronous pulse, 1-clock, 
  );

  parameter SYNC_DEPTH = 2;

  input logic clk;      // clock
  input logic rstb;
  input logic async_in; // asynchronous input, level
  output logic sync_out; // synchronous output, level
  output logic sync_pulse; // synchronous pulse, 1-clock, 

  // local signals
  logic sync_out_p;

  // sync flops
  metasync_Nflop #(.META_EN(1), .DATA_WIDTH(1), .META_SYNCFLOP_DEPTH(SYNC_DEPTH)) sync_flop(
    .clk(clk),                  
    .rstb(rstb),      
    .data_in(async_in),         
    .data_out(sync_out)   
  );
  
  // pulse gen, N+1 flop
  always_ff @(posedge clk or negedge rstb)
    if(!rstb)   sync_out_p <= 0;
    else        sync_out_p <= sync_out;
  
  assign sync_pulse = sync_out ^ sync_out_p;
  // sync_pulse and sync_out are on the same clock edge, 
  // CummingsCDC has sync_out from N+1 clock

endmodule
/****************************************************************/


/* 5.6.2 Closed-loop - MCP formulation toggle-pulse generation with feedback, no ack
* cdc_mcp_fbbk
*
  * data bus and data_send generated in sending clock based on ready
*/

module cdc_mcp_send_fdbk(
  aclk,     // sending clk
  arstb,    // sending clk reset
  adata_in, // sending data
  asend,    // send pulse
  b_ack,    // ack from recenving clk
  aready,   // ready to sending logic
  adata,    // output sync'd data
  a_en      // output control
);
  parameter DWIDTH = 32;
  parameter SYNC_DEPTH = 2;

  input logic aclk;
  input logic arstb;
  input logic [DWIDTH-1:0] adata_in;
  input logic asend;
  output logic aready;
  
  input logic b_ack;
  output logic [DWIDTH-1:0] adata;
  output logic a_en;
  
  // local signals
  logic a_load_en;
  logic state;      // 0-wait, 1-ready
  logic nx_state;   // 1-wait, 0-ready
  logic aack;       // ack sync'd from receiving clk
  
  // sending clock domain
  always_ff @(posedge aclk or negedge arstb)
  if (!arstb) begin
    adata <= 0;
    a_en <= 0;
  end else begin
    if(a_load_en) begin
      a_en <= !a_en;
      adata <= adata_in;
    end
  end
  
  always_ff @(posedge aclk or negedge arstb)
    if (!arstb)   state<= 0;
    else          state<=nx_state;
  
  always_comb
  begin
    aready=0;
    case(state)
      1'b0: // ready state
      begin
        nx_state=1'b0;
        aready=1'b1;
        if(asend)    nx_state=1'b1; // go to wait after send
      end
  
      1'b1:   // wait state 
      begin
        nx_state=1'b1;
        if (aack)    nx_state=1'b0;  // go to ready state after ack from receving clk
      end
    endcase
  end

  // a_load_en 1-clk pulse, aready goes to 0 after 1-clk
  assign a_load_en = aready & asend;

  // sync b_ack to aack
  metasync_Nflop #(.META_EN(1), .DATA_WIDTH(1), .META_SYNCFLOP_DEPTH(SYNC_DEPTH)) b_ack_sync(
    .clk(aclk),                  
    .rstb(arstb),      
    .data_in(b_ack),         
    .data_out(aack)   
  );

endmodule
/********************************************************************/

/* 5.6.3 Closed-loop - MCP formulation with acknowledge feedback */

/*
* cdc_mcp_send_fdbk_ack
*/

module cdc_mcp_receive_ack(
  bclk,
  brstb,
  bdata,
  bvalid,
  bload,
  b_ack,
  adata,
  a_en
);
  parameter DWIDTH=32;
  parameter SYNC_DEPTH=2;

  input logic bclk;
  input logic brstb;
  output logic [DWIDTH-1:0]bdata;
  output logic bvalid;
  input logic bload;
  output logic b_ack;
  input logic [DWIDTH-1:0] adata;
  input logic a_en;

// local signals
  logic b_load_en;  // enable pulse to load bdata
  logic state;      // 1-ready, 0-wait
  logic nx_state;   // 1-ready, 0-wait
  logic b_en;

// sync aclk to bclk
  metasync_Nflop#(.META_EN(1), .DATA_WIDTH(1), .META_SYNCFLOP_DEPTH(SYNC_DEPTH)) a_en_sync(
    .clk(bclk),                  
    .rstb(brstb),      
    .data_in(a_en),         
    .data_out(b_en)   
  );

// load adata when load is high
  always_ff @(posedge bclk or negedge brstb)
    if (!brstb) begin
      bdata<=0;
      state<=0;
      b_ack<=0;
    end
    else begin
      state<=nx_state;
      if(b_load_en) begin
        bdata<=adata;
        b_ack <= !b_ack;
      end
    end
  
  always_comb
  begin
    bvalid=0;
    case(state)
    1'b0:   // wait state
    begin
      nx_state=0;
      if(b_en)  nx_state=1; // go to ready
    end

    1'b1:   // wait state
    begin
      nx_state=1;
      bvalid=1;
      if(bload) nx_state=0; // go to wait
    end
    endcase
  end

  // load adata to bdata when adata is valid(bvalid) and when bload is high
  assign b_load_en = bvalid & bload;

endmodule

/****************************************************************/
/*
* priority encoder msb to lsb
* pri_msb : 0-lsb high pri, 1-msb high pri
* pririty_out = bit position of highest/lowest priority in priority_enc_in vector
*/
module priority_enc_msb #(NUM_LOG=2) (priority_enc_in, enable, pri_msb, priority_out);
  parameter NUM = 1<<NUM_LOG;
  input pri_msb;
  input logic [NUM-1:0] priority_enc_in;
  input logic enable;
  output logic [NUM_LOG-1:0] priority_out;

  logic [NUM-1:0] part[NUM_LOG-1:0];
  logic [NUM-1:0] shf [NUM_LOG-1:0];
  logic [NUM_LOG-1:0] msb,lsb;
  logic [NUM-1:0] enc_in;
  int i;

  always_comb begin
    // swap when pri_msb=0
    for (i=NUM-1;i>=0;i=i-1) begin
      enc_in[NUM-1-i] = pri_msb ? priority_enc_in[NUM-1-i] : priority_enc_in[i];
    end
  end

  //priority encoder for next req in based on prev grant and current req_in
  genvar g;
  generate
  for (g=NUM_LOG-1;g>=0;g=g-1) begin
    if(g==NUM_LOG-1) begin
      always_comb begin
        shf[g] = 1<<g;  // shift 1 time, top half
        part[g] = enc_in; // input
        if(|(part[g] >> shf[g]))  msb[g]=1'b1; // shift right out low half
        else msb[g] = 0;
        part[g-1] = msb[g] ? (part[g] >> shf[g]):part[g] & ((1'b1<<shf[g])-1'b1); // keep top half or select low half
      end
    end else if(g==0) begin
      always_comb begin
        shf[g] = 1<<g;
        if (|(part[g] >> shf[g])) msb[g] = 1;
        else msb[g] = 0;
      end
    end else begin
      always_comb begin
        shf[g] = 1<<g;  // shift 1 time, top half
        if(|(part[g] >> shf[g]))  msb[g]=1'b1; // shift right out low half
        else msb[g] = 0;
        part[g-1] = msb[g] ? (part[g] >> shf[g]):part[g] & ((1'b1<<shf[g])-1'b1); // keep top half or select low half
      end
    end
  end
  endgenerate

  assign lsb = NUM-1-msb;
  assign priority_out = pri_msb ? msb : lsb;

endmodule

/****************************************************************/
/*
* priority encoder with highest priority to msb
* pri_msb : 0-lsb high pri, 1-msb high pri
* pririty_out = bit position of highest/lowest priority in priority_enc_in vector
*/
module priority_enc #(IN_WIDTH=8, OUT_WIDTH=$clog2(IN_WIDTH), PRI_MSB=1) (enc_in, enable, priority_out, valid);
  input logic [IN_WIDTH-1:0] enc_in;
  input logic enable;
  output logic [OUT_WIDTH-1:0] priority_out;
  output logic valid;

  logic [IN_WIDTH-1:0] stop;
  logic [OUT_WIDTH-1] idx;

  if (PRI_MSB==1) begin
    always_comb begin
      if(!enable) begin
        stop = 0;
        priority_out = 0;
        valid = 0;
      end else begin
        stop = 0;
        priority_out = 0;
        valid = 0;
        for(idx=IN_WIDTH-1;i>=0;i=i+1) begin
          if(enc_in[idx] && !(|stop)) begin
            {priority_enc, stop[idx]} = {idx, 1'b1};
            valid = stop[idx];
          end
        end
      end
    end
  end
  else if (PRI_MSB==0) begin
    always_comb begin
      if(!enable) begin
        stop = 0;
        priority_out = 0;
        valid = 0;
      end else begin      
        stop = 0;
        priority_out = 0;
        valid = 0;
        for(idx=0;i<IN_WIDTH;i=i-1) begin
          if(enc_in[idx] && !(|stop)) begin
            {priority_enc, stop[idx]} = {idx, 1'b1};
            valid = stop[idx];
          end
        end
      end
    end    
  end

endmodule
