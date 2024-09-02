import {ConfigurationParameters} from './ConfigurationParameters';

export const BEGIN_PROGRAM_LINE = "/* BEGIN PROGRAM"
export const END_PROGRAM_LINE = "END_PROGRAM */"

export function translateParametersToJson(configuratorGlobalSettings, setConfiguratorGlobalSettings, pipelineSettings) {
    if (configuratorGlobalSettings.generalSettings.isa !== 'RISCV' && configuratorGlobalSettings.generalSettings["isaExtensions"] && configuratorGlobalSettings.generalSettings.isaExtensions.length !== 0) {
        const {isaExtensions, ...rest} = configuratorGlobalSettings
        setConfiguratorGlobalSettings(rest)
    }
}

export function translateJsonToM4Macros(json) {
    const {general, pipeline} = json;
    const lines = [];
    //lines.push(`var(M4_STANDARD_CONFIG, ${general.depth}-stage)`);
    lines.push(`var(ISA, ${general.isa})`);
    general.isa !== "MIPSI" && general.isaExtensions?.forEach(extension => {
        lines.push(`var(EXT_${extension}, 1)`);
    });
    if (general.isa !== "MIPSI") {
        if (!general.isaExtensions?.includes("E")) lines.push(`var(EXT_E, 0)`);
        if (!general.isaExtensions?.includes("M")) lines.push(`var(EXT_M, 0)`);
        if (!general.isaExtensions?.includes("F")) lines.push(`var(EXT_F, 0)`);
        if (!general.isaExtensions?.includes("B")) lines.push(`var(EXT_B, 0)`);
    }

    Object.entries(pipeline).forEach(entry => {
        const [jsonKey, value] = entry;
        const foundParameter = ConfigurationParameters.find(p => p.jsonKey === jsonKey);
        if (!foundParameter) throw Error(`Parameter ${jsonKey} not found`);
        if (value && foundParameter.validator && !foundParameter.validator(value, foundParameter)) {
            console.log(`Parameter ${jsonKey} failed validation`);
        } else lines.push(`${foundParameter.macroType}(${foundParameter.verilogName}, ${tlvM4OutputMapper(value, foundParameter.type)})`);
    });
    return lines;
}

function tlvM4OutputMapper(input, type) {
    if (typeof input === 'boolean') return input ? `1'b1` : `1'b0`;
    else if (typeof input === 'number') return input;
    else if (typeof input === 'string') return `${input}`;
}

let customInstructionTemplate = `// Instantiate WARP-V with custom instructions.
   // For example, here we add byte add instructions, defining:
   //   - their encoding (see similar in https://github.com/stevehoover/warp-v_includes/blob/master/risc-v_defs.tlv)
   //   - logic to assign their result value (see similar in https://github.com/stevehoover/warp-v/blob/master/warp-v.tlv).
   m5+warpv_with_custom_instructions(
      ['R, 32, I, 01110, 000, 0000000, BADD'],
      ['I, 32, I, 00110, 000, BADDI'],
      \\TLV
         $badd_rslt[31:0] = {24'b0, /src[1]$reg_value[7:0] + /src[2]$reg_value[7:0]};
         $baddi_rslt[31:0] = {24'b0, /src[1]$reg_value[7:0] + $raw_i_imm[7:0]};
      )`;

