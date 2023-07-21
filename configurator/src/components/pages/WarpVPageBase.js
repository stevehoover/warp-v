import React, {useEffect} from "react";
import {Box, Button, Heading, HStack, Image, useToast} from "@chakra-ui/react";
import {getTLVCodeForDefinitions, translateJsonToM4Macros, translateParametersToJson} from "../translation/Translation";
import {CoreDetailsComponent} from "./CoreDetailsComponent";
import {downloadOrCopyFile, openInMakerchip, OpenInMakerchipModal} from "../../utils/FetchUtils";
import useFetch from "../../utils/useFetch";

export function WarpVPageBase({
                                  programText,
                                  children,
                                  coreJson,
                                  macrosForJson,
                                  tlvForJson,
                                  setMacrosForJson,
                                  setTlvForJson,
                                  configuratorCustomProgramName,
                                  configuratorGlobalSettings,
                                  sVForJson,
                                  setSVForJson,
                                  setConfiguratorGlobalSettings,
                                  setCoreJson,
                                  makerchipOpening,
                                  openInMakerchipUrl,
                                  openInMakerchipDisclosure,
                                  selectedFile,
                                  setSelectedFile,
                                  detailsComponentRef,
                                  userChangedStages,
                                  setPipelineDefaultDepth,
                                  setUserChangedStages,
                                  pipelineDefaultDepth,
                                  downloadingCode,
                                  setFormErrors,
                                  formErrors,
                                  setMakerchipOpening,
                                  setDownloadingCode,
                                  setOpenInMakerchipUrl
                              }) {
    const makerchipFetch = useFetch("https://faas.makerchip.com")
    const toast = useToast()

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

    function scrollToDetailsComponent() {
        setSelectedFile("m4")
        detailsComponentRef?.current?.scrollIntoView()
    }

    async function getSVForTlv(tlv, callback) {
        // Extract settings to be applied to sandpiper-saas command-line, not via --iArgs (aka, args for the sandpiper wrapper script).
        const externSettings = configuratorGlobalSettings.generalSettings.formattingSettings.filter(formattingArg => formattingArg === "--fmtNoSource")
        const args = `-i test.tlv -o test.sv --m4out out/m4out ${externSettings.join(" ")} --iArgs`
        const data = await makerchipFetch.post(
            "/function/sandpiper-faas",
            {
                args: args,
                responseType: "json",
                sv_url_inc: true,
                files: {
                    "test.tlv": tlv
                }
            },
            false,
        )
           .catch(err => {
                toast({
                    title: "Compilation fetch failed",
                    status: "error"
                })
                console.error(err)
                return {"out/m4out": "// Compilation failed.", "out/test.sv": "// Compilation failed.", "out/test_gen.sv": "// Compilation failed."}
            })
        if (data["out/m4out"]) setTlvForJson(data["out/m4out"].replaceAll("\n\n", "\n").replace("[\\source test.tlv]", "")) // remove some extra spacing by removing extra newlines
        else toast({
            title: "Failed compilation",
            status: "error"
        })
        setMacrosForJson(tlv.split("\n"))

        if (data["out/test.sv"]) {
            const verilog = data["out/test.sv"]
                .replace("`include \"test_gen.sv\"", "// gen included here\n" + data["out/test_gen.sv"])   // (Due to --inlineGen being forced, this no longer matters.)
                .split("\n")
                .filter(line => !line.startsWith("`include \"sp_default.vh\""))
                .join("\n")
            callback(verilog)
        }
    }

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
                downloadOrCopyFile(false, 'verilog.sv', sv);
                setDownloadingCode(false)
            });
        }
    }

    function setDisclosureAndUrl(newUrl) {
        setOpenInMakerchipUrl(newUrl)
        openInMakerchipDisclosure.onOpen()
    }

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
        {/* CoreDetailsComponent used to contain "generalSettings={configuratorGlobalSettings.generalSettings} settings={configuratorGlobalSettings.settings}", but this resulted in "generalSettings="[object Object]" settings="[object Object]"" and a warning from React: "Warning: React does not recognize the `generalSettings` prop on a DOM element. If you intentionally want it to appear in the DOM as a custom attribute, spell it as lowercase `generalsettings` instead. If you accidentally passed it from a parent component, remove it from the DOM element." */}
        <CoreDetailsComponent coreJson={coreJson}
                              tlvForJson={tlvForJson}
                              macrosForJson={macrosForJson}
                              sVForJson={sVForJson}
                              selectedFile={selectedFile}
                              setSelectedFile={setSelectedFile}
                              setDiscloureAndUrl={setDisclosureAndUrl}
        />

        <OpenInMakerchipModal url={openInMakerchipUrl} disclosure={openInMakerchipDisclosure}/>
    </>

}
