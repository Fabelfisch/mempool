module snitch_hwloops #(
    parameter N_HW_LOOPS     = 2,
    /* do not override */
    parameter N_REG_BITS = $clog2(N_HW_LOOPS)
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,

    //selects the register set
    input  logic [N_REG_BITS-1:0]    hwloop_regid_i,

    // register data for setups
    input  logic           [31:0]    hwloop_start_address_i,
    input  logic           [31:0]    hwloop_end_address_i,
    input  logic           [31:0]    hwloop_cnt_data_i,

    // write enables for register setup
    input  logic                     hwloop_we_start_register_i,             // hwloop_we_i[0]
    input  logic                     hwloop_we_end_register_i,               // hwloop_we_i[1]
    input  logic                     hwloop_we_count_register_i,             // hwloop_we_i[2]

    // instruction valid
    input  logic                     hwloop_valid_i,

    // current program counter
    input  logic [31:0]              current_pc_i,

    // to instruction decode stage
    output logic [31:0]              hwloop_targ_addr_o,
    output logic                     hwloop_jump_o
);

    logic [N_HW_LOOPS-1:0] [31:0] hwloop_start;
    logic [N_HW_LOOPS-1:0] [31:0] hwloop_end;
    logic [N_HW_LOOPS-1:0]        hwloop_dec_cnt;

    logic [N_HW_LOOPS-1:0] pc_is_end_addr;

    //register state
    logic [N_HW_LOOPS-1:0] [31:0] hwloop_counter_q, hwloop_counter_d;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                  Hardware Loop Control Logic
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // generate comparators. check for end address and the loop counter
    genvar i;
    generate
        for (i = 0; i < N_HW_LOOPS; i++) begin
            always @(*) begin
                pc_is_end_addr[i] = 1'b0;
                if (current_pc_i == hwloop_end[i]) begin
                    if (hwloop_counter_q[i][31:2] != 30'h0) begin
                        pc_is_end_addr[i] = 1'b1;
                    // if it is the last iteration of the loop, it
                    // should not jump back to the start
                    end else /*(hwloop_counter_q[i][31:1] == 31'h0)*/begin
                        //pc_is_end_addr[i] = 1'b0;
                        case (hwloop_counter_q[i][1:0])
                            2'b11:        pc_is_end_addr[i] = 1'b1;
                            2'b10:        pc_is_end_addr[i] = 1'b1; //~hwlp_dec_cnt_id_i[i]; // only when there is nothing in flight
                            2'b01, 2'b00: pc_is_end_addr[i] = 1'b0;
                        endcase
                    end
                end
            end
        end
    endgenerate

    //loop variable
    integer j;

    // select corresponding start address and decrement counter
    always_comb begin
        hwloop_targ_addr_o = '0;
        hwloop_dec_cnt   = '0;

        for (j = 0; j < N_HW_LOOPS; j++) begin
            if (pc_is_end_addr[j]) begin
                hwloop_targ_addr_o  = hwloop_start[j];
                hwloop_dec_cnt[j] = 1'b1;
                break;
            end
        end
    end

    // output signal for ID stage
    // A jump is required, if any loop is at its end
    assign hwloop_jump_o = (|pc_is_end_addr);
    
    ////////////////////////////////////////////////////////////////////////////////////////////////
    //
    //                                  Hardware Loop Registers
    //
    ////////////////////////////////////////////////////////////////////////////////////////////////


    /////////////////////////////////////////////////////////////////////////////////
    //                      Hardware Loop Start-Address Register                                               //
    /////////////////////////////////////////////////////////////////////////////////
    always_ff @(posedge clk_i, negedge rst_ni) begin : HWLOOP_REGS_START
        if (rst_ni == 1'b0) begin
            hwloop_start <= '{default: 32'b0};
        end else if (hwloop_we_start_register_i == 1'b1) begin
            hwloop_start[hwloop_regid_i] <= hwloop_start_address_i;
        end
    end


    /////////////////////////////////////////////////////////////////////////////////
    //                       Hardware Loop End-Address Register                                                 //
    /////////////////////////////////////////////////////////////////////////////////
    always_ff @(posedge clk_i, negedge rst_ni) begin : HWLOOP_REGS_END
        if (rst_ni == 1'b0) begin
            hwloop_end <= '{default: 32'b0};
        end else if (hwloop_we_end_register_i == 1'b1) begin
            hwloop_end[hwloop_regid_i] <= hwloop_end_address_i;
        end
    end


    /////////////////////////////////////////////////////////////////////////////////
    //                Hardware Loop Counter Register and decrement logic                           //
    /////////////////////////////////////////////////////////////////////////////////
    
    //loop variables
    int unsigned l;
    genvar k;

    //set calculate decremented value
    for (k = 0; k < N_HW_LOOPS; k++) begin
        assign hwloop_counter_d[k] = hwloop_counter_q[k] - 1;
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin : HWLOOP_REGS_COUNTER
        if (rst_ni == 1'b0) begin
            hwloop_counter_q <= '{default: 32'b0};
        end else begin
            for (l = 0; l < N_HW_LOOPS; l++) begin
                if ((hwloop_we_count_register_i == 1'b1) && (l == hwloop_regid_i)) begin
                    hwloop_counter_q[l] <= hwloop_cnt_data_i;
                end else begin
                    if (hwloop_dec_cnt[l] && hwloop_valid_i) begin
                        hwloop_counter_q[l] <= hwloop_counter_d[l];
                    end
                end
            end
        end
    end

    //----------------------------------------------------------------------------
    // Assertions
    //----------------------------------------------------------------------------
    `ifndef VERILATOR
        // only decrement one counter at the time
        assert property (
        @(posedge clk_i) (hwloop_valid_i) |-> ($countones(hwloop_dec_cnt) <= 1) );
    `endif
endmodule