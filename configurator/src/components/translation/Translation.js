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
    //lines.push(`m4_def(M4_STANDARD_CONFIG, ${general.depth}-stage)`);
    lines.push(`m4_def(ISA, ${general.isa})`);
    general.isa !== "MIPSI" && general.isaExtensions?.forEach(extension => {
        lines.push(`m4_def(EXT_${extension}, 1)`);
    });
    if (general.isa !== "MIPSI") {
        if (!general.isaExtensions?.includes("E")) lines.push(`m4_def(EXT_E, 0)`);
        if (!general.isaExtensions?.includes("M")) lines.push(`m4_def(EXT_M, 0)`);
        if (!general.isaExtensions?.includes("F")) lines.push(`m4_def(EXT_F, 0)`);
        if (!general.isaExtensions?.includes("B")) lines.push(`m4_def(EXT_B, 0)`);
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

export function getTLVCodeForDefinitions(definitions, programName, programText, isa, settings) {
    //console.log(settings)
    const verilatorConfig = new Set()
    // These are now handled in warp-v itself:
    //if (settings.isaExtensions.includes("F")) verilatorConfig.add("/* verilator lint_off WIDTH */")
    //if (settings.isaExtensions.includes("M")) {
    //    verilatorConfig.add("/* verilator lint_off WIDTH */")
    //    verilatorConfig.add("/* verilator lint_off CASEINCOMPLETE */")
    //}
    //if (settings.isaExtensions.includes("B")) {
    //    verilatorConfig.add("/* verilator lint_off WIDTH */")
    //    verilatorConfig.add("/* verilator lint_off PINMISSING */")
    //    verilatorConfig.add("/* verilator lint_off SELRANGE */")
    //}
    if (settings.formattingSettings.includes("--fmtPackAll")) {
        verilatorConfig.add("/* verilator lint_on WIDTH */ // TODO: Disabling WIDTH to work around what we think is https://github.com/verilator/verilator/issues/1613")
        verilatorConfig.delete("/* verilator lint_off WIDTH */")
    }
    const formattingSettings = settings.formattingSettings.filter(formattingArg => formattingArg !== "--fmtNoSource")
    return `\\m4_TLV_version 1d${formattingSettings.length > 0 ? ` ${formattingSettings.join(" ")}` : ""}: tl-x.org
\\SV
   /*
   Copyright ${new Date().getFullYear()} Redwood EDA, LLC
   
   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
   
   The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
   
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
   */
m4+definitions(['
${definitions ? "   " + (settings.customProgramEnabled ? [`m4_def(PROG_NAME, ${programName})`] : []).concat(definitions).join("\n   ") : ""}
'])
\\SV
   // Include WARP-V.
   ${verilatorConfig.size === 0 ? "" : [...verilatorConfig].join("\n   ")}
   m4_include_lib(['${settings.warpVVersion}'])
   
${settings.customProgramEnabled ? `\\TLV ${isa.toLowerCase()}_${programName}_prog()
   ${programText.split("\n").join("\n   ")}` : ``}

${settings.customProgramEnabled ? `m4+module_def()
\\TLV
   m4+warpv_top()
\\SV
   endmodule` : `m4+module_def()
\\TLV
   m4+warpv_top()
\\SV
   endmodule`}
`
}
