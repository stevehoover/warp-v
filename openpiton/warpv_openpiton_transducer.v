`include "iop.h"

`define MSG_DATA_SIZE_1B        3'b001  // define.h.pyv
`define MSG_DATA_SIZE_2B        3'b010
`define MSG_DATA_SIZE_4B        3'b011
`define L15_AMO_OP_WIDTH        4   // l15.h.pyv
`define PHY_ADDR_WIDTH          40  // define.h.pyv
`define PCX_REQTYPE_AMO `SWAP_RQ    // l15.h.pyv
`define CPX_RESTYPE_ATOMIC_RES 4'b1110 // custom type l15.h.pyv


module warpv_openpiton_transducer(
    input logic clk,
    input logic rst_n,

    // WARP-V --> L1.5
    input                           warpv_transducer_mem_valid,
    input [31:0]                    warpv_transducer_mem_addr,
    input [ 3:0]                    warpv_transducer_mem_wstrb,

    input [31:0]                    warpv_transducer_mem_wdata,
    input [`L15_AMO_OP_WIDTH-1:0]   warpv_transducer_mem_amo_op,
    input                           l15_transducer_ack,
    input                           l15_transducer_header_ack,

    // outputs warpv uses                    
    output reg [4:0]                transducer_l15_rqtype,
    output [`L15_AMO_OP_WIDTH-1:0]  transducer_l15_amo_op,
    output reg [2:0]                transducer_l15_size,
    output                          transducer_l15_val,
    output [`PHY_ADDR_WIDTH-1:0]    transducer_l15_address,
    output [63:0]                   transducer_l15_data,
    output                          transducer_l15_nc,

    // outputs warpv doesn't use                    
    output [0:0]                    transducer_l15_threadid,
    output                          transducer_l15_prefetch,
    output                          transducer_l15_invalidate_cacheline,
    output                          transducer_l15_blockstore,
    output                          transducer_l15_blockinitstore,
    output [1:0]                    transducer_l15_l1rplway,
    output [63:0]                   transducer_l15_data_next_entry,
    output [32:0]                   transducer_l15_csm_data,

    //--- L1.5 -> WARP-V
    input                           l15_transducer_val,
    input [3:0]                     l15_transducer_returntype,
    
    input [63:0]                    l15_transducer_data_0,
    input [63:0]                    l15_transducer_data_1,
    
    output reg                      transducer_warpv_mem_ready,
    output [31:0]                   transducer_warpv_mem_rdata,
    
    output                          transducer_l15_req_ack,
    output reg                      warpv_int);

    localparam ACK_IDLE = 1'b0;
    localparam ACK_WAIT = 1'b1;

