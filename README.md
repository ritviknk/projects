# worksample
RTL design projects to showcase design skills, verilog language expertise and coding styles.
<pre>
1. Network Packet Decoder(Message Extractor):
   Problem statement : Design a verilog module to extract message payloads with variable lengths 
                       from a continuous stream of packets.
   https://github.com/ritviknk/worksample/tree/master/network_packet_decoder/Docs
   Design: FSM, Pipeline, FIFO
   - FSM based control path to read input packet data from a FIFO and output the message payload 
     and byte-enables.
   - Pipelined data and control path to produce throughput of 1 full message on every clock.
   - Incorporates FIFO with pre-fetch buffer for packet storage for upto 1000B of packet.
</pre>
   
<pre>
2. FIFO:
   Problem statement : Design a FIFO with pre-fetch buffer using SRAM model.
   https://github.com/ritviknk/worksample/tree/master/fifo_sram/Docs
   Design: FSM, Synchronous FIFO
   - Synchronous FIFO controller with Full and Empty status bits, with protection to block writes 
     and reads when Full and Empty are active.
   - Pre-fetch buffer to reduce read latency from 2 clocks to 1 clock for continuous reads.
   - Incorporates True Dual Port Synchronous SRAM model.
   
</pre>
