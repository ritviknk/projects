
Network Packet Decoder(Message Extractor):

  Problem statement   : Design a verilog module to extract message payloads from a continuous stream of packets
<pre>  
  Design requirement  :
                      : Input data packet can be backpressured using ready from the design.
                      : Output message payload does not have any backpressure mechanism.
    Inputs:             
                      : The input data to the module is 8B wide, qualified by side band signals and byte_enables.
                      : in_data[7:0][7:0], valid, start-of-packet, end-of-packet, byte_enables
    Outputs: 
                      : The output of the module is 16B message payload, qualified with valid and byte-enables.
                      : If the message payload is less than 16B, valid must be asserted with appropriate byte-enables.
                      : out_data[15:0][7:0], valid, byte_enable[15:0]
                   
  Data packet format  :    
                      : Message Count   - number of data payloads present in the packet
                      : Message Length  - number of bytes of data payload in current message
                      : Data payload    - current message
                      
  | MsgCnt0 | MsgCnt1 | MsgLen0 | MsgLen1 | Payload..........| 
  | MsgLen0 | MsgLen1 | Payload..........| 
  | MsgLen0 | MsgLen1 | Payload..........|
  .
  .
  | MsgLen0 | MsgLen1 | Payload..........|
  
  Design constraints  :  
                      : The message payload minimux length is 8B, max length is 64B. Min length of packet is 12B, 
                        max length is 1000B.
                      : The design must be able to handle the worst case packet as defined below.
                        Len of packet = 1000B
                        Len MsgCnt    = 2B
                        Len MsgLen    = 2B
                        Max no. of message/payload possible 
                        = (max size of packet - MsgCnt len) / (min len of payload + MsgLen len)
                        = (1000-2)/(8+2) = 99.8
                        = 98 messages with 8B payload, 2B MsgLen and  1 message with 16B payload, 2B MsgLen
  </pre>
  
  Implementation details: Block diagrams and state transition details can be found :
    https://github.com/ritviknk/worksample/tree/master/network_packet_decoder/Docs
    
  * The design makes use of FIFO to store input data packet stream. 8B of data, start-of-packet, end-of-packet variabled are written to the FIFO.
  * The FIFO emtpy output is used as ready_b to backpressure the data producer.
  * The messge extraction / message decoder is desined using Finite State Machine. The FSM is micro-architected for 8B of min. message payload length.
  * The output buffer that holds the message payload is scaleable to any length, with an additional 8B spill buffer to store payload when the output 
  buffer is full. 
  * When the 16B output buffer is full or when the message ends, a valid signal is asserted along with byte-enables(1bit per byte) to qualify the output
  message.
  
  * FIFO depth calculation:\
  See https://github.com/ritviknk/worksample/tree/master/network_packet_decoder/Docs/Implementation_Doc.pdf for more details.\
  * It takes 125 clocks to send 1000B, so the FIFO write burst is 125. 
  *For the worst case packet, the design module takes 173 clocks to output all the 
  payloads. 
  * The FIFO depth is 173-125 = 48 enties.
  
  <pre>
  Latency:
  Input data setup latency  : 1 clock to setup input data stream with proper byte_enables prior to writing to FIFO. 
                              This serves as one pipeline stage to meet timing.
  FIFO latency              : 1 clock to write, 1 clock to read, total 2 clocks of latency.
                            : With pre-fetch buffer, latency reduces to 1 clock.
  Extractor latency         : FSM and the output buffer/accmulator have a total of 2 pipeline stages. 
                              So, 2 clocks latency.
  Total system latency      : 4 clocks latency, from first data at input and first output data in the output buffer. 
  </pre>
