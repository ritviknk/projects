# worksample
RTL design projects to showcase design skills, verilog language expertise and coding styles.

<pre>
1. Network Packet Decoder(Message Extractor):
</pre>
https://github.com/ritviknk/worksample/tree/master/network_packet_decoder/Docs
<pre>
   Problem statement : Design a verilog module to extract message payloads with variable lengths 
                       from a continuous stream of packets. 
   Design: FSM, Pipeline, FIFO
   - FSM based control path to read input packet data from a FIFO and output the message payload 
     and byte-enables.
   - Pipelined data and control path to produce throughput of 1 full message on every clock.
   - Incorporates FIFO with pre-fetch buffer for packet storage for upto 1000B of packet.
</pre>

<pre> 
2. Bitonic Sort:
</pre>
https://github.com/ritviknk/worksample/tree/master/bitonic_sort/Docs
<pre>
   Problem statement : Design a sorting module that can sort in ascending order large arrays of up to 
                       1024 elements(signed and unsigned : integers, fixedpoint, floting point), with 
                       optimal time complexity (no of clocks for latency and throughput) and space 
                       complexity (no of pipe stages and no of buffers for storage). Design module should 
                       read a block of 4 elements from SRAM.
   Design : 
   - Sorting of each data blocks is acheived by implementing Bitonic sort in each pipe stage.
   - Sorting of complete array is achieved using Bubble sort algorithm in pipelined fashion.
     Pipe stage 0 sorts i-th block, pipe stage 1 sorts i-th and (i-1)-the block to achieve sorting 8 elements.
   - Reads a block of 4 elements every clock from SRAM model.
   - One separate pipeline stage for sorted data.
   - Control path slects read logic and sort logic in the pipeline data path.
   - Time complexity : O(N^2)
      No of entries in one block-read                                = R (fixed to 4 in design)
      No of pipe stages                                              = S (fixed to 3 in design)
      Total no of blocks of data                                     = N (variable input)
      Total no of entries in data                                    = R*N (variable input)
      Read latency from SRAM                                         = 1
      Throughput (no of clocks required to sort N*R entries)         = N*(N-1)
      Latency (no of clocks required to output first sorted block)   = N*(N-2) + S + 1
   - Space complexity : O(K) = O(R*S)
      No of pipe stages                                              = S (fixed to 3 in design)
      No of buffers in each stage                                    = R (fixed to 4 in design)
</pre>      

<pre>
3. FIFO:
</pre>
https://github.com/ritviknk/worksample/tree/master/fifo_sram/Docs
<pre>
   Problem statement : Design a FIFO with pre-fetch buffer using SRAM model.
   Design: FSM, Synchronous FIFO
   - Synchronous FIFO controller with Full and Empty status bits, with protection to block writes 
     and reads when Full and Empty are active.
   - Pre-fetch buffer to reduce read latency from 2 clocks to 1 clock for continuous reads.
   - Incorporates True Dual Port Synchronous SRAM model.
   
</pre>
