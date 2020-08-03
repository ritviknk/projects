/****************************************************************
* File name     : pckt_decoder.sv
* Creation date : 10-06-2020
* Last modified : Sun 02 Aug 2020 08:22:30 PM MDT
* Author        : Ritvik Nadig Krishnmurthy
* Description   :
*****************************************************************/
`timescale  1 ns/1 ps

module pckt_decoder(clk, rstb, in_sop, in_eop, in_data, in_empty, in_error, out_valid, out_data, out_bytemask, read_en, read_data_valid, fifo_empty);
  parameter IWIDTH = 8; // 8*8=64B
  parameter OWIDTH = 32;// 8*32=256B
  parameter logic [15:0] MINLEN = 'h8;

/*
in_data 63:0 - 8B
in_empty 7:0 8b
out_data 127:0 16B
out_bytemask 15:0 16b
nx_out_idx, out_idx 4:0 5b, 32 max, req 24 for out_data_temp
out_data_temp 23:0 7:0 - 8+16B
spill 7:0 7:0 8B
spill_len 2:0 
spill_data 15:0 7:0 16B
spill_bytes 3:0 4b for 16 max
data 0:1 7:0 7:0 , 2D 8B
data_bytes 0:1 2:0 - 2D 3bits for 8 max
*/

// inputs
input logic clk, rstb;

input logic in_sop, in_eop,in_error, fifo_empty, read_data_valid;
input logic [IWIDTH-1:0][7:0] in_data;
input logic [IWIDTH-1:0] in_empty;

// outputs
output logic out_valid, read_en;
output logic [OWIDTH-1:0][7:0] out_data;
output logic [OWIDTH-1:0] out_bytemask;

// one hot encoding
localparam S0i   = 0;
localparam S1i   = 1;
localparam S2i   = 2;
localparam S3i   = 3;
localparam S4i   = 4;
localparam S5i   = 5;
localparam S6i   = 6;
localparam S1_Pi = 7;
localparam ERRORi= 8;
localparam STALLi= 9;
localparam MAX_ST = 10; // change when adding new state

localparam logic [MAX_ST-1:0] IDLE = 'b0;   // Idle state
localparam logic [MAX_ST-1:0] ERROR= 1'b1 << ERRORi;   // error data stream
localparam logic [MAX_ST-1:0] STALL= 1'b1 << STALLi;   // stall FSM when fifo is empty

localparam logic [MAX_ST-1:0] S0   = 1'b1 << S0i;     // MC, ML, P, sop - first data stream of packet
localparam logic [MAX_ST-1:0] S1   = 1'b1 << S1i;     // P, ML, P - last data for current msg, first data for next msg
localparam logic [MAX_ST-1:0] S2   = 1'b1 << S2i;     // P - all data 
localparam logic [MAX_ST-1:0] S3   = 1'b1 << S3i;     // ML1, P - partial msg len and data
localparam logic [MAX_ST-1:0] S4   = 1'b1 << S4i;     // P, ML1 - last data for current msg, next msg len partial
localparam logic [MAX_ST-1:0] S5   = 1'b1 << S5i;     // ML, P - start of msg
localparam logic [MAX_ST-1:0] S6   = 1'b1 << S6i;     // P, ML - end of current msg, next msg len
localparam logic [MAX_ST-1:0] S1_P = 1'b1 << S1_Pi;   // partial message update state after S1

localparam ML_LEN = 16;
localparam MC_LEN = 16;

/************************* local signals ************************/
/*******************************************************************/
logic [MAX_ST-1:0] state;
logic [MAX_ST-1:0] nx_state;

// control signals

  // message count controls, MessageCount field, indices
  // 1st pipeline state variables
logic                       idle;
logic                       upd_mc;
logic [MC_LEN-1:0]          msg_cnt, nx_msg_cnt;
logic [$clog2(MINLEN)-1:0]  mc_st, mc_end;

  // message length controls, MessageLength field, indices
logic [1:0]                 upd_ml;                       // 2 bits to handle partial msg_len
logic [ML_LEN-1:0]          msg_len, nx_msg_len, cur_len, temp_msg_len;
logic [$clog2(MINLEN)-1:0]  ml_st, ml_end;

  // message data controls, data payload fields, indices
logic                       upd_len;
logic [$clog2(MINLEN)-1:0]  p_st, p_end;

  // FSM flow controls
logic                       msg_end, pckt_end;
logic                       msg_len_gt8, msg_len_7, msg_len_6, msg_len_8, msg_len_lt6, msg_len_0;

  // 2nd stage pipeline variables
logic [IWIDTH-1:0][7:0]     data_p1;
logic [IWIDTH-1:0]          byte_enable_p1, byte_enable_p;
logic                       data_valid_p1;
logic [$clog2(IWIDTH):0]    byte_count_p1;
logic                       msg_end_p0, msg_end_p1;

logic                             spill_valid, spill_valid_int;
logic [IWIDTH-1:0][7:0]           spill_data;
logic [IWIDTH-1:0]                spill_bytemask;
logic [$clog2(IWIDTH):0]          spill_count;
logic [$clog2(IWIDTH):0]          nx_spill_count;
logic [$clog2(OWIDTH+IWIDTH)-1:0] acc_idx, nx_acc_idx;
logic [$clog2(OWIDTH+IWIDTH)-1:0] acc_cnt, nx_acc_cnt;
logic [OWIDTH+IWIDTH-1:0][7:0]    packed_data;
logic [OWIDTH+IWIDTH-1:0]         packed_bytemask;
logic                             out_valid_int;
  // iterater variables
int i,d;

/************************* Functional Logic ************************/
/*******************************************************************/

// state register
always_ff @(posedge clk or negedge rstb)
  if (!rstb)  state <= 0;
  else if (nx_state != state)
              state <= nx_state;


/*********** state transition logic **********/

/* common transition path
 if msg len >  8 - go to S2
 if msg len == 8 - go to S2
 if msg len == 7 - go to S4
 if msg len == 6 - go to S6
 if msg len <  6 - go to S1
 if msg len == 0 - go to S0

S1    : if not end of packet go to S1_P, if end of packet go to S0
S2    : common
S3    : common
S4    : if not end of packet go to S3, if end of packet go to S0
S5    : common 
S6    : if not end of packet go to S2 as min msg len is 8, if end of packet go to S0
S1_P  : common 
ERROR : if end of packet is not aligned with end of message go to ERROR, 
        wait here until start of packet is seen
STALL :
*/

assign idle = (state == 0); // IDLE state decode

always_comb begin
  // when in IDLE, wait for fifo_empty
  if(idle) begin
    if(!fifo_empty)   nx_state  = S0;
    else              nx_state  = IDLE;
  end
  
  // if fifo goes empty and not end of packet, stall
  //else if (fifo_empty & !in_eop) begin
  //  nx_state = 0;
  //  nx_state[STALL] = 1'b1;
  //end

  // if fifo is not empty and not in IDLE state
  else
    case(state)
      S0  :
        begin
          if(in_sop)
          case({msg_len_gt8, msg_len_8, msg_len_7, msg_len_6, msg_len_lt6, msg_len_0})
            6'b100000:  begin nx_state = S2;    end
            6'b010000:  begin nx_state = S2;    end
            6'b001000:  begin nx_state = S4;    end
            6'b000100:  begin nx_state = S6;    end
            6'b000010:  begin nx_state = S1;    end
            6'b000001,  
            6'b000000:  begin nx_state = ERROR; end
            default  :        nx_state = state;
          endcase
          
          else
                              nx_state = state;
        end
      
      S1  :
        begin
                              nx_state = state;
          if(in_eop)    begin nx_state = S0;    end
          else          begin nx_state = S1_P;  end
        end
      
      S1_P:
        begin
                              nx_state = state;
          if(in_eop)    begin nx_state = ERROR; end
          else
          case({msg_len_gt8, msg_len_8, msg_len_7, msg_len_6, msg_len_lt6, msg_len_0})
            6'b100000:  begin nx_state = S2;    end
            6'b010000:  begin nx_state = S2;    end
            6'b001000:  begin nx_state = S4;    end
            6'b000100:  begin nx_state = S6;    end
            6'b000010:  begin nx_state = S1;    end
            6'b000001:  begin nx_state = ERROR; end
            default  :        nx_state = state;
          endcase       
        end

      S2:
        begin
                              nx_state = state;
          case({msg_len_gt8, msg_len_8, msg_len_7, msg_len_6, msg_len_lt6, msg_len_0})
            6'b100000:  begin nx_state = S2;    end
            6'b010000:  begin nx_state = S2;    end
            6'b001000:  begin nx_state = S4;    end
            6'b000100:  begin nx_state = S6;    end
            6'b000010:  begin nx_state = S1;    end
            6'b000001:  
            begin
              if(in_eop)begin nx_state = S0;    end
              else      begin nx_state = S5;    end
            end
            default  :        nx_state = state;
          endcase       
        end

      S3:
        begin
                              nx_state = state;
          case({msg_len_gt8, msg_len_7, msg_len_6, msg_len_8, msg_len_lt6, msg_len_0})
            6'b100000:  begin nx_state = S2;    end
            6'b010000:  begin nx_state = S2;    end
            6'b001000:  begin nx_state = S4;    end
            6'b000100:  begin nx_state = S6;    end
            6'b000010:  begin nx_state = S1;    end
            6'b000001:  begin nx_state = ERROR; end
            default  :        nx_state = state;
          endcase               
        end

      S4:
        begin
                              nx_state = state;
            if(in_eop)  begin nx_state = S0;    end
            else        begin nx_state = S3;    end
        end

      S5:
        begin
                              nx_state = state;
          case({msg_len_gt8, msg_len_7, msg_len_6, msg_len_8, msg_len_lt6, msg_len_0})
            6'b100000:  begin nx_state = S2;    end
            6'b010000:  begin nx_state = S2;    end
            6'b001000:  begin nx_state = S4;    end
            6'b000100:  begin nx_state = S6;    end
            6'b000010:  begin nx_state = S1;    end
            6'b000001:  begin nx_state = ERROR; end
            default  :        nx_state = state;
          endcase    
        end

      S6:
        begin
                            nx_state = state;
          if(in_eop)  begin nx_state = S0;    end
          else        begin nx_state = S2;    end
        end

      ERROR:
        begin
                            nx_state = state;
          if(in_sop)  begin nx_state = S0;        end
        end

      STALL:
        begin
          if(!fifo_empty)       nx_state = state;
          else begin
            case({msg_len_gt8, msg_len_7, msg_len_6, msg_len_8, msg_len_lt6, msg_len_0})
              6'b100000:  begin nx_state = S2;    end
              6'b010000:  begin nx_state = S2;    end
              6'b001000:  begin nx_state = S4;    end
              6'b000100:  begin nx_state = S6;    end
              6'b000010:  begin nx_state = S1;    end
              6'b000001:  begin nx_state = ERROR; end
              default  :        nx_state = state;
            endcase             
          end
        end
      default     : 
        begin
                                nx_state = nx_state;
        end

    endcase
end

/******************** control output, control data logic *****************/

// nx_msg_len comparator logic
assign msg_len_gt8  = (nx_msg_len>'b1000);
assign msg_len_8    = (nx_msg_len=='b1000);
assign msg_len_7    = (nx_msg_len=='b111);
assign msg_len_6    = (nx_msg_len=='b110);
assign msg_len_lt6  = (nx_msg_len<'b110) & !msg_len_0;
assign msg_len_0    = (nx_msg_len=='b0);

  // constant control signals
assign mc_st        = IWIDTH-1;
assign mc_end       = IWIDTH-2;

// control outputs
always_comb begin
  if(idle) begin
    upd_mc    = 0;
    upd_ml    = 0;
    upd_len   = 0;
    ml_st     = 0;
    ml_end    = 0;
    msg_end   = 0;
    cur_len   = 0;
    p_st      = 0;
    p_end     = 0;
    read_en   = 0;
  end
  else
    upd_mc  = 0;
    upd_ml  = 2'b00;
    msg_end = 0;
    case(state)
      S0    : 
      begin
        read_en = 1;
        if(in_sop) begin
          upd_mc  = 1;
          upd_ml  = 2'b11;
          upd_len = 1;
          ml_st   = IWIDTH-3;
          ml_end  = IWIDTH-4;
          p_st    = IWIDTH-5;
          p_end   = 0;
          cur_len = 4;
        end
      end

      S1    :
      begin
        read_en = 0;
        upd_ml  = pckt_end ? 2'b00 : 2'b11;
        // current message
        upd_len = 1;
        p_st    = IWIDTH-1;
        p_end	  = IWIDTH-msg_len;
        msg_end = 1;
        
        // next message
        ml_st   = IWIDTH-msg_len-1;
        ml_end  = IWIDTH-msg_len-2;
        cur_len = msg_len;
      end

      S1_P    :
      begin
        read_en = 1;
        upd_ml  = 2'b11;
        // new current message
        upd_len = 1;
        ml_st   = IWIDTH-cur_len -1;
        ml_end  = IWIDTH-cur_len -2;
        p_st    = IWIDTH-cur_len -3;
        p_end	  = 0;
        cur_len = IWIDTH-cur_len -2;
      end

      S2    :
      begin
        read_en = 1;
        upd_len = 1;
        p_st    = IWIDTH-1;
        p_end	  = 0;
        cur_len = IWIDTH;
        msg_end = (msg_len==IWIDTH);
      end

      S3    :
      begin
        read_en = 1;
        upd_ml  = 2'b01;
        upd_len = 1;
        ml_st   = 0;
        ml_end  = IWIDTH-1;
        p_st    = IWIDTH-2;
        p_end	  = 0;
        cur_len = 7;
      end

      S4    :
      begin
        read_en = 1;
        upd_ml  = pckt_end ? 2'b00 : 2'b10;
        upd_len = 1;
        ml_st   = 0;
        ml_end  = 0;
        p_st    = IWIDTH-1;
        p_end	  = 1;
        cur_len = 7;       
        msg_end = 1;
      end

      S5    :
      begin
        read_en = 1;
        upd_ml  = 2'b11;
        upd_len = 1;
        ml_st   = IWIDTH-1;
        ml_end  = IWIDTH-2;
        p_st    = IWIDTH-3;
        p_end	  = 0;
        cur_len = 6;
      end

      S6    :
      begin
        read_en = 1;
        upd_ml  = pckt_end ? 2'b00 : 2'b11;
        upd_len = 1;
        ml_st   = 1;
        ml_end  = 0;
        p_st    = IWIDTH-1;
        p_end	  = 2;
        cur_len = 6;
        msg_end = (msg_len==cur_len);
      end

      ERROR : // TODO
      begin
        upd_mc    = 0;
        upd_ml    = 0;
        upd_len   = 0;
        ml_st     = 0;
        ml_end    = 0;
        msg_end   = 0;
        cur_len   = 0;
        p_st      = 0;
        p_end     = 0;
        read_en   = !fifo_empty;        
      end

      STALL : // TODO
      begin
        upd_mc    = 0;
        upd_ml    = 0;
        upd_len   = 0;
        ml_st     = 0;
        ml_end    = 0;
        msg_end   = 0;
        cur_len   = 0;
        p_st      = 0;
        p_end     = 0;
        read_en   = !fifo_empty;        
      end
      default     : 
      begin
        upd_mc    = upd_mc ;
        upd_ml    = upd_ml ;
        upd_len   = upd_len;
        ml_st     = ml_st  ;
        ml_end    = ml_end ;
        msg_end   = msg_end;
        cur_len   = cur_len;
        p_st      = p_st   ;
        p_end     = p_end  ;
        read_en   = read_en; 
      end

    endcase
end

/***** msg_len, msg_cnt, data register logic **********/
always_ff @(posedge clk or negedge rstb)
  if(!rstb) begin
    msg_len <= 0;
    msg_cnt <= 0;
  end
  else begin
    msg_len <= nx_msg_len;
    msg_cnt <= nx_msg_cnt;
  end

/**************** msg len logic *********************/
always_comb begin
  temp_msg_len = get_msg_len(ml_st, ml_end);
  case({upd_len, upd_ml})
    //only upd len
    3'b100  : nx_msg_len = msg_len - cur_len;

    // upd len and collect new msg len
    3'b111  : nx_msg_len = temp_msg_len - cur_len;

    //new msg len only, end of curr msg
    3'b011  : nx_msg_len = temp_msg_len;

    // partial msg len
    3'b010  : nx_msg_len = temp_msg_len;

    // msg len complete, upd len
    3'b101  : nx_msg_len = temp_msg_len - cur_len;

    default : nx_msg_len = msg_len;
  endcase
end

function logic [15:0] get_msg_len(
  input logic [$clog2(MINLEN)-1:0] start_idx,
  input logic [$clog2(MINLEN)-1:0] end_idx);
  
  get_msg_len = msg_len;  // retain old value as default
  if(upd_ml[0] == 1'b1) get_msg_len[7:0]  = in_data[end_idx];
  if(upd_ml[1] == 1'b1) get_msg_len[15:8] = in_data[start_idx];

endfunction

/**************** msg cnt logic *********************/
always_comb begin
       if (upd_mc)  nx_msg_cnt = in_data[7:6];
  else if (msg_end) nx_msg_cnt = msg_cnt -1;
  else              nx_msg_cnt = msg_cnt;
end
assign pckt_end = (nx_msg_cnt==0) && msg_end;

/**************** data message logic *********************/
// pipelined data message payload, byte_enables, current length

always_comb begin
  byte_enable_p = get_byte_enables(p_st, p_end);
end

always_ff @(posedge clk) 
  if (~rstb) begin
    data_valid_p1   <= 0;
    data_p1         <= 0;
    byte_enable_p1  <= 0;
    byte_count_p1   <= 0;
    msg_end_p1      <= 0;
  end
  else if (upd_len) begin
    data_valid_p1   <= 1;
    data_p1         <= get_msg(p_st, p_end, byte_enable_p);
    byte_enable_p1  <= byte_enable_p;//get_byte_enables(p_st, p_end);
    byte_count_p1   <= cur_len;
    msg_end_p1      <= msg_end;
  end

  // drive valid low, and not data to save power
  else
    data_valid_p1   <= 0;

/**************** message accumulator logic *********************/
/*  
*
*/

always_ff @(posedge clk or negedge rstb) 
  if(!rstb) begin
    msg_end_p0      <= 0;
    acc_idx         <= OWIDTH+IWIDTH-1;
    acc_cnt         <= 0;
    packed_data     <= 0;
    packed_bytemask <= 0;
    spill_count     <= 0;
    out_valid_int   <= 0;
    spill_valid_int <= 0;
  end

  else begin

    spill_count     <= nx_spill_count;
  
    // if data_p1 is ready
    if (data_valid_p1 | spill_valid) begin
      msg_end_p0  <= msg_end_p1;

      // data payload is accumulating is less then OWIDTH bytes, no spill over
      if(~spill_valid) begin

        case({msg_end_p1, msg_end_p0})
          2'b00: begin // normal accumulate state
            acc_idx <= nx_acc_idx; //acc_idx - byte_count_p1;
            acc_cnt <= nx_acc_cnt; //acc_cnt + byte_count_p1;
          end
          2'b01: begin // current out_data is end of msg, data_p1 is new msg
            acc_idx <= nx_acc_idx; //acc_idx - byte_count_p1;
            acc_cnt <= byte_count_p1;
          end
          2'b10: begin // data_p1 is end of msg
            acc_idx <= OWIDTH+IWIDTH-1;
            acc_cnt <= nx_acc_cnt; //acc_cnt + byte_count_p1;
          end
          2'b11: begin // current out_data is end of msg, new data_p1 is end of msg
            acc_idx <= OWIDTH+IWIDTH-1;
            acc_cnt <= byte_count_p1;
          end
        endcase
        
        for(d=0;d<IWIDTH;d++) begin
          packed_data     [d+acc_idx-IWIDTH+1]  <= data_p1[d];
          packed_bytemask [d+acc_idx-IWIDTH+1]  <= byte_enable_p1[d];
        end

        spill_valid_int <= 0;
        out_valid_int   <= 0;

      end

      // if accumulating data exceeds OWIDTH bytes and spills over,
      // or data_p is not ready and only spill is ready
      else begin
        // if the data in spill bytes is not end of message
        // put spill data and new data into outbytes, 
        // this should not cause spill
        // if new data is end of message , valid will be set and index will be
        // reset in else block
        if (~msg_end_p0) begin
          acc_idx <= OWIDTH+IWIDTH-1;

          // if this the end of message in current data_p, reset acc_cnt
          if (msg_end_p1) begin
            acc_cnt <= 0;
            out_valid_int <= 1;
          end
          // if not end of message in data_p, increment count
          else begin
            acc_cnt <= spill_count + byte_count_p1;
            out_valid_int <= 0;
          end

          // out_data <= {spill data, data_p}
          packed_data    [OWIDTH+IWIDTH-1              : 0     ]  <= {spill_data,     {OWIDTH{8'h00}}};
          packed_bytemask[OWIDTH+IWIDTH-1              : 0     ]  <= {spill_bytemask, {OWIDTH{1'b0}}};
          packed_data    [OWIDTH+IWIDTH-1-spill_count -: IWIDTH]  <= data_p1;
          packed_bytemask[OWIDTH+IWIDTH-1-spill_count -: IWIDTH]  <= byte_enable_p1;
          spill_valid_int                                         <= 0;
        end

        // if spill data is end of message, put spill data in out_data
        // put new data in spill data, 
        // if new data is end of message, valid be set and index will be reset
        // on next clock cycle
        else if (msg_end_p0) begin
          acc_idx                               <= OWIDTH+IWIDTH-1;
          acc_cnt                               <= spill_count;
          spill_count                           <= byte_count_p1;
          packed_data     [OWIDTH+IWIDTH-1 : 0] <= {spill_data,     {OWIDTH{8'h00}}};
          packed_bytemask [OWIDTH+IWIDTH-1 : 0] <= {spill_bytemask, {OWIDTH{1'b0}}};
          packed_data     [IWIDTH-1:0]          <= data_p1;
          packed_bytemask [IWIDTH-1:0]          <= byte_enable_p1;
          out_valid_int                         <= 1;
          spill_valid_int                       <= 1;
        end
      end
    end
  end

assign spill_valid  = (acc_cnt > OWIDTH) || spill_valid_int;
assign nx_acc_idx   = acc_idx - byte_count_p1;
assign nx_acc_cnt   = acc_cnt + byte_count_p1;

always_comb begin
  if(acc_cnt + byte_count_p1 > OWIDTH)
    nx_spill_count  = (acc_cnt + byte_count_p1 - OWIDTH);
  else
    nx_spill_count  = 0;
end


/* outputs */
assign {out_data,spill_data}          = packed_data;
assign {out_bytemask,spill_bytemask}  = packed_bytemask;
assign out_valid                      = (acc_cnt[$size(acc_cnt)-1] == 1'b1) || msg_end_p0 || out_valid_int;


/**************** data message selection logic *********************/
// to select in_data[start_idx : end_idx],
// shift left in_data,  7 - start_idx bytes
// this will shift in 'b0 7 bytes when start_idx=0,
// if start_idx >0, data_temp will have in_data[end_idx-1:0] which will be
//   invalidated by byte_enable=0
function logic [IWIDTH-1:0][7:0] get_msg(
  input logic [$clog2(IWIDTH)-1:0]  start_idx,
  input logic [$clog2(IWIDTH)-1:0]  end_idx,
  input logic [IWIDTH-1:0]          byte_enable);
        logic [IWIDTH*2-1:0][7:0]   data_pkd_0ext;
        logic [IWIDTH-1:0][7:0]     temp_msg;

  // create a new data vector with 8B zero padding to left shift in zeros
  data_pkd_0ext       = {in_data,{IWIDTH*8{1'b0}}};

  // data selection can depend only on start_idx as invalid data after end_idx
  // will be discarded due to byte_enables being 0 in get_byte_enables()
  
  temp_msg[IWIDTH-1:0] = data_pkd_0ext[start_idx+IWIDTH -: 8];
  for(d=IWIDTH-1;d>=0;d--) begin
    if(byte_enable[d])  get_msg[d] = temp_msg[d];
    else                get_msg[d] = data_p1[d];
  end

  //TODO  : shifting left zeros will increase power
  //      : how to not shift left zeroa and not synth lathc
endfunction

/**************** data message byte enable logic *********************/
// to select in_data[start_idx : end_idx],
// shift in_data start_idx-end_idx+1 bytes from start_idx,
// this will shift in 'b0 7 bytes when start_idx=0,
// if start_idx >0, data_temp will have in_data[end_idx-1:0] which will be
//   invalidated by byte_enable=0

function logic [IWIDTH-1:0] get_byte_enables(
  input logic [$clog2(IWIDTH)-1:0]  start_idx,
  input logic [$clog2(IWIDTH)-1:0]  end_idx);
        logic [$clog2(IWIDTH):0]    ones;
        logic [IWIDTH-1:0]          byte_enables;

  ones = start_idx - end_idx + 1'b1;

  case(ones)
    1: get_byte_enables = 8'b1000_0000;
    2: get_byte_enables = 8'b1100_0000;
    3: get_byte_enables = 8'b1110_0000;
    4: get_byte_enables = 8'b1111_0000;
    5: get_byte_enables = 8'b1111_1000;
    6: get_byte_enables = 8'b1111_1100;
    7: get_byte_enables = 8'b1111_1110;
    8: get_byte_enables = 8'b1111_1111;
  endcase

endfunction

logic [10*8-1:0] state_ascii; // 10 chars
always_comb begin
  case(state)
    IDLE  : state_ascii = "Idle-st";
    ERROR : state_ascii = "Error-st";
    STALL : state_ascii = "Stall-st";
    S0    : state_ascii = "S0-st";
    S1    : state_ascii = "S1-st";
    S2    : state_ascii = "S2-st";
    S3    : state_ascii = "S3-st";
    S4    : state_ascii = "S4-st";
    S5    : state_ascii = "S5-st";
    S6    : state_ascii = "S6-st";
    S1_P  : state_ascii = "S1_P-st";
    default: state_ascii = state_ascii;
  endcase
end
endmodule

