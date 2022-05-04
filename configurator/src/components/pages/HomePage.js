import {Box, Button, Container, Heading, HStack, Image, Text} from '@chakra-ui/react';
import React from 'react';
import {ConfigurationParameters} from "../translation/ConfigurationParameters";
import {CoreDetailsComponent} from "./CoreDetailsComponent";
import {OpenInMakerchipModal} from "../../utils/FetchUtils";
import {ConfigureCpuComponent} from "./ConfigureCpuComponent";

export const pipelineParams = ["ld_return_align"].concat(ConfigurationParameters.map(param => param.jsonKey).filter(jsonKey => jsonKey !== "branch_pred" && jsonKey.endsWith("_stage")))
export const hazardsParams = ConfigurationParameters.filter(param => param.jsonKey.startsWith("extra_")).map(param => param.jsonKey)

export default function HomePage({
                                     configuratorGlobalSettings,
                                     setConfiguratorGlobalSettings,
                                     programText,
                                     setProgramText,
                                     userChangedStages,
                                     setUserChangedStages,
                                     formErrors
                                 }) {
    return <>
        <Box textAlign='center' mb={25}>
            <Image src='warpv-logo.png' maxW={250} mx='auto'/>
            <Text mb={2}>The open-source RISC-V core IP you can shape to your needs!</Text>
            <video controls autoPlay muted loop style={{"marginLeft": "auto", "marginRight": "auto", "width": "45%"}}>
                <source src="WARP-V_VIZ.mp4" type="video/mp4"/>
                Your browser does not support the video tag.
            </video>
        </Box>

        <Heading textAlign='center' size='md' mb={5}>What CPU core can we build for you today?</Heading>
        <Container maxW="fit-content">
            <HStack spacing={25} flexWrap="wrap" mx="auto" mb={10}>
                <CorePreview path='warpv-core-small.png' info='Low-Power, Low-Freq 1-cyc FPGA Implementation'
                             mb={3}/>
                <Box maxW={250} textAlign="center" mb={3}>
                    <Text fontSize={36}>...</Text>
                </Box>
                <CorePreview path='warpv-core-big.png' info='High-Freq 6-cyc ASIC Implementation' maxW={300}
                             mb={3}/>
            </HStack>
        </Container>
        <ConfigureCpuComponent configuratorGlobalSettings={configuratorGlobalSettings}
                               setConfiguratorGlobalSettings={setConfiguratorGlobalSettings} formErrors={formErrors}
                               settings={configuratorGlobalSettings.settings} userChangedStages={userChangedStages}
                               userChangedStages1={setUserChangedStages}
                               generalSettings={configuratorGlobalSettings.generalSettings}
                               onFormattingChange={values => setConfiguratorGlobalSettings({
                                   ...configuratorGlobalSettings,
                                   generalSettings: {
                                       ...configuratorGlobalSettings.generalSettings,
                                       formattingSettings: values
                                   }
                               })} onVersionChange={version => setConfiguratorGlobalSettings({
            ...configuratorGlobalSettings,
            generalSettings: {
                ...configuratorGlobalSettings.generalSettings,
                warpVVersion: version
            }
        })} programText={programText} setProgramText={setProgramText}/>
    </>;
}

function CorePreview({path, info, ...rest}) {
    return <Box>
        <Image src={path} mx='auto' {...rest} />
        <Text mx='auto' textAlign='center' maxW={160}>{info}</Text>
    </Box>;
}


