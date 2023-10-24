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
    Tooltip,
} from '@chakra-ui/react';
import {QuestionOutlineIcon} from "@chakra-ui/icons";

export function GeneralSettingsForm({configuratorGlobalSettings, setConfiguratorGlobalSettings, formErrors}) {
    function handleChangeCoreTypeChanged(value) {
        if (value !== "MIPSI") {
            setConfiguratorGlobalSettings({
                ...configuratorGlobalSettings,
                generalSettings: {
                    ...configuratorGlobalSettings.generalSettings,
                    customInstructionsEnabled: true,
                    customProgramEnabled: true,
                    isa: value
                }
            });
        } else {
            setConfiguratorGlobalSettings({
                ...configuratorGlobalSettings,
                generalSettings: {
                    ...configuratorGlobalSettings.generalSettings,
                    isa: value,
                    customInstructionsEnabled: false,
                    customProgramEnabled: false,
                    isaExtensions: []
                },
                settings: {...configuratorGlobalSettings.settings, cores: 1}
            });
        }
    }

    return <Box>
        <FormControl isInvalid={formErrors.includes('isa')} mb={4}>
            <FormLabel>ISA:</FormLabel>
            <RadioGroup onChange={handleChangeCoreTypeChanged}
                        value={configuratorGlobalSettings.generalSettings.isa}>
                <Stack direction='row'>
                    <Radio value='RISCV'>RISC-V</Radio>
                    <Radio value='MIPSI'>MIPS</Radio>
                </Stack>
                <FormErrorMessage>Please select an ISA</FormErrorMessage>
            </RadioGroup>
        </FormControl>

        <FormControl isInvalid={formErrors.includes('depth')} mb={5}>
            {/*Pipeline Depth (updates detailed parameters under "Pipeline")*/}
            <Tooltip label='Pipeline Depth (updates detailed parameters under "Pipeline")'
                     fontSize="md">
                <Box as="span" borderBottomStyle="dashed"
                     borderBottomWidth={1.5}>Pipeline Depth:<QuestionOutlineIcon ml={2} mb={1}/></Box>
            </Tooltip>
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
                    <Radio isDisabled value={""}>Custom Pipeline</Radio>
                </Stack>
                <FormErrorMessage>Please select a pipeline depth</FormErrorMessage>
            </RadioGroup>
        </FormControl>

        {configuratorGlobalSettings.generalSettings.isa === 'RISCV' && <FormControl>
            <FormLabel mb={2}>
                <Tooltip label="RISC-V has a modular design, consisting of alternative base parts, with added optional extensions. The ISA base and its extensions are developed in a collective effort between industry, the research community and educational institutions. The base specifies instructions (and their encoding), control flow, registers (and their sizes), memory and addressing, logic (i.e., integer) manipulation, and ancillaries. The base alone can implement a simplified general-purpose computer, with full software support, including a general-purpose compiler.

The standard extensions are specified to work with all of the standard bases, and with each other without conflict."
                         fontSize="md">
                    <Box as="span" borderBottomStyle="dashed"
                         borderBottomWidth={1.5}>ISA Extensions (RISC-V only):<QuestionOutlineIcon ml={2} mb={1}/></Box>
                </Tooltip>
            </FormLabel>
            <CheckboxGroup value={configuratorGlobalSettings.generalSettings.isaExtensions}
                           onChange={values => setConfiguratorGlobalSettings({
                               ...configuratorGlobalSettings,
                               generalSettings: {...configuratorGlobalSettings.generalSettings, isaExtensions: values}
                           })}>
                <Stack direction='row'>
                    <Checkbox value='E'
                              isDisabled={configuratorGlobalSettings.generalSettings.isa === "MIPSI"}
                              isChecked={configuratorGlobalSettings.generalSettings.isaExtensions?.includes("E")}>
                        <Tooltip label="Base Integer Instruction Set (embedded)">
                            <Box as="span">E <QuestionOutlineIcon/></Box>
                        </Tooltip>
                    </Checkbox>
                    <Checkbox value='M'
                              isDisabled={configuratorGlobalSettings.generalSettings.isa === "MIPSI"}
                              isChecked={configuratorGlobalSettings.generalSettings.isaExtensions?.includes("M")}>
                        <Tooltip label="Standard Extension for Integer Multiplication and Division">
                            <Box as="span">M <QuestionOutlineIcon/></Box>
                        </Tooltip>
                    </Checkbox>
                    <Checkbox value='F'
                              isDisabled={configuratorGlobalSettings.generalSettings.isa === "MIPSI"}
                              isChecked={configuratorGlobalSettings.generalSettings.isaExtensions?.includes("F")}>
                        <Tooltip label="Standard Extension for Single-Precision Floating-Point">
                            <Box as="span">F <QuestionOutlineIcon/></Box>
                        </Tooltip>
                    </Checkbox>
                    <Checkbox value='B'
                              isDisabled={configuratorGlobalSettings.generalSettings.isa === "MIPSI"}
                              isChecked={configuratorGlobalSettings.generalSettings.isaExtensions?.includes("B")}>
                        <Tooltip label="Standard Extension for Bit Manipulation">
                            <Box as="span">B <QuestionOutlineIcon/></Box>
                        </Tooltip>
                    </Checkbox>
                </Stack>
            </CheckboxGroup>
        </FormControl>}
    </Box>;
}