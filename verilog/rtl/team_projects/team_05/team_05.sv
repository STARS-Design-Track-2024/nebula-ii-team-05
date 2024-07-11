// $Id: $
// File name:   team_05.sv
// Created:     MM/DD/YYYY
// Author:      <Full Name>
// Description: <Module Description>

`default_nettype none

module team_05 (
    // HW
    input logic clk, nrst,
    
    input logic en, //This signal is an enable signal for your chip. Your design should disable if this is low.

    // Logic Analyzer - Grant access to all 128 LA
    input logic [127:0] la_data_in,
    output logic  [127:0] la_data_out,
    input logic [127:0] la_oenb,

    // 34 out of 38 GPIOs (Note: if you need up to 38 GPIO, discuss with a TA)
    input  logic [33:0] gpio_in, // Breakout Board Pins
    output logic [33:0] gpio_out, // Breakout Board Pins
    output logic [33:0] gpio_oeb, // Active Low Output Enable
    
    /*
    * Add other I/O ports that you wish to interface with the
    * Wishbone bus to the management core. For examples you can 
    * add registers that can be written to with the Wishbone bus
    */

    //input from wishbone interconnect
    input logic [31:0] DAT_I,
    input logic        ACK_I,

    //output to wishbone interconnect
    output logic [31:0] ADR_O,
    output logic [31:0] DAT_O,
    output logic [3:0]  SEL_O,
    output logic        WE_O,
    output logic        STB_O,
    output logic        CYC_O
);

    // All outputs must have a value even if not used
    assign la_data_out = 128'b0;
    assign gpio_out = 34'b0; //Inputs, but set low anyways
    assign gpio_oeb = '1;//All 1's inputs
    /*
    * Place code and sub-module instantiations here.
    */

    logic [31:0] CPU_DAT_I;
    logic [31:0] ADR_I;
    logic [3:0]  SEL_I;
    logic        WRITE_I;
    logic        READ_I;

    logic [31:0] CPU_DAT_O;
    logic        BUSY_O;

    assign SEL_I = 4'b1111;

    wishbone_manager wishbone(
        .nRST(nrst),
        .CLK(clk),
        .DAT_I(DAT_I),
        .ACK_I(ACK_I),
        .CPU_DAT_I(CPU_DAT_I),
        .ADR_I(ADR_I),
        .SEL_I(SEL_I),


        // .WRITE_I(WRITE_I),
        // .READ_I(READ_I),

        .WRITE_I(WRITE_I),
        .READ_I(READ_I),


        .ADR_O(ADR_O),
        .DAT_O(DAT_O),
        .SEL_O(SEL_O),
        .WE_O(WE_O),
        .STB_O(STB_O),
        .CYC_O(CYC_O),
        .CPU_DAT_O(CPU_DAT_O),
        .BUSY_O(BUSY_O)
    );

    always @(WRITE_I, READ_I, ADR_I, CPU_DAT_I, SEL_I, CPU_DAT_O, BUSY_O) begin
        $monitor("[Manager Monitor] WRITE_I=%h, READ_I=%h, ADR_I=%h, CPU_DAT_I=%h, SEL_I=%h, CPU_DAT_O=%h, BUSY_O=%h", WRITE_I, READ_I, ADR_I, CPU_DAT_I, SEL_I, CPU_DAT_O, BUSY_O);
    end


    t05_cpu_core core(
        .data_in_BUS(CPU_DAT_O),
        .bus_full(BUSY_O),
        .en(en),
        .clk(clk),
        .rst(~nrst),
        .data_out_BUS(CPU_DAT_I),
        .address_out(ADR_I),
        .data_write(WRITE_I), 
        .mem_read(READ_I)
    );

    
endmodule


















typedef enum logic [2:0] {
    INIT = 0,
    IDLE = 1,
    Read_Request = 2,
    Write_Request = 3,
    Read = 4,
    Write = 5,
    Wait = 6
} state_t;


module t05_cpu_core(
        input logic [31:0] data_in_BUS,
        input logic bus_full, en, //input from memory bus
        input logic clk, rst, //external clock, reset
        output logic [31:0] data_out_BUS, address_out,
        output logic data_write, mem_read
        //, result, reg1, reg2, data_cpu_o, write_address, reg_write, //instruction, result, reg1, reg2 //output data +address to memory bus
        //testing vals from control unit
        //output logic [4:0] rs1, rs2, rd,
       // output logic memToReg_flipflop, instr_wait, reg_write_en, data_write,
     //   output logic [6:0] opcode,
        //output logic [31:0] pc_val, pc_jump,
       // output logic branch_ff, branch, load_pc
);
    always_comb begin
        if(!en) begin
            data_out_BUS = 32'b0;
            address_out = 32'b0;
            data_write = 1'b0;
            mem_read = 1'b0;
        end else begin
            data_out_BUS = data_out_BUS_int;
            address_out = address_out_int;
            data_write = data_write_int;
            mem_read = (next_state == Read) ? 0 : mem_read_int;
        end
    end
    //Instruction Memory -> Control Unit
    logic [31:0] instruction;

    //Control Unit -> ALU
    logic [6:0] funct7, opcode;
    logic [2:0] funct3;
    logic ALU_source; //0 means register, 1 means immediate
    
    //Control Unit -> ALU + Program Counter
    logic [31:0] imm_32;
    logic [31:0] pc_jump;

    //Control Unit -> Registers
    logic [4:0] rs1, rs2, rd;
    
    //Control Unit -> Data Memory
    logic memToReg; //0 means use ALU output, 1 means use data from memory

    //Control Unit -> Program Counter
    logic load_pc; //0 means leave pc as is, 1 means need to load in data

    //Data Memory -> Registers
    logic [31:0] reg_write;

    //Register Input (double check where its coming from)
    logic reg_write_en;

    //Registers -> ALU
    logic [31:0] reg1, reg2;

    //ALU -> Data Memory
    logic [31:0] read_address, write_address, result;

    //ALU -> Program Counter
    logic branch;

    //Memcontrol
    logic [31:0] address_in, data_in_CPU;
    logic data_en, instr_en, memWrite, memRead;

    // outputs
    state_t next_state, state, prev_state; //not currently used, it's just kind of there rn
    logic [31:0] data_out_CPU, data_out_INSTR;
    
    //Program Counter
    logic inc;

    //Data Memory
    logic [31:0] data_read_adr_i, data_write_adr_i, data_bus_i;
    logic data_good, bus_full_CPU;
    logic data_read;//, data_write;
    logic [31:0] data_adr_o, data_bus_o, data_cpu_o;

    //(ALU or external reset) -> Program Counter 
    // logic [31:0] pc_data; //external reset value only now

    //Program Counter -> Instruction Memory
    logic [31:0] pc_val;

    //Memory Manager -> Instruction Memory
    logic [31:0] instruction_i;

    //Instruction Memory -> Memory Manager
    logic instr_fetch;
    logic next_instr_fetch;
    logic [31:0] instruction_adr_o;

    logic [31:0] mem_adr_i;
   // logic mem_read;

    logic branch_ff;
    logic instr_wait, next_instr_wait;
    logic memToReg_flipflop;

    logic [31:0] data_out_BUS_int, address_out_int;
    logic data_write_int, mem_read_int;
    
    assign mem_adr_i = (data_read | data_write_int) ? data_adr_o : instruction_adr_o;

    always_comb begin
        // mem_adr_i = (data_read | data_write_int) ? data_adr_o : instruction_adr_o;
        data_en = data_read | data_write_int;
        mem_read_int = data_read | instr_fetch;
        next_instr_wait = ((((read_address != 32'b0) | (write_address != 32'b0)) & ~data_good));
        // next_instr_wait = (state != IDLE) ? 1'b1 : 1'b0;
    end

    logic [31:0] load_data_flipflop, reg_write_flipflop, instruction_adr_i;

    always_ff @(posedge clk, posedge rst) begin
        if(rst) begin
            memToReg_flipflop <= 1'b0;
            reg_write_flipflop <= '0;
            load_data_flipflop <= '0;
            instr_wait <= 1'b0;
            instruction_adr_i <= '0;
            instruction_i <= '0;
            prev_state <= INIT;
            instr_fetch <= '0;
            disable_pc_reg <= '0;
        end else begin
            memToReg_flipflop <= memToReg;
            reg_write_flipflop <= reg_write;
            load_data_flipflop <= data_cpu_o;
            instr_wait <= next_instr_wait;
            instruction_adr_i <= pc_val;
            instruction_i <= data_out_INSTR;
            prev_state <= state;
            instr_fetch <= next_instr_fetch;
            disable_pc_reg <= disable_pc;
        end
    end

    // input logic [31:0] instruction_adr_i, instruction_i,
    // input logic clk, data_good, rst, instr_wait,
    // input logic [2:0] state,

    logic [31:0] ALU_val2;

    // always_comb begin
    //     if (ALU_source) begin
    //         ALU_val2 = imm_32;
    //     end else begin
    //         ALU_val2 = reg2;
    //     end 
    // end

    assign ALU_val2 = (ALU_source) ? imm_32 : reg2;

    // assign ALU_val2 = 32'b0;

    t05_instruction_memory instr_mem(
        .instruction_adr_i(instruction_adr_i),
        .instruction_i(instruction_i),
        .clk(clk),
        .data_good(!bus_full),
        .rst(rst),
        .state(prev_state),
        .instr_fetch(next_instr_fetch),
        .instruction_adr_o(instruction_adr_o),
        .instruction_o(instruction),
        .instr_wait(instr_wait));
    
    t05_control_unit ctrl(
        .instruction(instruction), 
        // .instruction(32'h3e800093), //addi instr
        // .instruction(32'h00309133), //sll instr
        // .instruction('1),
        .opcode(opcode),
        .funct7(funct7),
        .funct3(funct3),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .imm_32(imm_32), 
        .ALU_source(ALU_source), 
        .memToReg(memToReg),
        .load(load_pc)
        );

        // assign result = imm_32;

    // multiplexer for register input
    
    // always_comb begin
    //     if((opcode != 7'b0100011) && (opcode != 7'b1100011)) begin
    //         if(memToReg_flipflop == 1'b1) reg_write = (load_data_flipflop | data_cpu_o);
    //         else reg_write = result;
    //         reg_write_en = (!instr_fetch) ? 1'b1 : 1'b0;
    //     end else begin
    //         reg_write = 32'b0;
    //         reg_write_en = 1'b0;
    //     end
    // end

    assign reg_write = (memToReg) ? data_cpu_o : result;
    assign reg_write_en = (!instr_fetch) ? 1'b1 : 1'b0; //these need to be updated to accommodate load and store word

    logic [31:0] register_out;
    
    t05_register_file regFile(
        .reg_write(reg_write),
        .clk(clk), 
        .rst(rst), 
        .write(reg_write_en), 
        .rd(rd),
        .rs1(rs1), 
        .rs2(rs2),
        .reg1(reg1),
        .reg2(reg2),
        .register_out(register_out)
        );
 
    logic branch_temp;
    t05_ALU math(
        .ALU_source(ALU_source), 
        .opcode(opcode), 
        .funct3(funct3), 
        .funct7(funct7),
        .reg1(reg1), 
        .val2(ALU_val2),
        .read_address(read_address), 
        .write_address(write_address), 
        .result(result), 
        .branch(branch),
        .pc_data(pc_jump),
        .pc_val(pc_val)
        );

    always_comb begin
        data_good = !bus_full && (state == Wait);
    end

    logic [31:0] val2;
    logic data_access;

    always_comb begin
        // if (ALU_source) val2 = imm_32;
        // else val2 = reg2;
        val2 = reg2;
        branch_ff = (((opcode == 7'b1100011) && ((funct3 == 3'b000 && (reg1 == val2)) | (funct3 == 3'b100 && (reg1 < val2)) | (funct3 == 3'b001 && (reg1 != val2)) | (funct3 == 3'b101 && (reg1 >= val2)))) | (opcode == 7'b1101111) | (opcode == 7'b1100111)) ? 1'b1 : 1'b0;
    end

    //assign branch_ff = 1'b0;

    //sort through mem management inputs/outputs
    t05_data_memory data_mem(
        .data_read_adr_i(read_address),
        .data_write_adr_i(write_address),
        .data_cpu_i(reg2),
        .data_bus_i(data_out_CPU),
        .clk(clk),
        .rst(rst),
        .data_good(!bus_full),
        .state(prev_state),

        // .data_read_adr_i('0),
        // .data_write_adr_i('0),
        // .data_cpu_i('0),
        // .data_bus_i('0),
        // // .clk(clk),
        // // .rst(rst),
        // .data_good('0),
        // .state('0),

        .data_read(data_read),
        .data_write(data_write_int),
        .data_adr_o(data_adr_o),
        .data_bus_o(data_bus_o),
        .data_cpu_o(data_cpu_o));

    //need to figure out these inputs
    t05_memcontrol mem_ctrl(
        .address_in(mem_adr_i), //only works if non-active addresses are set to 0 
        .data_in_CPU(data_bus_o),
        .data_in_BUS(data_in_BUS), //external info
        .data_en(data_en),
        .instr_en(instr_fetch),
        .bus_full(bus_full), //external info
        .memWrite(data_write_int),
        .memRead(mem_read_int),
        .clk(clk),
        .rst(rst),
        .en(en),
        // outputs
        .state(state),
        .next_state(next_state),
        .address_out(address_out_int), //to external output
        .data_out_CPU(data_out_CPU), //to data mem
        .data_out_BUS(data_out_BUS_int), //to external output
        .data_out_INSTR(data_out_INSTR), //to instr mem
        .bus_full_CPU(bus_full_CPU),
        .data_access(data_access)); 

    // assign address_out = mem_adr_i;
    logic [31:0] pc_input;
    logic disable_pc_reg, disable_pc;
    assign disable_pc = instr_wait;
    // assign pc_input = (pc_jump != 32'b0) ? pc_jump : pc_data;
    t05_pc program_count(
        .clk(clk),
        .clr(rst),
        .load(load_pc),
        .inc(data_good & en & !data_access),
        .ALU_out(branch_ff),
        .Disable(disable_pc_reg),
        .data(pc_jump),
        .imm_val(imm_32),   //should be imm_32
        .pc_val(pc_val));

endmodule



module t05_ALU(
    input logic ALU_source,
    input logic [6:0] opcode,
    input logic [2:0] funct3,
    input logic [6:0] funct7,
    input logic [31:0] reg1, val2, pc_val,
    output logic [31:0] read_address, write_address, result, pc_data,
    output logic branch
);        

    always_comb begin
        pc_data = 32'b0;
        read_address = 32'b0;
        write_address = 32'b0; 
        result = 32'b0;
        branch = 1'b0;
        //len = val2-1;
        case(opcode)
            7'b0000011:
                begin
                    read_address = reg1 + val2;
                    // read_address = 32'h33000004;
                end
            7'b0100011:
                begin
                    write_address = reg1 + val2;
                end
            7'b0110011:
                begin
                    case(funct3)
                        3'b000: begin
                            if (funct7==7'b0100000) begin //subtract based on f7
                                result = reg1-val2;
                            end else begin
                                result = reg1+val2;
                            end
                        end 
                        3'b010: begin
                            if (funct7==7'b0100000) begin //subtract based on f7
                                result = reg1-val2;
                            end else begin
                                result = reg1+val2;
                            end
                        end
                        3'b100: result = reg1^val2;
                        3'b110: result = reg1|val2;
                        3'b111: result = reg1&val2;
                        3'b001: result = reg1 << val2[4:0];
                        3'b101: result = reg1 >> val2[4:0];
                        default: begin
                            result=32'b0;
                            read_address=32'b0;
                            write_address=32'b0;
                        end
                    endcase 
                end
            7'b0010011:
                begin
                    case(funct3)
                        3'b000: begin
                            if (funct7==7'b0100000) begin //subtract based on f7
                                result = reg1-val2;
                            end else begin
                                result = reg1+val2;
                            end
                        end 
                        3'b010: begin
                            if (funct7==7'b0100000) begin //subtract based on f7
                                result = reg1-val2;
                            end else begin
                                result = reg1+val2;
                            end
                        end
                        3'b100: result = reg1^val2;
                        3'b110: result = reg1|val2;
                        3'b111: result = reg1&val2;
                        3'b001: result = reg1 << val2[4:0];
                        3'b101: result = reg1 >> val2[4:0];
                        default: begin
                            result=32'b0;
                            read_address=32'b0;
                            write_address=32'b0;
                        end
                    endcase 
                end
            7'b1100011:
                begin
                    case(funct3)
                        3'b000: begin //branch ==
                            if (reg1 == val2) branch=1'b1;
                            else branch=1'b0;
                        end
                        3'b001:  begin //branch !=
                            if (reg1!=val2) branch=1'b1;
                            else branch=1'b0;
                        end
                        3'b100:  begin //branch <
                            if (reg1<val2) branch=1'b1;
                            else branch=1'b0;
                        end
                        3'b101: begin //branch >=
                            if (reg1>=val2) branch=1'b1;
                            else branch=1'b0;
                        end
                        default: branch=1'b0;
                    endcase 
                end
            7'b1101111:
              begin
                branch = 1'b1;
                result = pc_val + 32'd4;
              end
            7'b1100111:
              begin 
                branch=1'b1;//jump and link, jalr
                result = pc_val + 32'd4;
                pc_data = reg1 + val2;
              end
            7'b0110111: result = {val2[19:0],12'b0}; // lui
            default: 
                begin
                    read_address = 32'b0; 
                    write_address = 32'b0; 
                    result = 32'b0;
                    branch = 1'b0;
                end 
        endcase
    end
endmodule


module t05_control_unit(
    input logic [31:0] instruction,
    output logic [6:0] opcode, funct7,
    output logic [2:0] funct3,
    output logic [4:0] rs1, rs2, rd,
    output logic [31:0] imm_32,
    output logic ALU_source, //0 means register, 1 means immediate
    output logic memToReg, //0 means use ALU output, 1 means use data from memory
    output logic load //0 means leave pc as is, 1 means need to load in data
);

    always_comb begin
        opcode = instruction[6:0];
        rd = 5'b0;
        imm_32 = 32'h00000000;
        rs1 = 5'b0;
        rs2 = 5'b0;
        funct3 = 3'b0;
        funct7 = 7'b0;
        ALU_source = 1'b0;
        memToReg = 1'b0;
        load = 1'b0;
        case(instruction[6:0])
            7'b0110011: //only r type instruction
                begin
                    funct3 = instruction[14:12];
                    funct7 = instruction[31:25];
                    rd = instruction[11:7];
                    rs1 = instruction[19:15];
                    rs2 = instruction[24:20];
                    imm_32 = 32'b0;
                    ALU_source = 1'b0;
                    memToReg = 1'b0;
                    load = 1'b0;
                end
            7'b0010011: //i type instructions
                begin
                    funct3 = instruction[14:12];
                    rd = instruction[11:7];
                    rs1 = instruction[19:15];
                    imm_32 = {{20{instruction[31]}}, instruction[31:20]};
                    funct7 = 7'b0;
                    rs2 = 5'b0;
                    ALU_source = 1'b1;
                    memToReg = 1'b0;
                    load = 1'b0;
                end
            7'b0000011:
                begin
                    funct3 = instruction[14:12];
                    rd = instruction[11:7];
                    rs1 = instruction[19:15];
                    imm_32 = {{20{instruction[31]}}, instruction[31:20]};
                    funct7 = 7'b0;
                    rs2 = 5'b0;
                    ALU_source = 1'b1;
                    memToReg = 1'b1;
                    load = 1'b0;
                end
            7'b1100111:
                begin
                    funct3 = instruction[14:12];
                    rd = instruction[11:7];
                    rs1 = instruction[19:15];
                    imm_32 = {{20{instruction[31]}}, instruction[31:20]};
                    funct7 = 7'b0;
                    rs2 = 5'b0;
                    ALU_source = 1'b1;
                    memToReg = 1'b0;
                    load = 1'b1;
                end
            7'b0100011: //s type instructions
                begin
                    funct3 = instruction[14:12];
                    rs1 = instruction[19:15];
                    rs2 = instruction[24:20];
                    imm_32 = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
                    funct7 = 7'b0;
                    rd = 5'b0;
                    ALU_source = 1'b1;
                    memToReg = 1'b0;
                    load = 1'b0;
                end
            7'b1100011: //b type instruction
                begin
                    funct3 = instruction[14:12];
                    rs1 = instruction[19:15];
                    rs2 = instruction[24:20];
                    // imm_32 = {{20{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8]};
                    imm_32 = ({{20{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8]} << 1);
                    funct7 = 7'b0;
                    rd = 5'b0;
                    ALU_source = 1'b1;
                    memToReg = 1'b0;
                    load = 1'b0;
                end
            7'b1101111: //j type instruction
                begin
                    rd = instruction[11:7] ;
                    imm_32 = ({{12{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21]} << 1) - 32'd4;
                    rs1 = 5'b0;
                    rs2 = 5'b0;
                    funct3 = 3'b0;
                    funct7 = 7'b0;
                    ALU_source = 1'b1;
                    memToReg = 1'b0;
                    load = 1'b0;
                end
            7'b0110111: //u type instruction
                begin
                    rd = instruction[11:7];
                    imm_32 = {{12{instruction[31]}}, instruction[31:12]};
                    rs1 = 5'b0;
                    rs2 = 5'b0;
                    funct3 = 3'b0;
                    funct7 = 7'b0;
                    ALU_source = 1'b1;
                    memToReg = 1'b0;
                    load = 1'b0;
                end
            default:
                begin
                    rd = 5'b0;
                    imm_32 = 32'b0;
                    rs1 = 5'b0;
                    rs2 = 5'b0;
                    funct3 = 3'b0;
                    funct7 = 7'b0;
                    ALU_source = 1'b0;
                    memToReg = 1'b0;
                    load = 1'b0;
                end
        endcase
    end
endmodule

module t05_data_memory(
    input logic [31:0] data_read_adr_i, data_write_adr_i, data_bus_i, data_cpu_i,
    input logic clk, data_good, rst,
    input logic [2:0] state,
    output logic data_read, data_write,
    output logic [31:0] data_adr_o, data_bus_o, data_cpu_o
);

    logic next_read, next_write;
    logic [31:0] stored_read_data, stored_write_data, stored_data_adr;
    logic [31:0] data_read_adr_reg, data_write_adr_reg;
    logic [31:0] data_bus_i_reg, data_cpu_i_reg;

    always_comb begin
        next_read = 1'b0;
        next_write = 1'b0;
        stored_read_data = 32'b0;
        stored_write_data = 32'b0;
        stored_data_adr = '0;
        // data_cpu_o = data_bus_i;
        // data_bus_o = data_cpu_i;

        if(state == Wait) begin
            next_read = '0;
            next_write = '0;
            stored_data_adr = '0;
            stored_read_data = '0;
            stored_write_data = '0;
        end else if (data_read_adr_reg != 32'b0 & state == IDLE) begin
            next_read = '1;
            next_write = '0;
            stored_data_adr = data_read_adr_reg;
            stored_read_data = '0;
            stored_write_data = '0;
        end else if(data_write_adr_reg != 32'b0 & state == IDLE) begin
            next_read = '0;
            next_write = '1;
            stored_data_adr = data_write_adr_reg;
            stored_read_data = '0;
            stored_write_data = '0;
        end else if(data_read_adr_reg != 32'b0 & state == Read) begin
            next_read = '0;
            next_write = '0;
            stored_data_adr = '0;
            stored_read_data = data_bus_i_reg;
            stored_write_data = '0;
        end else if(data_write_adr_reg != 32'b0 & state == Write) begin
            next_read = '0;
            next_write = '0;
            stored_data_adr = '0;
            stored_write_data = data_cpu_i_reg;
            stored_read_data = '0;
        end

        // if((~(data_read_adr_i == 32'b0))) begin
        //     if(data_good & data_read) begin
        //         next_read = 1'b0;
        //     end else begin
        //         next_read = 1'b1;
        //     end
        // end else if(~(data_write_adr_i == 32'b0)) begin
        //     if(data_good & data_write) begin
        //         next_write = 1'b0;
        //     end else begin
        //         next_write = 1'b1;
        //     end
        // end
    end

    always_ff @(posedge clk, posedge rst) begin
        if(rst) begin
            data_adr_o <= 32'b0;
            data_bus_o <= 32'b0;
            data_cpu_o <= 32'b0;
            data_read <= 1'b0;
            data_write <= 1'b0;
            data_read_adr_reg <= '0;
            data_write_adr_reg <= '0;
            data_bus_i_reg <= '0;
            data_cpu_i_reg <= '0;
        end else begin
            data_read <= next_read;
            data_write <= next_write;
            data_adr_o <= stored_data_adr;
            data_read_adr_reg <= data_read_adr_i;
            data_write_adr_reg <= data_write_adr_i;
            data_cpu_o <= stored_read_data;
            data_bus_o <= stored_write_data;
            data_bus_i_reg <= data_bus_i;
            data_cpu_i_reg <= data_cpu_i;

            // data_adr_o <= 32'b0;
            // data_bus_o <= 32'b0;
            // data_cpu_o <= 32'b0;
            // data_read <= 1'b0;
            // data_write <= 1'b0;
            // data_read_adr_reg <= '0;
            // data_write_adr_reg <= '0;
            // data_bus_i_reg <= '0;
            // data_cpu_i_reg <= '0;
        end
    end
endmodule

module t05_instruction_memory(
    input logic [31:0] instruction_adr_i, instruction_i,
    input logic clk, data_good, rst, instr_wait,
    input logic [2:0] state,
    output logic instr_fetch,
    output logic [31:0] instruction_adr_o, instruction_o
);

    logic next_fetch, prev_fetch, prev_d_good;
    logic [31:0] stored_instr, stored_instr_adr;


    always_comb begin
        next_fetch = 1'b0;
        stored_instr_adr = '0;
        stored_instr = '0;

        if((state == Wait)) begin //data_good & instr_fetch
            next_fetch = 1'b0;
            stored_instr_adr = instruction_adr_i;
            stored_instr = '0;
        end else if((state == Read)) begin
            next_fetch = 1'b0;
            stored_instr_adr = instruction_adr_i;
            stored_instr = instruction_i;
            // stored_instr = 32'h3E800093;
        end else if(!instr_wait) begin
            next_fetch = 1'b1;
            stored_instr_adr = instruction_adr_i;
            stored_instr = '0;  ////////////32'b0 <-
        end else begin
            // next_fetch = 1'b0;
            // stored_instr_adr = instruction_adr_i;
            // stored_instr = instruction_o;
        end
        if(instr_wait) begin
            instruction_adr_o = instruction_adr_o;
        end else begin
            instruction_adr_o = instruction_adr_i;
        end
    end

    always_ff @(posedge clk, posedge rst) begin
        if(rst) begin
            // instruction_adr_o <= 32'b0;
            instruction_o <= 32'b0;
            instr_fetch <= 1'b0;
            prev_d_good <= 0;
            prev_fetch <= 0;
        end else if(instr_wait) begin
            // instruction_adr_o <= instruction_adr_o;
            instruction_o <= instruction_o;
            instr_fetch <= 1'b0;
            prev_fetch <= instr_fetch;
            prev_d_good <= data_good;
        end else begin
            // instruction_adr_o <= stored_instr_adr;
            instruction_o <= stored_instr;
            instr_fetch <= next_fetch;
            prev_fetch <= instr_fetch;
            prev_d_good <= data_good;
        end
    end
endmodule

module t05_memcontrol(
    // inputs
    // data_in_BUS and bus_full are the only inputs from the bus manager, so we need to figure those out on wednesday
    input logic [31:0] address_in, data_in_CPU, data_in_BUS,
    input logic data_en, instr_en, bus_full, memWrite, memRead,
    input logic clk, rst, en,
    // outputs
    output logic [2:0] next_state, state,
    output logic bus_full_CPU, data_access,
    output logic [31:0] address_out, data_out_CPU, data_out_BUS, data_out_INSTR
);

    always @ (memRead, address_in, data_in_BUS) begin
        $display("[Read monitor] time=%0t, memRead=%h, address_in=%h, data_in_BUS=%h", $time, memRead, address_in, data_in_BUS);
    end
    always @ (memWrite, address_in, data_in_CPU) begin
        $display("[Write monitor] time=%0t, memWrite=%h, address_in=%h, data_in_CPU=%h", $time, memWrite, address_in, data_in_CPU);
    end

    always @ (address_in) begin
        if (address_in == 33000024) #1 $stop;
    end

    logic [2:0] prev_state;
    logic next_next_fetch;
    logic next_instr;
    logic next_data_read;
    logic next_next_data_read;
    logic next_data_access;

    always_ff @(posedge clk, posedge rst) begin : startFSM
        if (rst) begin
            state <= INIT;
            next_next_fetch <= 0;
            next_next_data_read <= 0;
            data_access <= 0;
        end else begin
            state <= next_state;
            next_next_fetch <= next_instr;
            next_next_data_read <= next_data_read;
            data_access <= next_data_access;
        end
    end

    always_comb begin : changeState
        bus_full_CPU = bus_full;
        // garbage values for testing
        address_out = address_in;
        data_out_BUS = 32'h0;
        data_out_CPU = 32'h0;
        data_out_INSTR = 32'h0;
        next_state = state;
        prev_state = state;
        next_instr = next_next_fetch;
        next_data_read = next_next_data_read;
        next_data_access = data_access;

        case(state)
            INIT: begin 
                if (!rst & en) next_state = IDLE;
                else next_state = INIT;
            end
            
            IDLE: begin
                if (memRead) begin
                    next_state = Read_Request;
                    prev_state = Read_Request;
                    next_data_access = 1'b1;
                end else if (memWrite) begin
                    next_state = Write_Request;
                    prev_state = Write_Request;
                    next_data_access = 1'b1;
                end else begin
                    prev_state = IDLE;
                    next_state = IDLE;
                    address_out = 32'b0;
                end
            end
            
            Read_Request: begin 
                if (bus_full) begin
                    next_state = Wait;
                    prev_state = Read_Request;
                end else begin
                    next_state = Wait;
                    prev_state = Read_Request;
                end
                if(data_en) begin
                    next_data_read = 1'b1;
                end else begin
                    next_instr = 1'b1;
                    next_data_access = 1'b0;
                end
            end
            
            Write_Request: begin 
                if (bus_full) begin
                    next_state = Write;
                end else begin
                    next_state = Write;
                end
            end

            Read: begin 
                address_out = address_in;
                data_out_BUS = 32'b0;
                if (next_next_data_read) begin
                    data_out_CPU = data_in_BUS;
                    data_out_INSTR = 32'b0; // going to MUX
                end
                else if (next_next_fetch) begin
                    data_out_CPU = 32'b0;
                    data_out_INSTR = data_in_BUS; // going to CU
                end
                next_state = IDLE;
                next_instr = 1'b0;
                next_data_read = 1'b0;
                next_data_access = 1'b0;
            end
            
            Write: begin 
                address_out = address_in;
                data_out_BUS = data_in_CPU;
                data_out_INSTR = 32'b0;
                data_out_CPU = 32'b0;
                next_state = IDLE;
                next_data_access = 1'b0;
            end

            Wait: begin
                if (!bus_full) begin
                    if (memRead) begin
                        next_state = Read;
                    end else if (memWrite) begin
                        next_state = Write;
                    end else begin
                        next_state = Read;
                    end
                end else begin
                    next_state = Wait;
                    if(memRead) begin
                        prev_state = Read_Request;
                    end else if(memWrite) begin
                        prev_state = Write_Request;
                    end
                end
            end

            default: next_state = IDLE;
            
        endcase
    end
endmodule

module t05_pc(
    input logic clk, clr, load, inc, Disable, ALU_out,
    input logic [31:0] data, imm_val,
    output logic [31:0] pc_val 
);
    logic [31:0] next_line_ad;
    logic [31:0] jump_ad;
    logic [31:0] next_pc;
    logic branch_choice;


    //registering the imm_val for pranav dream
    logic [31:0] imm_val_reg;
    logic        ALU_out_reg;


    // Register 
    always_ff @(posedge clk, posedge clr) begin

        if (clr) begin
            pc_val <= 32'h33000000;

            imm_val_reg <= '0;
            ALU_out_reg <= '0;
        end

        else begin
            pc_val <= next_pc;

            imm_val_reg <= imm_val;
            ALU_out_reg <= ALU_out;
        end
    end


   always_comb begin
       next_pc = pc_val;
       next_line_ad = pc_val + 32'd4;	// Calculate next line address  
    //    jump_ad = pc_val + imm_val;    // Calculate jump address (jump and link)
        jump_ad = pc_val;
	
        // Mux choice between next line address and jump address
        if (Disable) begin 
		    next_pc = pc_val; 
	    end

        else if (load) begin
            next_pc = data;
        end
            
        else if (ALU_out_reg) begin
		    next_pc = pc_val + imm_val_reg;
	    end
	
        else if (inc) begin
            next_pc= pc_val + 32'd4;
        end
   end       
endmodule

module t05_register_file (
    input logic [31:0] reg_write, 
    input logic [4:0] rd, rs1, rs2, 
    input logic clk, rst, write,
    output logic [31:0] reg1, reg2,
    output logic [31:0] register_out//array????
);
    logic [31:0] register [0:31];
    //reg[31:0][31:0] next_register; 

    logic [31:0] write_data;

    //assign register = '{default:'0};

    always_comb begin
        write_data = reg_write;
        if (write) begin
            if (rd != 0) begin
                write_data = reg_write;
            end else begin
                write_data = 32'b0;
            end
        end
        reg1 = register[rs1];
        reg2 = register[rs2];
        register_out = register[5'd2];
    end

    always_ff @ (posedge clk, posedge rst) begin //reset pos or neg or no reset
        if (rst) begin
            register[0] <= 32'b0;
            register[1] <= 32'b0;
            register[2] <= 32'b0;
            register[3] <= 32'b0;
            register[4] <= 32'b0;
            register[5] <= 32'b0;
            register[6] <= 32'b0;
            register[7] <= 32'b0;
            register[8] <= 32'b0;
            register[9] <= 32'b0;
            register[10] <= 32'b0;
            register[11] <= 32'b0;
            register[12] <= 32'b0;
            register[13] <= 32'b0;
            register[14] <= 32'b0;
            register[15] <= 32'b0;
            register[16] <= 32'b0;
            register[17] <= 32'b0;
            register[18] <= 32'b0;
            register[19] <= 32'b0;
            register[20] <= 32'b0;
            register[21] <= 32'b0;
            register[22] <= 32'b0;
            register[23] <= 32'b0;
            register[24] <= 32'b0;
            register[25] <= 32'b0;
            register[26] <= 32'b0;
            register[27] <= 32'b0;
            register[28] <= 32'b0;
            register[29] <= 32'b0;
            register[30] <= 32'b0;
            register[31] <= 32'b0;


        end
        else begin
            //register <= next_register;
            if(write) begin
                register[rd] <= write_data;
            end
        end
    end
endmodule








































module wishbone_manager(
    //clock and reset of course
    input logic nRST, CLK,
    
    //input from wishbone interconnect
    input logic [31:0] DAT_I,
    input logic        ACK_I,

    //input from user design
    input logic [31:0] CPU_DAT_I,
    input logic [31:0] ADR_I,
    input logic [3:0]  SEL_I,
    input logic        WRITE_I,
    input logic        READ_I,

    //output to wishbone interconnect
    output logic [31:0] ADR_O,
    output logic [31:0] DAT_O,
    output logic [3:0]  SEL_O,
    output logic        WE_O,
    output logic        STB_O,
    output logic        CYC_O,

    //output to user design
    output logic [31:0] CPU_DAT_O,
    output logic        BUSY_O
);

typedef enum logic[1:0] {
    W_IDLE,
    WRITE,
    READ
 } state;


state curr_state;
state next_state;

logic [31:0] next_ADR_O;
logic [31:0] next_DAT_O;
logic [3:0]  next_SEL_O;
logic        next_WE_O;
logic        next_STB_O;
logic        next_CYC_O;

logic [31:0] next_CPU_DAT_O;
logic        next_BUSY_O;


always_ff @(posedge CLK, negedge nRST) begin : All_ffs
    if(~nRST) begin
        //state machine
        curr_state <= W_IDLE;

        //registers for user project outputs
        CPU_DAT_O <= '0;
        BUSY_O    <= '0;

        //signals going to interconnect
        ADR_O     <= '0;
        DAT_O     <= '0;
        SEL_O     <= '0;
        WE_O      <= '0;
        STB_O     <= '0;
        CYC_O     <= '0;
    end
    else begin
        curr_state <= next_state;

        CPU_DAT_O  <= next_CPU_DAT_O;
        BUSY_O     <= next_BUSY_O;

        ADR_O      <= next_ADR_O;
        DAT_O      <= next_DAT_O;
        SEL_O      <= next_SEL_O;
        WE_O       <= next_WE_O;
        STB_O      <= next_STB_O;
        CYC_O      <= next_CYC_O;
    end
end


always_comb begin
    next_state = curr_state;

    next_ADR_O  = ADR_O;
    next_DAT_O  = DAT_O;
    next_SEL_O  = SEL_O;
    next_WE_O   = WE_O;
    next_STB_O  = STB_O;
    next_CYC_O  = CYC_O;
    next_BUSY_O = BUSY_O;    
    
    case(curr_state)
        W_IDLE: begin
            if(WRITE_I && !READ_I) begin
                next_BUSY_O = 1'b1;
                next_state  = WRITE;
            end
            if(!WRITE_I && READ_I) begin
                next_BUSY_O = 1'b1;
                next_state  = READ;
            end
        end     
        WRITE: begin
            next_ADR_O  = ADR_I;
            next_DAT_O  = CPU_DAT_I;
            next_SEL_O  = SEL_I;
            next_WE_O   = 1'b1;
            next_STB_O  = 1'b1;
            next_CYC_O  = 1'b1;
            next_BUSY_O = 1'b1;

            if(ACK_I) begin
                next_state = W_IDLE;

                next_ADR_O  = '0;
                next_DAT_O  = '0;
                next_SEL_O  = '0;
                next_WE_O   = '0;
                next_STB_O  = '0;
                next_CYC_O  = '0;
                next_BUSY_O = '0;
            end
        end
        READ: begin
            next_ADR_O  = ADR_I;
            next_DAT_O  = '0;
            next_SEL_O  = SEL_I;
            next_WE_O   = '0;
            next_STB_O  = 1'b1;
            next_CYC_O  = 1'b1;
            next_BUSY_O = 1'b1;

            if(ACK_I) begin
                next_state = W_IDLE;

                next_ADR_O  = '0;
                next_DAT_O  = '0;
                next_SEL_O  = '0;
                next_WE_O   = '0;
                next_STB_O  = '0;
                next_CYC_O  = '0;
                next_BUSY_O = '0;
            end
        end
        default: next_state = curr_state;
    endcase
end



logic prev_BUSY_O;
logic BUSY_O_edge;

always_ff @(posedge CLK, negedge nRST) begin : BUSY_O_edge_detector
    if(!nRST) begin
        prev_BUSY_O <= '0;
    end
    else begin
        prev_BUSY_O <= BUSY_O;
    end
end

//detects the falling edge of BUSY_O to indicate the end of a transaction
assign BUSY_O_edge = (!BUSY_O && prev_BUSY_O);

//this always comb is for the logic to latch the data input on a read transaction
always_comb begin
    next_CPU_DAT_O = 32'hBAD1BAD1;

    if((curr_state == READ) && ACK_I) begin
        next_CPU_DAT_O = DAT_I;
    end
    else if(BUSY_O_edge) begin
        next_CPU_DAT_O = CPU_DAT_O;
    end
end
endmodule



