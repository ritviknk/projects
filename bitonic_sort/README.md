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
      
** TODO : compare functions for signed integer, signed and unsigned fixed point, floting point numbers **
</pre>   
