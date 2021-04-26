import {
  Box,
  Checkbox,
  FormControl,
  FormLabel,
  NumberDecrementStepper,
  NumberIncrementStepper,
  NumberInput,
  NumberInputField,
  NumberInputStepper,
  Radio,
  RadioGroup,
  Stack,
  Text,
} from '@chakra-ui/react';
import { ConfigurationParameters, Int, RadioParameter } from '../translation/ConfigurationParameters';

export function PipelineSettingsForm({ settings, setSettings, formErrors }) {

  function handleValueUpdate(key, type, value) {
    const newObj = { ...settings };
    newObj[key] = value;
    setSettings(newObj);
  }

  return <Box>
    {ConfigurationParameters.map(configurationParameter => {
      const jsonKey = configurationParameter.jsonKey;
      if (configurationParameter.type === Int) {
        return <FormControl mb={3} key={configurationParameter.jsonKey}
                            isInvalid={configurationParameter.validator && settings[jsonKey] !== undefined
                            && settings[jsonKey] && !configurationParameter.validator(settings[jsonKey], configurationParameter)}>
          <FormLabel mb={0}>{configurationParameter.readableName}</FormLabel>
          <Text mb={2}>{configurationParameter.description}</Text>
          <NumberInput maxW={100} step={1} min={configurationParameter.min}
                       onChange={(_, valueAsNumber) => handleValueUpdate(configurationParameter.jsonKey, Int, valueAsNumber)}>
            <NumberInputField placeholder={configurationParameter.defaultValue} />
            <NumberInputStepper>
              <NumberIncrementStepper />
              <NumberDecrementStepper />
            </NumberInputStepper>
          </NumberInput>
        </FormControl>;
      } else if (configurationParameter.type === Boolean) {
        return <FormControl mb={3} key={configurationParameter.jsonKey}
                            isInvalid={configurationParameter.validator && settings[jsonKey] !== undefined
                            && settings[jsonKey] && !configurationParameter.validator(settings[jsonKey], configurationParameter)}>
          <FormLabel mb={2}>{configurationParameter.readableName}</FormLabel>
          <Checkbox onChange={e => handleValueUpdate(configurationParameter.jsonKey, Int, e.target.checked)}>
            {configurationParameter.description}
          </Checkbox>
        </FormControl>;
      } else if (configurationParameter.type === RadioParameter) {
        return <FormControl mb={3} key={configurationParameter.jsonKey}>
          <FormLabel mb={2}>{configurationParameter.readableName}</FormLabel>
          <RadioGroup
            onChange={value => handleValueUpdate(configurationParameter.jsonKey, RadioParameter, value === 'None' ? null : value)}
            value={settings[configurationParameter.jsonKey] || 'None'} defaultValue='None'>
            <Stack direction='row'>
              {configurationParameter.possibleValues.map(possibleValue => <Radio key={possibleValue}
                                                                                 value={possibleValue}>{possibleValue}</Radio>)}
              <Radio value='None'>None</Radio>
            </Stack>
          </RadioGroup>
        </FormControl>;
      } else return null;
    })}
  </Box>;
}