export function getTLVCodeForDefinitions(definitions, programName, programText, isa, settings, target_plat) {
    const verilatorConfig = new Set()
    if (settings.formattingSettings.includes("--fmtPackAll")) {
        verilatorConfig.add("/* verilator lint_on WIDTH */ // TODO: Disabling WIDTH to work around what we think is https://github.com/verilator/verilator/issues/1613")
        verilatorConfig.delete("/* verilator lint_off WIDTH */")
    }
    let formattingSettings;
    if (target_plat === '1st-CLaaS') {
        formattingSettings = ['--debugSigs', '--noline'];
    }
    else
    {
        formattingSettings = settings.formattingSettings.filter(formattingArg => formattingArg !== "--fmtNoSource")
    }
    let boilerplate_1st_ClaaS = `\\m5_TLV_version 1d${formattingSettings.length > 0 ? ` ${formattingSettings.join(" ")}` : ""}: tl-x.org
\\m5
   / -----------------------------------------------------------------------------
   / Copyright (c) ${new Date().getFullYear()}, Steven F. Hoover
   /
   / Redistribution and use in source and binary forms, with or without
   / modification, are permitted provided that the following conditions are met:
   /
   /     * Redistributions of source code must retain the above copyright notice,
   /       this list of conditions and the following disclaimer.
   /     * Redistributions in binary form must reproduce the above copyright
   /       notice, this list of conditions and the following disclaimer in the
   /       documentation and/or other materials provided with the distribution.
   /     * The name Steven F. Hoover
   /       may not be used to endorse or promote products derived from this software
   /       without specific prior written permission.
   /
   / THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
   / AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
   / IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
   / DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
   / FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
   / DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
   / SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
   / CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
   / OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   / OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
   / -----------------------------------------------------------------------------

   / For Xilinx: \m5_TLV_version 1d --fmtFlatSignals --bestsv --noline: tl-x.org
   
   use(m5-1.0)

   / Overview:
   / ========
   /
   / This kernel, in it's current form, instantiates a single WARP-V RISC-V CPU. It accepts input traffic
   / (via 1st CLaaS WebSocket) to:
   /   o load instruction memory (IMem)
   /   o reset the CPU (but not the data memory (DMem)) and run the program, which must produce a result value via CSR write
   /
   / API:
   /
   / The following chunks are supported:
   /   o IMEM_WRITE: {..., data, addr, type} =>    / addr is instruction-granular
   /                 {..., data, addr, type}
   /        Write a single IMem instruction word.
   /   o IMEM_READ:  {...,       addr, type} =>
   /                 {..., data, addr, type}
   /        Read a single IMem instruction word.
   /   o RUN:        {...,            type} =>
   /                 {..., CSR_value, type}
   /        Reset the CPU and execute the program from PC=0 until the CLAASRSP CSR is written,
   /        returning the value written to the CSR in a single chunk.
   /
   / Microarchitecture:
   / =================
   /
   / This kernel utilizes the tlv_flow_lib to create a short back-pressured pipeline from kernel input to
   / kernel output. IMEM_READ/WRITE transactions traverse this as follows.
   / Stages:
   /   |kernel_in0@1: kernel input and transit
   /   |kernel_in1@1 / |kernel1@1 (same unless RUN): mux PC and kernel input addr, and rd/wr addr decode
   /   |kernel2@1: array data out and transit
   /   |kernel3@1: transit and encode kernel output data
   / RUN transactions run the program as an m4-+wait_for in |kernel1@1.
   / and the CSR write injects into the kernel output.
   / Kernel interaction with IMem is a backpressured pipeline.

   / --------------------------------------------------------------------
   /
   / A library file for developing FPGA kernels for use with 1st CLaaS
   / (https://github.com/stevehoover/1st-CLaaS)
   /
   / --------------------------------------------------------------------
   / Macros used by WARP-V
   ${definitions ? (settings.customProgramEnabled ? [`var(PROG_NAME, ${programName})`] : []).concat(definitions).join("\n   ") : ""}
   var(XILINX, 0)
   var(flow_lib, https://raw.githubusercontent.com/stevehoover/tlv_flow_lib/23f43b4408a7be1379b5289911b2b19c7e897186)
\\SV
   m4_include_lib(m5_flow_lib/pipeflow_lib.tlv)
   m4_include_lib(m5_flow_lib/arrays.tlv)
   m4_ifelse_block(m5_XILINX, 0, , ['
      m4_include_lib(m5_flow_lib/xilinx_macros.tlv)
   '])
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/warp-v/1b92316df68256f6f0dfa242041a6669456e8e63/warp-v.tlv'])
\\m5
   define_csr(['claasrsp'], 12'hC00, ['32, VAL, 0'], ['32'b0'], ['{32{1'b1}}'], 0)

   var(IMEM_MACRO_NAME, imem)


   // =========
   // Constants
   // =========

   var(IMEM_WRITE_TYPE, 4'h1)
   var(IMEM_READ_TYPE,  4'h2)
   var(RUN_TYPE,        4'h4)

   var(IMEM_FETCH_ALIGN, m5_calc(m5_FETCH_STAGE - 1))

   define_hier(IMEM_ENTRY, 1024)

   define_hier(IMEM, 1024)

   / The 1st CLaaS kernel module definition.
   / TODO: Import from https://github.com/stevehoover/makerchip_examples/blob/master/1st-claas_template_with_macros.tlv
   / This must be defined prior to any \TLV region, so \TLV macro syntax cannot be used - just raw m5.
   fn(kernel_module_def, KernelName, {
      ~eval(['
         module m5_KernelName['']_kernel #(
            parameter integer C_DATA_WIDTH = 512 // Data width of both input and output data
         )
         (
            input wire                       clk,
            input wire                       reset,
            output wire                      in_ready,
            input wire                       in_avail,
            input wire  [C_DATA_WIDTH-1:0]   in_data,
            input wire                       out_ready,
            output wire                      out_avail,
            output wire [C_DATA_WIDTH-1:0]   out_data
         );
      '])
   })

   / Makerchip module definition containing a testbench and instantiation of the custom kernel.
   / This must be defined prior to any \TLV region, so \TLV macro syntax cannot be used - just raw m5.
   fn(makerchip_module_with_random_kernel_tb, kernel_name, ?passed_expr, ?failed_expr, {
      ~if_eq(M4_MAKERCHIP, 1, ['
         ['// Makerchip interfaces with this module, coded in SV.
         ']m5_makerchip_module['
            // Instantiate a 1st CLaaS kernel with random inputs.
            logic [511:0] in_data = {2{RW_rand_vect[255:0]}};
            logic in_avail = ^ RW_rand_vect[7:0];
            logic out_ready = ^ RW_rand_vect[15:8];

            ']m5_kernel_name['_kernel kernel (
                  .*,  // clk, reset, and signals above
                  .in_ready(),  // Ignore blocking (inputs are random anyway).
                  .out_avail(),  // Outputs dangle.
                  .out_data()    //  "
               );
            ']m5_passed_expr['
            ']m5_failed_expr['
         endmodule
         ']
      '])
      ~kernel_module_def(m5_kernel_name)
   })


// The hookup of kernel module SV interface signals to TLV signals following flow library conventions.
\\TLV tlv_wrapper(|_in, @_in, |_out, @_out, /_trans)
   m5_var(trans_ind, m5_if_eq(/_trans, [''], [''], ['   ']))
   // The input interface hookup.
   |_in
      @_in
         $reset = *reset;
         \`BOGUS_USE($reset)
         $avail = *in_avail;
         *in_ready = ! $blocked;
         /trans
      m5_trans_ind   $data[C_DATA_WIDTH-1:0] = *in_data;
   // The output interface hookup.
   |_out
      @_out
         $blocked = ! *out_ready;
         *out_avail = $avail;
         /trans
      m5_trans_ind   *out_data = $data;
      
\\TLV imem()
   // WARP-V configured to use this for IMem, though
   // IMem and read defined elsewhere. This just hooks up $raw.
   |fetch
      @m5_calc(m5_FETCH_STAGE + 1)
         ?$fetch
            // IMem
            $fetch_word[m5_INSTR_RANGE] = /top|imem>>m5_align(2, m5_FETCH_STAGE + 1)$rd_instr;
      
\\SV
   m5_makerchip_module_with_random_kernel_tb(warpv, ['assign passed = cyc_cnt > 20;']) // Provide the name the top module for 1st CLaaS in $3 param
\\m5
   / A hack to reset line alignment to address the fact that the above macro is multi-line. 
\\TLV
   m5+tlv_wrapper(|kernel_in0, @1, |kernel3, @1, /trans)
   
   m5+bp_pipeline(/top, |kernel_in, 0, 1, /trans)
   m5+connect(/top, |kernel_in1, @1, |kernel1, @1, /trans, , || $stalled)
   m5+bp_pipeline(/top, |kernel, 1, 3, /trans)
   
   m5_var(KERNEL_PC_ALIGN, m5_align(3, m5_NEXT_PC_STAGE - 1))      // |kernel_in1@1 trigger CPU.
   m5_var(EXE_KERNEL_ALIGN, m5_align(m5_EXECUTE_STAGE + 1, 1))     // |kernel_in1@1 stop stalling.
   m5_var(soft_reset, /top|kernel_in1>>m5_KERNEL_PC_ALIGN$ResetPc)
   // Block CPU execution if kernel pipeline is blocked.
   m5_set(cpu_blocked, m5_cpu_blocked || /top|kernel1>>m5_align(m5_REG_RD_STAGE, 1)$blocked)
   
   // WARP-V Core
   m5+warpv()

   // ---------------------
   // Stall the BP Pipeline
   
   |kernel_in1
      @1
         // On m5_RUN_TYPE we:
         //   o begin stalling the back-pressured pipeline
         //   o releases CPU reset, starting the CPU from PC==0
         // We run until CSR CLAASRSP is written, then:
         //   o capture CSR CLAASRSP
         //   o begin resetting the CPU
         // Once the EXE stage is again reset, we release the stall.
         
         // One cycle pulse on start.
         $start = $avail && ! $Held && /trans$chunk_type == m5_RUN_TYPE;
         // Stop pulse when CSR is written while running.
         $stop = ! $ResetPc && ! $reset_exe &&
               /top|fetch/instr>>m5_EXE_KERNEL_ALIGN$commit &&
               /top|fetch/instr>>m5_EXE_KERNEL_ALIGN$is_csr_write &&
               /top|fetch/instr>>m5_EXE_KERNEL_ALIGN$is_csr_claasrsp;
         // 1'b0 for m5_RUN_TYPE after $start through $stop.
         $ResetPc <= $reset ? 1'b1 :
                     $start ? 1'b0 :
                     $stop  ? 1'b1 :
                              $RETAIN;
         // 1'b1 for an m5_RUN_TYPE after $start through $accepted.
         $Held <= $reset ? 1'b0 :
                  ($Held || $start) ? ! $accepted :
                           $RETAIN;
         $reset_exe = /top|fetch/instr>>m5_EXE_KERNEL_ALIGN$reset;
         $stalled = $start || ! $ResetPc || ! $reset_exe;
         /trans
            // Grab CLAASRSP CSR when written (cycle after write) and hold.
            $rsp_value[31:0] =
               |kernel_in1$reset  ? 32'b0 :
               |kernel_in1$stop   ? /top|fetch/instr>>m5_calc(m5_EXE_KERNEL_ALIGN - 1)$csr_claasrsp :
                                    $RETAIN;

   |kernel_in0
      @1
         /trans
            $in_data[C_DATA_WIDTH-1:0] = $data[C_DATA_WIDTH-1:0];
   |kernel3
      @1
         /trans
            \`BOGUS_USE($dummy)
            $data[511:0] =  /top|kernel2/trans<>0$out_data;

   // =================
   // BP_Pipeline Logic
   // =================
   
   // Decode $in_data.
   /* verilator lint_off SELRANGE */
   |kernel_in0
      @1
         // Minimal decode logic.
         ?$accepted
            /trans
               $chunk_type[3:0] = $in_data[3:0];
               $addr[m5_IMEM_INDEX_RANGE] = $in_data[(1 * m5_INSTR_CNT) + m5_IMEM_INDEX_MAX:(1 * m5_INSTR_CNT)];
               $instr[m5_INSTR_RANGE] = $in_data[(3 * m5_INSTR_CNT) - 1: 2 * m5_INSTR_CNT];
   
   |imem
      // Mux from |kernel_in1@1 and |fetch@m5_FETCH_STAGE. TODO: No exclusivity check.
      @1
         $accepted = /top|kernel_in1<>0$accepted || /top|fetch/instr>>m5_IMEM_FETCH_ALIGN$fetch;
         ?$accepted
            $addr[m5_IMEM_INDEX_RANGE] = /top|kernel_in1<>0$accepted ? /top|kernel_in1/trans<>0$addr :
                                                                  /top|fetch/instr>>m5_IMEM_FETCH_ALIGN$Pc[m5_IMEM_INDEX_MAX + m5_PC_MIN:m5_PC_MIN];
            $instr[m5_INSTR_RANGE] = /top|kernel_in1/trans<>0$instr;  // (no write for CPU pipeline, so $instr is DONT_CARE)
         $wr_en =  (/top|kernel_in1/trans<>0$chunk_type == m5_IMEM_WRITE_TYPE) && /top|kernel_in1<>0$accepted;
         $rd_en = ((/top|kernel_in1/trans<>0$chunk_type == m5_IMEM_READ_TYPE ) && /top|kernel_in1<>0$accepted) ||
                  /top|fetch/instr>>m5_IMEM_FETCH_ALIGN$fetch;
         
   m5+ifelse(m5_XILINX, 0,
      \\TLV
         m5+array1r1w(/top, /imem_entry, |imem, @1, $wr_en, $addr, $instr[m5_INSTR_RANGE], |imem, @1, $rd_en, $addr, $rd_instr[m5_INSTR_RANGE])
      ,
      \\TLV
         |imem
            @1
               // TODO: I'm not sure about the timing. I'm assuming inputs are a cycle before outputs.
               m5+bram_sdp(m5_INSTR_CNT, $instr, $addr, $wr_en, $rd_instr[m5_INSTR_RANGE], $accepted && $rd_en, $addr)
      )
   // Recirculate rd_data (as the bp_pipeline would naturally have done the cycle before).
   |kernel2
      @1
         // Recirculate rd_data (as the bp_pipeline would naturally have done the cycle before).
         $rd_instr_held[m5_INSTR_RANGE] = /top|imem>>1$rd_en ? /top|imem>>1$rd_instr : $RETAIN;
         ?$accepted
            /trans
               //$rd_instr[m5_INSTR_RANGE] = /top<<1$imem_rd_data_held;
               $rd_instr[m5_INSTR_RANGE] = |kernel2$rd_instr_held;
               $dummy = 0;
   
   // Encode $out_data.
   |kernel2
      @1
         ?$accepted
            /trans
               $out_data[511:0] =
                  ($chunk_type == m5_IMEM_WRITE_TYPE) ? {m5_calc(32 * (16 - 3))'b0, $instr,    m5_calc(32 - m5_IMEM_INDEX_CNT)'b0, $addr, 28'b0, $chunk_type} :
                  ($chunk_type == m5_IMEM_READ_TYPE)  ? {m5_calc(32 * (16 - 3))'b0, $rd_instr, m5_calc(32 - m5_IMEM_INDEX_CNT)'b0, $addr, 28'b0, $chunk_type} :
                  ($chunk_type == m5_RUN_TYPE)?         {m5_calc(512-32-32)'b0, $rsp_value, 28'b0, $chunk_type} :
                                                         512'b0;
   /* verilator lint_on SELRANGE */
   
   
\\SV
   endmodule

    `
    let boilerplate_warpv = `\\m5_TLV_version 1d${formattingSettings.length > 0 ? ` ${formattingSettings.join(" ")}` : ""}: tl-x.org
\\SV
    /*
    Copyright ${new Date().getFullYear()} Redwood EDA, LLC
    
    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    */
\\m5
   use(m5-1.0)

${definitions ? "   " + (settings.customProgramEnabled ? [`var(PROG_NAME, ${programName})`] : []).concat(definitions).join("\n   ") : ""}
\\SV
    // Include WARP-V.
    ${verilatorConfig.size === 0 ? "" : [...verilatorConfig].join("\n   ")}
    m4_include_lib(['${settings.warpVVersion}'])
${settings.customProgramEnabled ? `\\m5\n   TLV_fn(${isa.toLowerCase()}_${programName}_prog, {\n      ~assemble(['
            ${programText.split("\n").join("\n         ")}
        '])\n   })` : ``}
m4+module_def()
\\TLV
   ${settings.customInstructionsEnabled ? customInstructionTemplate : "m5+warpv_top()"}
\\SV
    endmodule
`
    if (target_plat === '1st-CLaaS') {
        return boilerplate_1st_ClaaS
        
    } else {
        return boilerplate_warpv
    }

}
