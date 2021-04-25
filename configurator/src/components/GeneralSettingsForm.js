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

export function GeneralSettingsForm({ configuratorGlobalSettings, setConfiguratorGlobalSettings, formErrors }) {
  return <Box>
    <FormControl isInvalid={formErrors.includes('isa')} mb={4}>
      <FormLabel>ISA:</FormLabel>
      <RadioGroup onChange={value => setConfiguratorGlobalSettings({...configuratorGlobalSettings, generalSettings: { ...configuratorGlobalSettings.generalSettings, isa: value }})}
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
      <RadioGroup onChange={value => setConfiguratorGlobalSettings({...configuratorGlobalSettings, generalSettings: { ...configuratorGlobalSettings.generalSettings, depth: parseInt(value) }})}
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
      <CheckboxGroup onChange={values => setConfiguratorGlobalSettings({...configuratorGlobalSettings, generalSettings: {...configuratorGlobalSettings.generalSettings, formattingSettings: values }})}>
        <Stack direction='row'>
          <Checkbox value='--fmtNoSource'>Do not generate \source tags for correlating pre- and post-M4 code</Checkbox>
        </Stack>
      </CheckboxGroup>
    </FormControl>

    {configuratorGlobalSettings.generalSettings.isa === 'RISCV' && <FormControl>
      <FormLabel>ISA Extensions (RISC-V only):</FormLabel>
      <CheckboxGroup onChange={values => setConfiguratorGlobalSettings({...configuratorGlobalSettings, generalSettings: {...configuratorGlobalSettings.generalSettings, isaExtensions: values }})}>
        <Stack direction='row'>
          <Checkbox value='E'>E</Checkbox>
          <Checkbox value='M'>M</Checkbox>
          <Checkbox value='F'>F</Checkbox>
          <Checkbox value='B'>B</Checkbox>
        </Stack>
      </CheckboxGroup>
    </FormControl>}
  </Box>;
}