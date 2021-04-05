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

export function GeneralSettingsForm({ generalSettings, setGeneralSettings, formErrors }) {
  return <Box>
    <FormControl isInvalid={formErrors.includes('isa')} mb={4}>
      <FormLabel>ISA:</FormLabel>
      <RadioGroup onChange={value => setGeneralSettings({ ...generalSettings, isa: value })}
                  value={generalSettings.isa}>
        <Stack direction='row'>
          <Radio value='RISCV'>RISC-V</Radio>
          <Radio value='MIPSI'>MIPS</Radio>
        </Stack>
        <FormErrorMessage>Please select an ISA</FormErrorMessage>
      </RadioGroup>
    </FormControl>

    <FormControl isInvalid={formErrors.includes('depth')} mb={5}>
      <FormLabel>Pipeline Depth:</FormLabel>
      <RadioGroup onChange={value => setGeneralSettings({ ...generalSettings, depth: parseInt(value) })}
                  value={generalSettings.depth} defaultValue={4}>
        <Stack direction='row'>
          <Radio value={1}>1-cyc</Radio>
          <Radio value={2}>2-cyc</Radio>
          <Radio value={4}>4-cyc</Radio>
          <Radio value={6}>6-cyc</Radio>
        </Stack>
        <FormErrorMessage>Please select a pipeline depth</FormErrorMessage>
      </RadioGroup>
    </FormControl>

    {generalSettings.isa === 'RISCV' && <FormControl>
      <FormLabel>ISA Extensions (RISC-V only):</FormLabel>
      <CheckboxGroup onChange={values => setGeneralSettings({ ...generalSettings, isaExtensions: values })}>
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