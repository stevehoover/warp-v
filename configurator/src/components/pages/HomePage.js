import {Box, Button, Container, Heading, HStack, Image, Text} from '@chakra-ui/react';
import React from 'react';
import {ConfigurationParameters} from "../translation/ConfigurationParameters";
import {CoreDetailsComponent} from "./CoreDetailsComponent";
import {OpenInMakerchipModal} from "../../utils/FetchUtils";
import {ConfigureCpuComponent} from "./ConfigureCpuComponent";

export const pipelineParams = ["ld_return_align"].concat(ConfigurationParameters.map(param => param.jsonKey).filter(jsonKey => jsonKey !== "branch_pred" && jsonKey.endsWith("_stage")))
export const hazardsParams = ConfigurationParameters.filter(param => param.jsonKey.startsWith("extra_")).map(param => param.jsonKey)

export default function HomePage({
                                     getSVForTlv,
                                     sVForJson,
                                     setSVForJson,
                                     tlvForJson,
                                     macrosForJson,
                                     setMacrosForJson,
                                     setTlvForJson,
                                     coreJson,
                                     setCoreJson,
                                     configuratorGlobalSettings,
                                     setConfiguratorGlobalSettings,
                                     configuratorCustomProgramName,
                                     setConfiguratorCustomProgramName,
                                     programText,
                                     setProgramText,
                                     userChangedStages,
                                     setUserChangedStages,
                                     scrollToDetailsComponent,
                                     handleDownloadRTLVerilogButtonClicked,
                                     downloadingCode,
                                     handleOpenInMakerchipButtonClicked,
                                     makerchipOpening,
                                     detailsComponentRef,
                                     openInMakerchipUrl,
                                     openInMakerchipDisclosure,
                                     selectedFile,
                                     setSelectedFile,
                                     setDisclosureAndUrl,
                                     formErrors,
                                     setFormErrors
                                 }) {
    return <>
        <Box textAlign='center' mb={25}>
            <Image src='warpv-logo.png' maxW={250} mx='auto'/>
            <Text>The open-source RISC-V core IP you can shape to your needs!</Text>
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

        <Box mt={5} mb={15} mx='auto' maxW='100vh' pb={10} borderBottomWidth={2}>
            <Heading size='lg' mb={4}>Get your code:</Heading>
            <HStack mb={3}>
                <Button type="button" colorScheme="blue" onClick={scrollToDetailsComponent}>View Below</Button>
                <Box>
                    <Button type='button' colorScheme="teal" onClick={handleDownloadRTLVerilogButtonClicked}
                            isLoading={downloadingCode} isDisabled={downloadingCode}>Download
                        Verilog</Button>
                </Box>
                <Button type='button' colorScheme='blue' onClick={handleOpenInMakerchipButtonClicked}
                        isLoading={makerchipOpening} isDisabled={makerchipOpening}>Open in Makerchip IDE</Button>
            </HStack>

            <Image src='makerchip-preview.png' w='350px'/>


        </Box>

        <div ref={detailsComponentRef}>
            <CoreDetailsComponent generalSettings={configuratorGlobalSettings.generalSettings}
                                  settings={configuratorGlobalSettings.settings}
                                  coreJson={coreJson}
                                  tlvForJson={tlvForJson}
                                  macrosForJson={macrosForJson}
                                  sVForJson={sVForJson}
                                  selectedFile={selectedFile}
                                  setSelectedFile={setSelectedFile}
                                  setDiscloureAndUrl={setDisclosureAndUrl}
            />
        </div>

        <OpenInMakerchipModal url={openInMakerchipUrl} disclosure={openInMakerchipDisclosure}/>
    </>;
}

function CorePreview({path, info, ...rest}) {
    return <Box>
        <Image src={path} mx='auto' {...rest} />
        <Text mx='auto' textAlign='center' maxW={160}>{info}</Text>
    </Box>;
}


