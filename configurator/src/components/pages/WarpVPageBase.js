import React, {useEffect} from "react";
import {Box, Button, Heading, HStack, Image} from "@chakra-ui/react";
import {getTLVCodeForDefinitions, translateJsonToM4Macros, translateParametersToJson} from "../translation/Translation";
import {CoreDetailsComponent} from "./CoreDetailsComponent";
import {OpenInMakerchipModal} from "../../utils/FetchUtils";

export function WarpVPageBase({
                                  programText,
                                  setProgramText,
                                  formErrors,
                                  setFormErrors,
                                  children,
                                  coreJson,
                                  macrosForJson,
                                  tlvForJson,
                                  setMacrosForJson,
                                  setTlvForJson,
                                  configuratorCustomProgramName,
                                  configuratorGlobalSettings,
                                  sVForJson,
                                  getSVForTlv,
                                  setSVForJson,
                                  setConfiguratorGlobalSettings,
                                  setDownloadingCode,
                                  setCoreJson,
                                  makerchipOpening,
                                  openInMakerchipUrl,
                                  setDisclosureAndUrl,
                                  openInMakerchipDisclosure,
                                  selectedFile,
                                  setSelectedFile,
                                  detailsComponentRef,
                                  userChangedStages,
                                  setPipelineDefaultDepth,
                                  setUserChangedStages,
                                  pipelineDefaultDepth,
                                  setMakerchipOpening,
                                  downloadingCode,
                                  validateForm,
                                  scrollToDetailsComponent,
                                  handleDownloadRTLVerilogButtonClicked,
                                  handleOpenInMakerchipButtonClicked
                              }) {


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

    useEffect(() => {
        translateParametersToJson(configuratorGlobalSettings, setConfiguratorGlobalSettings);
        const json = {
            general: configuratorGlobalSettings.generalSettings,
            pipeline: configuratorGlobalSettings.settings
        };
        if (JSON.stringify(coreJson) !== JSON.stringify(json)) {
            setCoreJson(json)
        }
    }, [configuratorGlobalSettings.generalSettings, configuratorGlobalSettings.settings]);

    return <>
        {children}

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
    </>

}