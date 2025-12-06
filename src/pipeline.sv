`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION PIPELINE
// > 5-stage pipeline: Fetch, Decode, Execute, Memory, Writeback
// > Handles hazard detection and forwarding
// > Supports stalls for memory operations
// > Pipeline registers between each stage
module pipeline #(
    parameter DATA_BITS = 16,
    parameter ADDR_BITS = 8,
    parameter INSTR_BITS = 16,
    parameter REG_BITS = 4
) (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire flush,                      // Flush pipeline (branch misprediction)

    // Fetch stage inputs
    input wire [INSTR_BITS-1:0] fetched_instruction,
    input wire fetch_valid,

    // Decode stage outputs (to decoder)
    output reg [INSTR_BITS-1:0] decode_instruction,
    output reg decode_valid,

    // Execute stage inputs (from ALU/FMA)
    input wire [DATA_BITS-1:0] execute_result,
    input wire execute_ready,
    input wire [REG_BITS-1:0] execute_rd,

    // Memory stage inputs (from LSU)
    input wire [DATA_BITS-1:0] memory_data,
    input wire memory_ready,
    input wire memory_is_load,

    // Writeback outputs
    output reg [DATA_BITS-1:0] writeback_data,
    output reg [REG_BITS-1:0] writeback_rd,
    output reg writeback_enable,

    // Hazard outputs
    output reg pipeline_stall,
    output reg [DATA_BITS-1:0] forward_data,
    output reg [REG_BITS-1:0] forward_rd,
    output reg forward_valid
);
    // Pipeline stages
    localparam FETCH    = 3'd0;
    localparam DECODE   = 3'd1;
    localparam EXECUTE  = 3'd2;
    localparam MEMORY   = 3'd3;
    localparam WRITEBACK = 3'd4;

    // IF/ID Pipeline Register
    reg [INSTR_BITS-1:0] if_id_instruction;
    reg if_id_valid;

    // ID/EX Pipeline Register
    reg [INSTR_BITS-1:0] id_ex_instruction;
    reg [REG_BITS-1:0] id_ex_rd;
    reg [REG_BITS-1:0] id_ex_rs;
    reg [REG_BITS-1:0] id_ex_rt;
    reg id_ex_valid;
    reg id_ex_is_load;
    reg id_ex_is_store;
    reg id_ex_is_alu;
    reg id_ex_is_fma;

    // EX/MEM Pipeline Register
    reg [DATA_BITS-1:0] ex_mem_result;
    reg [REG_BITS-1:0] ex_mem_rd;
    reg ex_mem_valid;
    reg ex_mem_is_load;
    reg ex_mem_writes_reg;

    // MEM/WB Pipeline Register
    reg [DATA_BITS-1:0] mem_wb_data;
    reg [REG_BITS-1:0] mem_wb_rd;
    reg mem_wb_valid;
    reg mem_wb_writes_reg;

    // Decode instruction fields (for hazard detection)
    wire [3:0] decode_opcode = if_id_instruction[15:12];
    wire [REG_BITS-1:0] decode_rd_field = if_id_instruction[11:8];
    wire [REG_BITS-1:0] decode_rs_field = if_id_instruction[7:4];
    wire [REG_BITS-1:0] decode_rt_field = if_id_instruction[3:0];

    // Opcode definitions for hazard detection
    localparam OP_NOP   = 4'b0000;
    localparam OP_BRnzp = 4'b0001;
    localparam OP_CMP   = 4'b0010;
    localparam OP_ADD   = 4'b0011;
    localparam OP_SUB   = 4'b0100;
    localparam OP_MUL   = 4'b0101;
    localparam OP_DIV   = 4'b0110;
    localparam OP_LDR   = 4'b0111;
    localparam OP_STR   = 4'b1000;
    localparam OP_CONST = 4'b1001;
    localparam OP_FMA   = 4'b1010;
    localparam OP_RET   = 4'b1111;

    // Determine instruction types
    wire decode_is_load = (decode_opcode == OP_LDR);
    wire decode_is_store = (decode_opcode == OP_STR);
    wire decode_is_alu = (decode_opcode == OP_ADD) || (decode_opcode == OP_SUB) ||
                         (decode_opcode == OP_MUL) || (decode_opcode == OP_DIV) ||
                         (decode_opcode == OP_CMP);
    wire decode_is_fma = (decode_opcode == OP_FMA);
    wire decode_writes_reg = decode_is_load || decode_is_alu || decode_is_fma ||
                            (decode_opcode == OP_CONST);

    // RAW Hazard Detection
    // Check if current instruction reads from a register that's being written
    wire raw_hazard_ex = id_ex_valid && id_ex_writes_reg &&
                        ((id_ex_rd == decode_rs_field) || (id_ex_rd == decode_rt_field));
    wire raw_hazard_mem = ex_mem_valid && ex_mem_writes_reg &&
                         ((ex_mem_rd == decode_rs_field) || (ex_mem_rd == decode_rt_field));
    
    // Load-use hazard (need to stall one cycle)
    wire load_use_hazard = id_ex_valid && id_ex_is_load &&
                          ((id_ex_rd == decode_rs_field) || (id_ex_rd == decode_rt_field));

    // Register for tracking writes
    reg id_ex_writes_reg;

    // Forwarding logic
    always @(*) begin
        forward_valid = 1'b0;
        forward_data = {DATA_BITS{1'b0}};
        forward_rd = {REG_BITS{1'b0}};

        // Forward from MEM stage (highest priority for most recent)
        if (ex_mem_valid && ex_mem_writes_reg) begin
            forward_valid = 1'b1;
            forward_data = ex_mem_result;
            forward_rd = ex_mem_rd;
        end
        // Forward from WB stage
        else if (mem_wb_valid && mem_wb_writes_reg) begin
            forward_valid = 1'b1;
            forward_data = mem_wb_data;
            forward_rd = mem_wb_rd;
        end
    end

    // Stall logic
    always @(*) begin
        pipeline_stall = 1'b0;
        
        // Stall for load-use hazard
        if (load_use_hazard && if_id_valid) begin
            pipeline_stall = 1'b1;
        end
        
        // Stall waiting for memory
        if (ex_mem_valid && ex_mem_is_load && !memory_ready) begin
            pipeline_stall = 1'b1;
        end
        
        // Stall waiting for execute
        if (id_ex_valid && (id_ex_is_alu || id_ex_is_fma) && !execute_ready) begin
            pipeline_stall = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            // Reset all pipeline registers
            if_id_instruction <= {INSTR_BITS{1'b0}};
            if_id_valid <= 1'b0;

            id_ex_instruction <= {INSTR_BITS{1'b0}};
            id_ex_rd <= {REG_BITS{1'b0}};
            id_ex_rs <= {REG_BITS{1'b0}};
            id_ex_rt <= {REG_BITS{1'b0}};
            id_ex_valid <= 1'b0;
            id_ex_is_load <= 1'b0;
            id_ex_is_store <= 1'b0;
            id_ex_is_alu <= 1'b0;
            id_ex_is_fma <= 1'b0;
            id_ex_writes_reg <= 1'b0;

            ex_mem_result <= {DATA_BITS{1'b0}};
            ex_mem_rd <= {REG_BITS{1'b0}};
            ex_mem_valid <= 1'b0;
            ex_mem_is_load <= 1'b0;
            ex_mem_writes_reg <= 1'b0;

            mem_wb_data <= {DATA_BITS{1'b0}};
            mem_wb_rd <= {REG_BITS{1'b0}};
            mem_wb_valid <= 1'b0;
            mem_wb_writes_reg <= 1'b0;

            decode_instruction <= {INSTR_BITS{1'b0}};
            decode_valid <= 1'b0;
            writeback_data <= {DATA_BITS{1'b0}};
            writeback_rd <= {REG_BITS{1'b0}};
            writeback_enable <= 1'b0;
        end
        else if (flush) begin
            // Flush pipeline on branch misprediction
            if_id_valid <= 1'b0;
            id_ex_valid <= 1'b0;
            ex_mem_valid <= 1'b0;
            decode_valid <= 1'b0;
        end
        else if (enable && !pipeline_stall) begin
            // Stage 1: IF -> IF/ID
            if_id_instruction <= fetched_instruction;
            if_id_valid <= fetch_valid;

            // Stage 2: IF/ID -> ID/EX
            decode_instruction <= if_id_instruction;
            decode_valid <= if_id_valid;
            
            id_ex_instruction <= if_id_instruction;
            id_ex_rd <= decode_rd_field;
            id_ex_rs <= decode_rs_field;
            id_ex_rt <= decode_rt_field;
            id_ex_valid <= if_id_valid;
            id_ex_is_load <= decode_is_load;
            id_ex_is_store <= decode_is_store;
            id_ex_is_alu <= decode_is_alu;
            id_ex_is_fma <= decode_is_fma;
            id_ex_writes_reg <= decode_writes_reg;

            // Stage 3: ID/EX -> EX/MEM
            ex_mem_result <= execute_result;
            ex_mem_rd <= id_ex_rd;
            ex_mem_valid <= id_ex_valid && execute_ready;
            ex_mem_is_load <= id_ex_is_load;
            ex_mem_writes_reg <= id_ex_writes_reg;

            // Stage 4: EX/MEM -> MEM/WB
            if (ex_mem_is_load && memory_ready) begin
                mem_wb_data <= memory_data;
            end else begin
                mem_wb_data <= ex_mem_result;
            end
            mem_wb_rd <= ex_mem_rd;
            mem_wb_valid <= ex_mem_valid;
            mem_wb_writes_reg <= ex_mem_writes_reg;

            // Stage 5: MEM/WB -> Writeback
            writeback_data <= mem_wb_data;
            writeback_rd <= mem_wb_rd;
            writeback_enable <= mem_wb_valid && mem_wb_writes_reg;
        end
        else if (enable && pipeline_stall) begin
            // Insert bubble on stall
            if (load_use_hazard) begin
                // Insert NOP in EX stage
                id_ex_valid <= 1'b0;
            end
        end
    end

    // Pipeline visualization (for debugging)
    wire [4:0] stage_valid = {if_id_valid, id_ex_valid, ex_mem_valid, mem_wb_valid, writeback_enable};
endmodule

