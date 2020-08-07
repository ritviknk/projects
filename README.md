# worksample
RTL design projects to showcase design skills, verilog language expertise and coding styles.
<pre>
1. Network Packet Decoder(Message Extractor):
   Problem statement : Design a verilog module to extract message payloads from a continuous 
                       stream of packets
   Design:
   - Pipelined design module reads input packet data from a FIFO and extracts messaged with 
     variable lengths.
   - Incorporates SRAM-based FIFO with pre-fetch buffer for packet storage.
</pre>
   
<pre>
2. FIFO:
   Problem statement : Design a FIFO using SRAM.
   Design:
   - FIFO using True Dual Port Synchronous SRAM model.
   - Pre-fetch buffer to reduce read latency from 2 clocks to 1 clock for continuous reads.
</pre>
