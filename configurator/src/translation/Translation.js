import { ConfigurationParameters } from './ConfigurationParameters';

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
  lines.push(`m4_def(M4_STANDARD_CONFIG, ${general.depth}-stage)`);
  lines.push(`m4_def(ISA, ${general.isa})`);
  general.isaExtensions?.forEach(extension => lines.push(`m4_ifndef(['M4_EXT_${extension}'], 1)`));
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
  else if (typeof input === 'string') return `"${input}"`;
}

export function getTLVCodeForDefinitions(definitions, includeLib) {
  return `\\m4_TLV_version 1d: tl-x.org
m4+definitions(['
        ${definitions ? definitions.join("\n") : ""}
'])
\\SV
   // Include WARP-V.
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/warp-v/master/warp-v.tlv'])
  
m4+module_def
\\TLV
   m4+warpv()
   m4+warpv_makerchip_cnt10_tb()
   m4+makerchip_pass_fail()
\\SV
   endmodule
            `;
}