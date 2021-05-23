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
    Tooltip
} from "@chakra-ui/react";
import {QuestionOutlineIcon} from "@chakra-ui/icons"
import {ConfigurationParameters, Int, RadioParameter} from "../translation/ConfigurationParameters";
import {ErrorBoundary} from 'react-error-boundary'

export function GenericSettingsFormComponent({
                                                 configuratorGlobalSettings,
                                                 setConfiguratorGlobalSettings,
                                                 configurationParametersSubset,
                                                 userChangedStages,
                                                 setUserChangedStages
                                             }) {


    function handleValueUpdate(param, key, type, value) {
        const newObj = {...configuratorGlobalSettings.settings};
        if (!value && value !== 0) {
            if (key.endsWith("_stage") && setUserChangedStages) setUserChangedStages(userChangedStages.filter(k => k !== key))
            delete newObj[key]
        } else if(newObj[key] !== value) {
            if (key.endsWith("_stage") && setUserChangedStages && !userChangedStages.includes(key)) setUserChangedStages([...userChangedStages, key])
            if (!configuratorGlobalSettings.settings[key] && configuratorGlobalSettings.settings[key] !== 0 && param?.defaultValue && param?.type === Int) value += param.defaultValue
            newObj[key] = value;
        }
        setConfiguratorGlobalSettings({...configuratorGlobalSettings, settings: newObj});
    }


    const getTitleComponent = (parameter) => <>
        {!parameter.description ? <FormLabel mb={2}>{parameter.readableName}</FormLabel> :
            <FormLabel mb={2}>
                <Tooltip label={parameter.description} fontSize="md">
                    <Box as="span" borderBottomStyle="dashed"
                         borderBottomWidth={1.5}>{parameter.readableName}<QuestionOutlineIcon ml={2} mb={1}/></Box>
                </Tooltip>
            </FormLabel>}
    </>

    return <ErrorBoundary>
        <Box>
            {ConfigurationParameters.filter(parameter => configurationParametersSubset.includes(parameter.jsonKey)).map(configurationParameter => {
                const jsonKey = configurationParameter.jsonKey;
                if (configurationParameter.type === Int) {
                    return <FormControl mb={3} key={configurationParameter.jsonKey}
                                        isInvalid={configurationParameter.validator && configuratorGlobalSettings.settings[jsonKey] !== undefined
                                        && configuratorGlobalSettings.settings[jsonKey] && !configurationParameter.validator(configuratorGlobalSettings.settings[jsonKey], configurationParameter)}>
                        {getTitleComponent(configurationParameter)}
                        <NumberInput maxW={100} step={1} min={configurationParameter.min}
                                     max={configurationParameter.max}
                                     onChange={(_, valueAsNumber) => handleValueUpdate(configurationParameter, configurationParameter.jsonKey, Int, valueAsNumber)}
                                     value={(configuratorGlobalSettings.settings[jsonKey] || configuratorGlobalSettings.settings[jsonKey] === 0) ? configuratorGlobalSettings.settings[jsonKey] : ""}>
                            <NumberInputField placeholder={configurationParameter.defaultValue}/>
                            <NumberInputStepper>
                                <NumberIncrementStepper/>
                                <NumberDecrementStepper/>
                            </NumberInputStepper>
                        </NumberInput>
                    </FormControl>;
                } else if (configurationParameter.type === Boolean) {
                    return <FormControl mb={3} key={configurationParameter.jsonKey}
                                        isInvalid={configurationParameter.validator && configuratorGlobalSettings.settings[jsonKey] !== undefined
                                        && configuratorGlobalSettings.settings[jsonKey] && !configurationParameter.validator(configuratorGlobalSettings.settings[jsonKey], configurationParameter)}>
                        {getTitleComponent(configurationParameter)}
                        <Checkbox
                            onChange={e => handleValueUpdate(configurationParameter, configurationParameter.jsonKey, Int, e.target.checked)}
                            value={configuratorGlobalSettings.settings[jsonKey] || ""}>
                        </Checkbox>
                    </FormControl>;
                } else if (configurationParameter.type === RadioParameter) {
                    return <FormControl mb={3} key={configurationParameter.jsonKey}>
                        {getTitleComponent(configurationParameter)}
                        <RadioGroup
                            onChange={value => handleValueUpdate(configurationParameter, configurationParameter.jsonKey, RadioParameter, value === 'None' ? null : value)}
                            value={configuratorGlobalSettings.settings[configurationParameter.jsonKey] || 'None'} defaultValue='None'>
                            <Stack direction='row'>
                                {configurationParameter.possibleValues.map(possibleValue => <Radio key={possibleValue}
                                                                                                   value={possibleValue}>{possibleValue}</Radio>)}
                                <Radio value='None'>None</Radio>
                            </Stack>
                        </RadioGroup>
                    </FormControl>;
                } else return null;
            })}
        </Box>
    </ErrorBoundary>
}