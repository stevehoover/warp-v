import {
    Alert,
    AlertIcon,
    Box,
    Button,
    Container,
    Heading,
    HStack,
    Image,
    Tab,
    TabList,
    TabPanel,
    TabPanels,
    Tabs,
    Text,
    useDisclosure
} from '@chakra-ui/react';
import React, {createRef, useEffect, useState} from 'react';
import {
    getTLVCodeForDefinitions,
    translateJsonToM4Macros,
    translateParametersToJson,
} from '../translation/Translation';
import {GeneralSettingsForm} from '../components/GeneralSettingsForm';
import {GenericSettingsFormComponent} from "../components/GenericSettingsFormComponent";
import {ConfigurationParameters} from "../translation/ConfigurationParameters";
import {CoreDetailsComponent} from "./CoreDetailsComponent";
import {downloadFile, openInMakerchip, OpenInMakerchipModal} from "../utils/FetchUtils";
import {EnterProgramForm} from "./EnterProgramForm";
import {VerilogSettingsForm} from "./VerilogSettingsForm";

const pipelineParams = ["ld_return_align"].concat(ConfigurationParameters.map(param => param.jsonKey).filter(jsonKey => jsonKey !== "branch_pred" && jsonKey.endsWith("_stage")))
const hazardsParams = ConfigurationParameters.filter(param => param.jsonKey.startsWith("extra_")).map(param => param.jsonKey)

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
                                     setProgramText
                                 }) {
    const [formErrors, setFormErrors] = useState([]);
    const [userChangedStages, setUserChangedStages] = useState([])
    const [pipelineDefaultDepth, setPipelineDefaultDepth] = useState()
    const [makerchipOpening, setMakerchipOpening] = useState(false)
    const [downloadingCode, setDownloadingCode] = useState(false)
    const detailsComponentRef = createRef()
    const [selectedFile, setSelectedFile] = useState("m4")
    const openInMakerchipDisclosure = useDisclosure()
    const [openInMakerchipUrl, setOpenInMakerchipUrl] = useState()

    function setDisclosureAndUrl(newUrl) {
        setOpenInMakerchipUrl(newUrl)
        openInMakerchipDisclosure.onOpen()
    }

    useEffect(() => {
        if (!coreJson) return
        if (!coreJson && (macrosForJson || tlvForJson)) {
            setMacrosForJson(null)
            setTlvForJson(null)
        } else {
            const macros = translateJsonToM4Macros(coreJson)
            const tlv = getTLVCodeForDefinitions(macros, configuratorCustomProgramName, programText, configuratorGlobalSettings.generalSettings.isa, configuratorGlobalSettings.generalSettings)
            setMacrosForJson(tlv.split("\n"))

            const task = setTimeout(() => {
                getSVForTlv(tlv, sv => {
                    setSVForJson(sv)
                })
            }, 250)

            return () => {
                clearTimeout(task)
            }
        }
    }, [JSON.stringify(coreJson)])

    function scrollToDetailsComponent() {
        setSelectedFile("m4")
        detailsComponentRef?.current?.scrollIntoView()
    }

    function updateDefaultStagesForPipelineDepth(depth, newJson) {
        let valuesToSet;
        if (depth === 1) {
            valuesToSet = {
                next_pc_stage: 0,
                fetch_stage: 0,
                decode_stage: 0,
                branch_pred_stage: 0,
                register_rd_stage: 0,
                execute_stage: 0,
                result_stage: 0,
                register_wr_stage: 0,
                mem_wr_stage: 0,
                ld_return_align: 1,
                branch_pred: "fallthrough"
            }
        } else if (depth === 2) {
            valuesToSet = {
                next_pc_stage: 0,
                fetch_stage: 0,
                decode_stage: 0,
                branch_pred_stage: 0,
                register_rd_stage: 0,
                execute_stage: 1,
                result_stage: 1,
                register_wr_stage: 1,
                mem_wr_stage: 1,
                ld_return_align: 2,
                branch_pred: "two_bit"
            }
        } else if (depth === 4) {
            valuesToSet = {
                next_pc_stage: 0,
                fetch_stage: 0,
                decode_stage: 1,
                branch_pred_stage: 1,
                register_rd_stage: 1,
                execute_stage: 2,
                result_stage: 2,
                register_wr_stage: 3,
                mem_wr_stage: 3,
                extra_replay_bubble: 0,//1,
                ld_return_align: 4,
                branch_pred: "two_bit"
            }
        } else if (depth === 6) {
            valuesToSet = {
                next_pc_stage: 1,
                fetch_stage: 1,
                decode_stage: 3,
                branch_pred_stage: 4,
                register_rd_stage: 4,
                execute_stage: 5,
                result_stage: 5,
                register_wr_stage: 6,
                mem_wr_stage: 7,
                extra_replay_bubble: 0,//1,
                ld_return_align: 7,
                branch_pred: "two_bit"
            }
        }

        const newSettings = {...configuratorGlobalSettings.settings}
        const newUserChangedStages = [...userChangedStages]
        if (Object.entries(valuesToSet).length === 0) return;
        Object.entries(valuesToSet).forEach(entry => {
            const [key, value] = entry
            //if (!userChangedStages.includes(key)) {
            newSettings[key] = value
            //}
            if (!newUserChangedStages.includes(key)) newUserChangedStages.push(key)
        })
        setPipelineDefaultDepth(depth)
        setUserChangedStages(newUserChangedStages)
        setConfiguratorGlobalSettings({
            ...configuratorGlobalSettings,
            settings: newSettings,
            needsPipelineInit: false,
        })

    }

    useEffect(() => {
        const newJson = validateForm(false);
        if (configuratorGlobalSettings.generalSettings.depth && (configuratorGlobalSettings.needsPipelineInit || pipelineDefaultDepth !== configuratorGlobalSettings.generalSettings.depth)) {
            updateDefaultStagesForPipelineDepth(configuratorGlobalSettings.generalSettings.depth, newJson)
        }
    }, [configuratorGlobalSettings.generalSettings.depth]);


    function validateForm(err) {
        if (!err) {
            translateParametersToJson(configuratorGlobalSettings, setConfiguratorGlobalSettings);
            const json = {
                general: configuratorGlobalSettings.generalSettings,
                pipeline: configuratorGlobalSettings.settings
            };
            if (JSON.stringify(coreJson) !== JSON.stringify(json)) setCoreJson(json);
            return true
        }

        if (!configuratorGlobalSettings.generalSettings.depth && !formErrors.includes("depth")) {
            setFormErrors([...formErrors, 'depth']);
        } else {
            if (formErrors.length !== 0) setFormErrors([]);
            translateParametersToJson(configuratorGlobalSettings, setConfiguratorGlobalSettings);
            const json = {
                general: configuratorGlobalSettings.generalSettings,
                pipeline: configuratorGlobalSettings.settings
            };
            if (JSON.stringify(coreJson) !== JSON.stringify(json)) setCoreJson(json);
            return true
        }

        return null;
    }

    function handleOpenInMakerchipButtonClicked() {
        if (validateForm(true)) {
            setMakerchipOpening(true)
            const macros = translateJsonToM4Macros(coreJson);
            const tlv = getTLVCodeForDefinitions(macros, configuratorCustomProgramName, programText, configuratorGlobalSettings.generalSettings.isa, configuratorGlobalSettings.generalSettings);
            openInMakerchip(tlv, setMakerchipOpening, setDisclosureAndUrl)
        }
    }

    function handleDownloadRTLVerilogButtonClicked() {
        if (validateForm(true)) {
            const json = validateForm(true)
            if (json) setConfiguratorGlobalSettings({
                ...configuratorGlobalSettings,
                coreJson: json
            })
            setDownloadingCode(true)
            const macros = translateJsonToM4Macros(coreJson);
            const tlv = getTLVCodeForDefinitions(macros, configuratorCustomProgramName, programText, configuratorGlobalSettings.generalSettings.isa, configuratorGlobalSettings.generalSettings);
            getSVForTlv(tlv, sv => {
                downloadFile('verilog.sv', sv);
                setDownloadingCode(false)
            });
        }
    }

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
        <Box mx='auto' w={{base: "100%", md: "100vh"}}>
            <Heading size='lg' mb={4}>Configure your CPU now</Heading>
            <Tabs borderWidth={1} borderRadius='lg' p={3} isFitted>
                <TabList className="tab-list">
                    <Tab>General</Tab>
                    <Tab>Multi-Core</Tab>
                    <Tab>Pipeline</Tab>
                    <Tab>Components</Tab>
                    <Tab>Hazards</Tab>
                    <Tab>Memory</Tab>
                    <Tab>I/O</Tab>
                    <Tab>Verilog</Tab>
                    <Tab>Program</Tab>
                </TabList>
                <TabPanels>
                    <TabPanel>
                        <GeneralSettingsForm configuratorGlobalSettings={configuratorGlobalSettings}
                                             setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                             formErrors={formErrors}/>
                    </TabPanel>
                    <TabPanel>
                        <GenericSettingsFormComponent configuratorGlobalSettings={configuratorGlobalSettings}
                                                      setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                                      configurationParametersSubset={(configuratorGlobalSettings.settings["cores"] && configuratorGlobalSettings.settings["cores"] > 1) ? ["cores", "vcs", "prios", "max_packet_size"] : ["cores"]}/>
                    </TabPanel>
                    <TabPanel>
                        <GenericSettingsFormComponent configuratorGlobalSettings={configuratorGlobalSettings}
                                                      setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                                      configurationParametersSubset={pipelineParams}
                                                      userChangedStages={userChangedStages}
                                                      setUserChangedStages={setUserChangedStages}
                                                      mustBeMonotonicallyNonDecreasing={true}/>
                    </TabPanel>
                    <TabPanel>
                        <GenericSettingsFormComponent configuratorGlobalSettings={configuratorGlobalSettings}
                                                      setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                                      configurationParametersSubset={["branch_pred"]}/>
                    </TabPanel>
                    <TabPanel>
                        <Alert status="info" mb={5}>
                            <AlertIcon/>
                            EXTRA_*_BUBBLEs (0 or 1). Set to 1 to add a cycle to the replay condition and relax circuit
                            timing. (Not all configurations are valid.)
                        </Alert>

                        <GenericSettingsFormComponent configuratorGlobalSettings={configuratorGlobalSettings}
                                                      setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                                      configurationParametersSubset={hazardsParams}/>
                    </TabPanel>
                    <TabPanel>
                        <Text>WARP-V currently supports only the CPU core itself, with a small instruction memory and
                            data memory.</Text>
                    </TabPanel>
                    <TabPanel>
                        <Text>WARP-V does not currently provide any I/O components.</Text>
                    </TabPanel>
                    <TabPanel>
                        <VerilogSettingsForm generalSettings={configuratorGlobalSettings.generalSettings}
                                             onFormattingChange={values => setConfiguratorGlobalSettings({
                                                 ...configuratorGlobalSettings,
                                                 generalSettings: {
                                                     ...configuratorGlobalSettings.generalSettings,
                                                     formattingSettings: values
                                                 }
                                             })}
                                             onVersionChange={version => setConfiguratorGlobalSettings({
                                                 ...configuratorGlobalSettings,
                                                 generalSettings: {
                                                     ...configuratorGlobalSettings.generalSettings,
                                                     warpVVersion: version
                                                 }
                                             })}
                        />
                    </TabPanel>
                    <TabPanel>
                        <EnterProgramForm configuratorGlobalSettings={configuratorGlobalSettings}
                                          setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                          programText={programText} setProgramText={setProgramText}
                        />
                    </TabPanel>
                </TabPanels>
            </Tabs>
        </Box>

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

        <OpenInMakerchipModal url={openInMakerchipUrl} disclosure={openInMakerchipDisclosure} />
    </>;
}

function CorePreview({path, info, ...rest}) {
    return <Box>
        <Image src={path} mx='auto' {...rest} />
        <Text mx='auto' textAlign='center' maxW={160}>{info}</Text>
    </Box>;
}