// ** DECODER ** //              
    reg current_val;
    reg prev_val;
    wire new_request = current_val & ~prev_val;
    always @(posedge clk) begin
        if(!rst_n) begin
            current_val <= 0;
            prev_val    <= 0;
        end
        else begin
            current_val <= warpv_transducer_mem_valid;
            prev_val    <= current_val;
        end
    end

    // are we waiting for an ack
    reg ack_reg;
    reg ack_next;
    always @ (posedge clk) begin
        if (!rst_n) begin
            ack_reg <= 0;
        end
        else begin
            ack_reg <= ack_next;
        end
    end

    always @ (*) begin
        // be careful with these conditionals.
        if (l15_transducer_ack) begin
            ack_next = ACK_IDLE;
        end
        else if (new_request) begin
            ack_next = ACK_WAIT;
        end
        else begin
            ack_next = ack_reg;
        end
    end

    // if we haven't got an ack and it's an old request, valid should be high
    // otherwise if we got an ack valid should be high only if we got a new
    // request
    assign transducer_l15_val  =  (ack_reg == ACK_WAIT)   ?  warpv_transducer_mem_valid  :
                                    (ack_reg == ACK_IDLE)   ?  new_request     :
                                                            warpv_transducer_mem_valid;

    reg [31:0] warpv_wdata_flipped;

    // unused wires tie to zero
    assign transducer_l15_threadid         =  1'b0;
    assign transducer_l15_prefetch         =  1'b0;
    assign transducer_l15_csm_data         =  33'b0;
    assign transducer_l15_data_next_entry  =  64'b0;
    assign transducer_l15_blockstore       =  1'b0;
    assign transducer_l15_blockinitstore   =  1'b0;

    // is this set when something in the l1 gets replaced? pico has no cache
    assign transducer_l15_l1rplway = 2'b0;
    // will pico ever need to invalidate cachelines?
    assign transducer_l15_invalidate_cacheline = 1'b0;

    // logic to check if a request is new
    assign transducer_l15_address  = {{8{warpv_transducer_mem_addr[31]}}, warpv_transducer_mem_addr};
    assign transducer_l15_nc       = warpv_transducer_mem_addr[31] | (transducer_l15_rqtype == `PCX_REQTYPE_AMO);
    assign transducer_l15_data     = {warpv_wdata_flipped, warpv_wdata_flipped};
    
    // set rqtype specific data
    always @ *
    begin
        if (warpv_transducer_mem_valid) begin
            // store or atomic operation 
            if (warpv_transducer_mem_wstrb) begin
                transducer_l15_rqtype = `STORE_RQ;
                // endian wizardry
                warpv_wdata_flipped  =  {warpv_transducer_mem_wdata[7:0], warpv_transducer_mem_wdata[15:8],
                                        warpv_transducer_mem_wdata[23:16], warpv_transducer_mem_wdata[31:24]};

                // NO Atomics at the moment
                // // if it's an atomic operation, modify the request type.
                // // That's it
                // if (pico_mem_amo_op != `L15_AMO_OP_NONE) begin
                //    transducer_l15_rqtype = `PCX_REQTYPE_AMO;
                // end

                case(warpv_transducer_mem_wstrb)
                    4'b1111: begin
                        transducer_l15_size = `MSG_DATA_SIZE_4B;
                    end
                    4'b1100, 4'b0011: begin
                        transducer_l15_size = `MSG_DATA_SIZE_2B;
                    end
                    4'b1000, 4'b0100, 4'b0010, 4'b0001: begin
                        transducer_l15_size = `MSG_DATA_SIZE_1B;
                    end
                    // this should never happen
                    default: begin
                        transducer_l15_size = 0;
                    end
                endcase
            end
            // load operation
            else begin
                warpv_wdata_flipped = 32'b0;
                transducer_l15_rqtype = `LOAD_RQ;
                transducer_l15_size = `MSG_DATA_SIZE_4B;
            end 
        end
        else begin
            warpv_wdata_flipped = 32'b0;
            transducer_l15_rqtype = 5'b0;
            transducer_l15_size = 3'b0;
        end
    end

    // ** ENCODER ** //

    reg [31:0] rdata_part;
    assign transducer_warpv_mem_rdata   =  {rdata_part[7:0], rdata_part[15:8],
                                            rdata_part[23:16], rdata_part[31:24]};
    assign transducer_l15_req_ack       =  l15_transducer_val;
    
    // keep track of whether we have received the wakeup interrupt
    reg int_recv;
    always @ (posedge clk) begin
        if (!rst_n) begin
            warpv_int <= 1'b0;
        end
        else if (int_recv) begin
            warpv_int <= 1'b1;
        end
        else if (warpv_int) begin
            warpv_int <= 1'b0;
        end
    end
        
    always @ * begin
        if (l15_transducer_val) begin
            case(l15_transducer_returntype)
                `LOAD_RET, `CPX_RESTYPE_ATOMIC_RES: begin
                    // load
                    int_recv = 1'b0;
                    transducer_warpv_mem_ready = 1'b1;
                    case(transducer_l15_address[3:2])
                        2'b00: begin
                            rdata_part = l15_transducer_data_0[63:32];
                        end
                        2'b01: begin
                            rdata_part = l15_transducer_data_0[31:0];
                        end
                        2'b10: begin
                            rdata_part = l15_transducer_data_1[63:32];
                        end
                        2'b11: begin
                            rdata_part = l15_transducer_data_1[31:0];
                        end
                        default: begin
                        end
                    endcase 
                end
                `ST_ACK: begin
                    int_recv = 1'b0;
                    transducer_warpv_mem_ready = 1'b1;
                    rdata_part = 32'b0;
                end
                `INT_RET: begin
                    if (l15_transducer_data_0[17:16] == 2'b01) begin
                        int_recv = 1'b1;
                    end
                    else begin
                        int_recv = 1'b0;
                    end
                    transducer_warpv_mem_ready = 1'b0;
                    rdata_part = 32'b0;
                end
                default: begin
                    int_recv = 1'b0;
                    transducer_warpv_mem_ready = 1'b0;
                    rdata_part = 32'b0;
                end
            endcase 
        end
        else begin
            int_recv = 1'b0;
            transducer_warpv_mem_ready = 1'b0;
            rdata_part = 32'b0;
        end
    end
endmodule
