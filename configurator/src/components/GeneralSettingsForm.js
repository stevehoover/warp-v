import {
    Box,
    Checkbox,
    CheckboxGroup,
    FormControl,
    FormErrorMessage,
    FormLabel,
    Radio,
    RadioGroup,
    Stack,
} from '@chakra-ui/react';

export function GeneralSettingsForm({configuratorGlobalSettings, setConfiguratorGlobalSettings, formErrors}) {
    return <Box>
        <FormControl isInvalid={formErrors.includes('isa')} mb={4}>
            <FormLabel>ISA:</FormLabel>
            <RadioGroup onChange={value => setConfiguratorGlobalSettings({
                ...configuratorGlobalSettings,
                generalSettings: {...configuratorGlobalSettings.generalSettings, isa: value}
            })}
                        value={configuratorGlobalSettings.generalSettings.isa}>
                <Stack direction='row'>
                    <Radio value='RISCV'>RISC-V</Radio>
                    <Radio value='MIPSI'>MIPS</Radio>
                </Stack>
                <FormErrorMessage>Please select an ISA</FormErrorMessage>
            </RadioGroup>
        </FormControl>

        <FormControl isInvalid={formErrors.includes('depth')} mb={5}>
            <FormLabel>Pipeline Depth:</FormLabel>
            <RadioGroup onChange={value => setConfiguratorGlobalSettings({
                ...configuratorGlobalSettings,
                generalSettings: {...configuratorGlobalSettings.generalSettings, depth: parseInt(value)}
            })}
                        value={configuratorGlobalSettings.generalSettings.depth} defaultValue={4}>
                <Stack direction='row'>
                    <Radio value={1}>1-cyc</Radio>
                    <Radio value={2}>2-cyc</Radio>
                    <Radio value={4}>4-cyc</Radio>
                    <Radio value={6}>6-cyc</Radio>
                </Stack>
                <FormErrorMessage>Please select a pipeline depth</FormErrorMessage>
            </RadioGroup>
        </FormControl>

        <FormControl mb={5}>
            <FormLabel>Formatting</FormLabel>
            <CheckboxGroup onChange={values => setConfiguratorGlobalSettings({
                ...configuratorGlobalSettings,
                generalSettings: {...configuratorGlobalSettings.generalSettings, formattingSettings: values}
            })}>
                <Stack direction='column'>
                    <Checkbox value='--fmtDeclSingleton'> Each HDL signal is declared in its own declaration statement
                        with its own type specification.</Checkbox>
                    <Checkbox value='--fmtDeclUnifiedHier'>Declare signals in a unified design hierarchy in the
                        generated file, as opposed to inline with scope lines in the translated file. (No impact if
                        --fmtFlatSignals.)</Checkbox>
                    <Checkbox value='--fmtEscapedNames'>Use escaped HDL names that resemble TLV names as closely as
                        possible.</Checkbox>
                    <Checkbox value='--fmtFlatSignals'>Declare signals at the top level scope in the generated file, and
                        do not use hierarchical signal references.</Checkbox>
                    <Checkbox value='--fmtFullHdlHier'>Provide HDL hierarchy for all scopes, including non-replicated
                        scopes.</Checkbox>
                    <Checkbox value='--fmtNoRespace'>Preserve whitespace in HDL expressions as is. Do not adjust
                        whitespace to preserve alignment of elements and comments of the expression.</Checkbox>
                  <Checkbox value='--fmtPackAll'>Generate HDL signals as packed at all levels of hierarchy.  Also, forces behavior of --fmtFlatSignals.</Checkbox>
                  <Checkbox value='--fmtPackBooleans'>Pack an additional level of hierarchy for boolean HDL signals. </Checkbox>
                  <Checkbox value='--fmtStripUniquifiers'>Eliminate the use of uniquifiers in HDL names where possible.</Checkbox>

                </Stack>
            </CheckboxGroup>
        </FormControl>

        {configuratorGlobalSettings.generalSettings.isa === 'RISCV' && <FormControl>
            <FormLabel>ISA Extensions (RISC-V only):</FormLabel>
            <CheckboxGroup value={configuratorGlobalSettings.generalSettings.isaExtensions} onChange={values => setConfiguratorGlobalSettings({
                ...configuratorGlobalSettings,
                generalSettings: {...configuratorGlobalSettings.generalSettings, isaExtensions: values}
            })}>
              <Stack direction='row'>
                    <Checkbox value='E' isChecked={configuratorGlobalSettings.generalSettings.isaExtensions?.includes("E")}>E</Checkbox>
                    <Checkbox value='M'>M</Checkbox>
                    <Checkbox value='F'>F</Checkbox>
                    <Checkbox value='B'>B</Checkbox>
                </Stack>
            </CheckboxGroup>
        </FormControl>}
    </Box>;
}