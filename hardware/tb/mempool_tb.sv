// Copyright 2019 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

import "DPI-C" function void read_elf (input string filename);
import "DPI-C" function byte get_section (output longint address, output longint len);
import "DPI-C" context function byte read_section(input longint address, inout byte buffer[]);

module mempool_tb;

  /*****************
   *  Definitions  *
   *****************/

  timeunit      1ns;
  timeprecision 1ps;

  import mempool_pkg::*;
  import axi_pkg::xbar_cfg_t;
  import axi_pkg::xbar_rule_32_t;

  `ifdef NUM_CORES
  localparam NumCores = `NUM_CORES;
  `else
  localparam NumCores = 256;
  `endif

  `ifdef BOOT_ADDR
  localparam BootAddr = `BOOT_ADDR;
  `else
  localparam BootAddr = 0;
  `endif

  localparam        BankingFactor    = 4;
  localparam addr_t TCDMBaseAddr     = '0;
  localparam        TCDMSizePerBank  = 1024 /* [B] */;
  localparam        NumTiles         = NumCores / NumCoresPerTile;
  localparam        NumTilesPerGroup = NumTiles / NumGroups;
  localparam        NumBanks         = NumCores * BankingFactor;
  localparam        TCDMSize         = NumBanks * TCDMSizePerBank;

  localparam ClockPeriod = 1ns;
  localparam TA          = 0.2ns;
  localparam TT          = 0.8ns;

  localparam L2AddrWidth = 18;

 /********************************
   *  Clock and Reset Generation  *
   ********************************/

  logic clk;
  logic rst_n;

  logic eoc_valid;

  // Toggling the clock
  always #(ClockPeriod/2) clk = !clk;

  // Controlling the reset
  initial begin
    clk   = 1'b1;
    rst_n = 1'b0;

    repeat (5)
      #(ClockPeriod);

    rst_n = 1'b1;
  end

  /*********
   *  AXI  *
   *********/

  `include "axi/assign.svh"

  localparam NumAXIMasters = 1;
  localparam NumAXISlaves  = 2;
  typedef enum logic [$clog2(NumAXISlaves)-1:0] {
    UART,
    HOST
  } axi_slave_target;

  axi_slv_req_t   [NumAXIMasters - 1:0] axi_mst_req;
  axi_slv_resp_t  [NumAXIMasters - 1:0] axi_mst_resp;
  axi_req_t       [NumAXISlaves - 1:0]  axi_mem_req;
  axi_resp_t      [NumAXISlaves - 1:0]  axi_mem_resp;

  localparam xbar_cfg_t XBarCfg = '{
    NoSlvPorts        : NumAXIMasters,
    NoMstPorts        : NumAXISlaves,
    MaxMstTrans       : 4,
    MaxSlvTrans       : 4,
    FallThrough       : 1'b0,
    LatencyMode       : axi_pkg::CUT_MST_PORTS,
    AxiIdWidthSlvPorts: dut.AxiSlvIdWidth,
    AxiIdUsedSlvPorts : dut.AxiSlvIdWidth,
    AxiAddrWidth      : AddrWidth,
    AxiDataWidth      : DataWidth,
    NoAddrRules       : NumAXISlaves
  };

  /*********
   *  DUT  *
   *********/

  mempool_system #(
    .NumCores       (NumCores     ),
    .BankingFactor  (BankingFactor),
    .TCDMBaseAddr   (TCDMBaseAddr ),
    .BootAddr       (BootAddr     )
  ) dut (
    .clk_i          (clk          ),
    .rst_ni         (rst_n        ),
    .fetch_en_i     (/*Unused*/   ),
    .eoc_valid_o    (eoc_valid    ),
    .busy_o         (/*Unused*/   ),
    .ext_req_o      (axi_mst_req  ),
    .ext_resp_i     (axi_mst_resp ),
    .ext_req_i      (/*Unused*/   ),
    .ext_resp_o     (/*Unused*/   ),
    .rab_conf_req_i (/*Unused*/   ),
    .rab_conf_resp_o(/*Unused*/   )
  );

  /**********************
   *  AXI Interconnect  *
   **********************/

  localparam addr_t UARTBaseAddr = 32'hC000_0000;
  localparam addr_t UARTEndAddr = 32'hC000_FFFF;
  localparam addr_t HOSTBaseAddr = 32'h0000_0000;
  localparam addr_t HOSTEndAddr = 32'hFFFF_FFFF;

  xbar_rule_32_t [NumAXISlaves-1:0] xbar_routing_rules = '{
    '{idx: UART, start_addr: UARTBaseAddr, end_addr: UARTEndAddr},
    '{idx: HOST, start_addr: HOSTBaseAddr, end_addr: HOSTEndAddr}};

  axi_xbar #(
    .Cfg          (XBarCfg       ),
    .slv_aw_chan_t(axi_slv_aw_t  ),
    .mst_aw_chan_t(axi_aw_t      ),
    .w_chan_t     (axi_w_t       ),
    .slv_b_chan_t (axi_slv_b_t   ),
    .mst_b_chan_t (axi_b_t       ),
    .slv_ar_chan_t(axi_slv_ar_t  ),
    .mst_ar_chan_t(axi_ar_t      ),
    .slv_r_chan_t (axi_slv_r_t   ),
    .mst_r_chan_t (axi_r_t       ),
    .slv_req_t    (axi_slv_req_t ),
    .slv_resp_t   (axi_slv_resp_t),
    .mst_req_t    (axi_req_t     ),
    .mst_resp_t   (axi_resp_t    ),
    .rule_t       (xbar_rule_32_t)
  ) i_testbench_xbar (
    .clk_i                (clk               ),
    .rst_ni               (rst_n             ),
    .test_i               (1'b0              ),
    .slv_ports_req_i      (axi_mst_req       ),
    .slv_ports_resp_o     (axi_mst_resp      ),
    .mst_ports_req_o      (/*Unused*/        ),
    .mst_ports_resp_i     (/*Unused*/        ),
    .addr_map_i           (xbar_routing_rules),
    .en_default_mst_port_i('0                ),
    .default_mst_port_i   ('0                )
  );

  /**********
   *  UART  *
   **********/

  // Printing
  axi_slv_id_t id_queue [$];

  initial begin
    automatic string sb = "";

    axi_mem_resp[UART] <= '0;
    while (1) begin
      @(posedge clk); #TT;
      fork
        begin
          wait(axi_mem_req[UART].aw_valid);
          axi_mem_resp[UART].aw_ready <= 1'b1;
          axi_mem_resp[UART].aw_ready <= @(posedge clk) 1'b0;
          id_queue.push_back(axi_mem_req[UART].aw.id);
        end
        begin
          wait(axi_mem_req[UART].w_valid);
          axi_mem_resp[UART].w_ready <= 1'b1;
          axi_mem_resp[UART].w_ready <= @(posedge clk) 1'b0;
          $write("%c", axi_mem_req[UART].w.data);
        end
      join

      // Send response
      axi_mem_resp[UART].b_valid = 1'b1;
      axi_mem_resp[UART].b.id    = id_queue.pop_front();
      axi_mem_resp[UART].b.resp  = axi_pkg::RESP_OKAY;
      axi_mem_resp[UART].b.user  = '0;
      wait(axi_mem_req[UART].b_ready);
      @(posedge clk);
      axi_mem_resp[UART].b_valid = 1'b0;
    end
  end

  /*********
   *  EOC  *
   *********/

  localparam addr_t EOCAddress = 32'h4000_0000;

  initial begin
    while (1) begin
        @(posedge clk); #TT;
        if (eoc_valid) begin
            // Finish simulation
            $timeformat(-9, 2, " ns", 0);
            // $display("[EOC] Simulation ended at %t (retval = %0d).", $time, axi_lite_ctrl_registers_req.w.data);
            $display("[EOC] Simulation ended at %t.", $time);
            $finish(0);
        end
    end
  end

 /************************
   *  Instruction Memory  *
   ************************/

  localparam addr_t ICacheBytes       = ICacheLineWidth / 8 ;
  localparam addr_t ICacheAddressMask = ~(ICacheBytes - 1);
  localparam addr_t ICacheByteOffset  = $clog2(ICacheBytes);

  logic [ICacheLineWidth-1:0] instr_memory[addr_t];

  for (genvar g = 0; g < NumGroups; g++) begin : drive_inst_mem_group
    for (genvar t = 0; t < NumTilesPerGroup; t++) begin : drive_inst_mem_tile
      for (genvar c = 0; c < NumCoresPerTile/NumCoresPerCache; c++) begin : drive_inst_mem_cache
        static addr_t address       = '0;
        static integer unsigned len = '0;

        initial begin
          while (1) begin
            @(posedge clk);
            #TA
            if (dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_qvalid_o[c]) begin
              // Respond to request
              address = dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_qaddr_o[c];
              len     = dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_qlen_o[c];

              cache_line_alignment: assume ((address & ICacheAddressMask) == address)
              else $fatal(1, "Tile %0d request instruction at %x, but we only support cache-line boundary addresses.", t, address);

              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_qready_i[c] = 1'b1;
              @(posedge clk);
              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_qready_i[c] = 1'b0;
              // Response
              for (int i = 0; i < len; i++) begin
                force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_pdata_i[c]  = instr_memory[address];
                force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_pvalid_i[c] = 1'b1;
                force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_plast_i[c]  = 1'b0;
                address += ICacheBytes;
                wait(dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_pready_o[c]);
                @(posedge clk);
              end
              // Last response
              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_pdata_i[c]  = instr_memory[address];
              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_pvalid_i[c] = 1'b1;
              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_plast_i[c]  = 1'b1;
              wait(dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_pready_o[c]);
              @(posedge clk);
              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_pvalid_i[c] = 1'b0;
              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_plast_i[c]  = 1'b0;
            end else begin
              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_pdata_i[c]  = '0;
              force dut.i_mempool.gen_groups[g].i_group.gen_tiles[t].i_tile.refill_qready_i[c] = 1'b0;
            end
          end
        end
      end
    end
  end

  /***************************
   *  Memory Initialization  *
   ***************************/

  initial begin : instr_memory_init
    automatic logic [ICacheLineWidth-1:0] mem_row;
    byte buffer [];
    addr_t address;
    addr_t length;
    string binary;

    // Initialize memories
    void'($value$plusargs("PRELOAD=%s", binary));
    if (binary != "") begin
      // Read ELF
      void'(read_elf(binary));
      $display("Loading %s", binary);
      while (get_section(address, length)) begin
        // Read sections
        automatic int nwords = (length + ICacheBytes - 1)/ICacheBytes;
        $display("Loading section %x of length %x", address, length);
        buffer = new[nwords * ICacheBytes];
        void'(read_section(address, buffer));
        // Initializing memories
        for (int w = 0; w < nwords; w++) begin
          mem_row = '0;
          for (int b = 0; b < ICacheBytes; b++) begin
            mem_row[8 * b +: 8] = buffer[w * ICacheBytes + b];
          end
          instr_memory[address + (w << ICacheByteOffset)] = mem_row;
        end
      end
    end
  end : instr_memory_init

  initial begin : l2_init
    automatic data_t mem_row;
    byte buffer [];
    addr_t address;
    addr_t length;
    string binary;

    // Initialize memories
    void'($value$plusargs("PRELOAD=%s", binary));
    if (binary != "") begin
      // Read ELF
      void'(read_elf(binary));
      $display("Loading %s", binary);
      while (get_section(address, length)) begin
        // Read sections
        automatic int nwords = (length + BeWidth - 1)/BeWidth;
        $display("Loading section %x of length %x", address, length);
        buffer = new[nwords * BeWidth];
        void'(read_section(address, buffer));
        // Initializing memories
        for (int w = 0; w < nwords; w++) begin
          mem_row = '0;
          for (int b = 0; b < BeWidth; b++) begin
            mem_row[8 * b +: 8] = buffer[w * BeWidth + b];
          end
          if (address >= dut.L2MemoryBaseAddr && address < dut.L2MemoryEndAddr)
            dut.l2_mem.init_val[(address - dut.L2MemoryBaseAddr + (w << ByteOffset)) >> ByteOffset] = mem_row;
          else
            $display("Cannot initialize address %x, which doesn't fall into the L2 region.", address);
        end
      end
    end
  end : l2_init

endmodule : mempool_tb
