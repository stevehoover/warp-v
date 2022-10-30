import {Box, Checkbox, CheckboxGroup, FormControl, FormLabel, Input, Stack} from "@chakra-ui/react";
import React from "react";
import {DebounceInput} from "react-debounce-input";
import {getWarpVFileForCommit, warpVLatestSupportedCommit, warpVLatestVersionCommit} from "../../App";

export function VerilogSettingsForm({generalSettings, onFormattingChange, onVersionChange}) {
    return <>
        <Box mb={5}>
            <FormControl mb={5}>
                <FormLabel>WARP-V Version URL</FormLabel>
                <Input value={generalSettings.warpVVersion}
                       placeholder="WARP-V version URL"
                       as={DebounceInput}
                       debounceTimeout={300}
                       mb={3}
                       onChange={e => onVersionChange(e.target.value)} />

                <CheckboxGroup value={[getWarpVFileForCommit(warpVLatestSupportedCommit), getWarpVFileForCommit(warpVLatestVersionCommit)].includes(generalSettings.warpVVersion) ? [generalSettings.warpVVersion] : []}>
                    <Checkbox onChange={() => onVersionChange(getWarpVFileForCommit(warpVLatestVersionCommit))} value={getWarpVFileForCommit(warpVLatestVersionCommit)} mr={4} isDisabled={generalSettings.warpVVersion === warpVLatestVersionCommit}>Set to latest</Checkbox>
                    <Checkbox  onChange={() => onVersionChange(getWarpVFileForCommit(warpVLatestSupportedCommit))} value={getWarpVFileForCommit(warpVLatestSupportedCommit)} isDisabled={generalSettings.warpVVersion === warpVLatestSupportedCommit}>Set to latest tested version ({warpVLatestSupportedCommit.substring(0, 6)}...)</Checkbox>
                </CheckboxGroup>
            </FormControl>

        </Box>

        <FormControl mb={5}>
            <FormLabel>Verilog/SystemVerilog Formatting</FormLabel>
            <CheckboxGroup value={generalSettings.formattingSettings}
                           onChange={onFormattingChange}>
                <Stack direction="column">
                    <Checkbox value="--hdl verilog">Verilog (vs. SystemVerilog)</Checkbox>
                    <Checkbox value="--bestsv">Optimize SystemVerilog code for readability (versus
                        preserving line association with TL-Verilog source).</Checkbox>
                    <Checkbox value="--fmtNoSource">Disable \source tags in TL-Verilog. (Note, this is not an option in Makerchip.)</Checkbox>
                    <Checkbox value="--noline">Disable `line directive in SV output.</Checkbox>
                    <Checkbox value="--clkAlways">Use the global/free-running clock for all flip-flops.</Checkbox>
                    <Checkbox value="--clkEnable">Use enable flip-flops, not clock gating. (Good for FPGAs.)</Checkbox>
                    <Checkbox value="--clkStageAlways">Apply clock gating/enabling only to the first
                        of a series of flip-flops. Generally this will be less area, higher power.</Checkbox>
                    <Checkbox value="--fmtDeclSingleton"> Each HDL signal is declared in its own
                        declaration statement
                        with its own type specification.</Checkbox>
                    <Checkbox value="--fmtDeclUnifiedHier">Declare signals in a unified design hierarchy
                        in the
                        generated file, as opposed to inline with scope lines in the translated file.
                        (No impact if --fmtFlatSignals.)</Checkbox>
                    <Checkbox value="--fmtEscapedNames">Use escaped HDL names that resemble TLV names as
                        closely as
                        possible.</Checkbox>
                    <Checkbox value="--fmtFlatSignals">Declare signals at the top level scope in the
                        generated file, and
                        do not use hierarchical signal references.</Checkbox>
                    <Checkbox value="--fmtFullHdlHier">Provide HDL hierarchy for all scopes, including
                        non-replicated
                        scopes.</Checkbox>
                    <Checkbox value="--fmtInlineInjection">Provide X-injection and state recirculation for       
                        assignments under 'when' conditions in the          
                        assignment expressions themself where possible,     
                        rather than in separate manufactured assignments.</Checkbox>
                    <Checkbox value="--fmtNoRespace">Preserve whitespace in HDL expressions as is. Do
                        not adjust
                        whitespace to preserve alignment of elements and comments of the
                        expression.</Checkbox>
                    <Checkbox value="--fmtPackAll">Generate HDL signals as packed at all levels of
                        hierarchy. Also, forces behavior of --fmtFlatSignals.</Checkbox>
                    <Checkbox value="--fmtPackBooleans">Pack an additional level of hierarchy for
                        boolean HDL signals. </Checkbox>
                    <Checkbox value="--fmtStripUniquifiers">Eliminate the use of uniquifiers in HDL names where
                        possible.</Checkbox>
                    <Checkbox value="--fmtUseGenerate">Use the generate/endgenerate keywords that are
                        optional in SystemVerilog.</Checkbox>
                    <Checkbox value="--noDirectiveComments">For strict adherence to the Verilog specification, do
                        not output comments on `line and `include lines.</Checkbox>
                    <Checkbox value="--inlineGen" style={{visibility: 'hidden'}}>Produce generated content
                        inline in the primary output file rather than in a separate file.</Checkbox>
                    {/*<Checkbox value='--fmtStripUniquifiers'>Eliminate the use of uniquifiers in HDL
                                        names where possible.</Checkbox> //TODO re-add after mono fix #433 */}

                </Stack>
            </CheckboxGroup>
        </FormControl>
    </>;
}