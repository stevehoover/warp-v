import React, {createRef, useEffect, useState} from 'react';
import {Box, ChakraProvider, theme, useDisclosure, useToast} from '@chakra-ui/react';
import {Route, Switch} from 'react-router-dom';
import HomePage from './components/pages/HomePage';
import useFetch from './utils/useFetch';
import {ConfigurationParameters} from "./components/translation/ConfigurationParameters";
import {
    getTLVCodeForDefinitions,
    translateJsonToM4Macros,
    translateParametersToJson
} from "./components/translation/Translation";
import {Footer} from "./components/header/Footer";
import {Header} from "./components/header/Header";
import {getWarpVFileForCommit, warpVLatestSupportedCommit} from "./utils/WarpVUtils";
import {WarpVPageBase} from "./components/pages/WarpVPageBase";
import {downloadFile, openInMakerchip} from "./utils/FetchUtils";


function App() {
    const makerchipFetch = useFetch("https://faas.makerchip.com")

    const [configuratorGlobalSettings, setConfiguratorGlobalSettings] = useState({
        settings: getInitialSettings(),
        coreJson: null,
        generalSettings: {
            warpVVersion: getWarpVFileForCommit(warpVLatestSupportedCommit),
            isa: 'RISCV',
            isaExtensions: [],
            depth: 4,
            formattingSettings: [
                "--bestsv",
                "--noline",
                "--fmtNoSource"
            ],
            customProgramEnabled: false
        },
        needsPipelineInit: true
    })

    const [sVForJson, setSVForJson] = useState()
    const [tlvForJson, setTlvForJson] = useState()
    const [macrosForJson, setMacrosForJson] = useState()
    const [coreJson, setCoreJson] = useState(null)
    const [configuratorCustomProgramName, setConfiguratorCustomProgramName] = useState("my_custom")
    const [programText, setProgramText] = useState(initialProgramText)
    const [formErrors, setFormErrors] = useState([]);

    const toast = useToast()

    const [userChangedStages, setUserChangedStages] = useState([])
    const [pipelineDefaultDepth, setPipelineDefaultDepth] = useState()
    const [makerchipOpening, setMakerchipOpening] = useState(false)
    const [downloadingCode, setDownloadingCode] = useState(false)
    const detailsComponentRef = createRef()
    const [selectedFile, setSelectedFile] = useState("m4")
    const openInMakerchipDisclosure = useDisclosure()
    const [openInMakerchipUrl, setOpenInMakerchipUrl] = useState()

    function getInitialSettings() {
        const settings = {
            cores: 1
        }
        ConfigurationParameters.forEach(param => settings[param.jsonKey] = param.defaultValue)
        return settings
    }

    function setDisclosureAndUrl(newUrl) {
        setOpenInMakerchipUrl(newUrl)
        openInMakerchipDisclosure.onOpen()
    }

    async function getSVForTlv(tlv, callback) {
        const data = await makerchipFetch.post(
            "/function/sandpiper-faas",
            {
                args: `-i test.tlv -o test.sv --iArgs --m4out out/m4out ${configuratorGlobalSettings.generalSettings.formattingSettings.filter(setting => setting === "--fmtNoSource").join(" ")}`,
                responseType: "json",
                sv_url_inc: true,
                files: {
                    "test.tlv": tlv
                }
            },
            false,
        )
        //console.log(tlv)
        //console.log(data)
        if (data["out/m4out"]) setTlvForJson(data["out/m4out"].replaceAll("\n\n", "\n").replace("[\\source test.tlv]", "")) // remove some extra spacing by removing extra newlines
        else toast({
            title: "Failed compilation",
            status: "error"
        })
        setMacrosForJson(tlv.split("\n"))

        if (data["out/test.sv"]) {
            const verilog = data["out/test.sv"]
                .replace("`include \"test_gen.sv\"", "// gen included here\n" + data["out/test_gen.sv"])
                .split("\n")
                .filter(line => !line.startsWith("`include \"sp_default.vh\""))
                .join("\n")
            callback(verilog)
        }
    }


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

    function getInitialSettings() {
        const settings = {
            cores: 1
        }
        ConfigurationParameters.forEach(param => settings[param.jsonKey] = param.defaultValue)
        return settings
    }

    async function getSVForTlv(tlv, callback) {
        const data = await makerchipFetch.post(
            "/function/sandpiper-faas",
            {
                args: `-i test.tlv -o test.sv --iArgs --m4out out/m4out ${configuratorGlobalSettings.generalSettings.formattingSettings.filter(setting => setting === "--fmtNoSource").join(" ")}`,
                responseType: "json",
                sv_url_inc: true,
                files: {
                    "test.tlv": tlv
                }
            },
            false,
        )
        //console.log(tlv)
        //console.log(data)
        if (data["out/m4out"]) setTlvForJson(data["out/m4out"].replaceAll("\n\n", "\n").replace("[\\source test.tlv]", "")) // remove some extra spacing by removing extra newlines
        else toast({
            title: "Failed compilation",
            status: "error"
        })
        setMacrosForJson(tlv.split("\n"))

        if (data["out/test.sv"]) {
            const verilog = data["out/test.sv"]
                .replace("`include \"test_gen.sv\"", "// gen included here\n" + data["out/test_gen.sv"])
                .split("\n")
                .filter(line => !line.startsWith("`include \"sp_default.vh\""))
                .join("\n")
            callback(verilog)
        }
    }

    function scrollToDetailsComponent() {
        setSelectedFile("m4")
        detailsComponentRef?.current?.scrollIntoView()
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
                downloadFile('verilog.sv', sv);
                setDownloadingCode(false)
            });
        }
    }

    return <ChakraProvider theme={theme}>
        <Box minHeight='480px'>
            {<Header/>}

            <Box mx={5} overflowWrap>
                <Switch>
                    <Route exact path='/'>
                        <WarpVPageBase programText={programText}
                                       setProgramText={setProgramText}
                                       formErrors={formErrors}
                                       setFormErrors={setFormErrors}
                                       tlvForJson={tlvForJson}
                                       sVForJson={sVForJson}
                                       selectedFile={selectedFile} setSelectedFile={setSelectedFile}
                                       setUserChangedStages={setUserChangedStages} userChangedStages={userChangedStages}
                                       downloadingCode={downloadingCode} detailsComponentRef={detailsComponentRef}
                                       openInMakerchipDisclosure={openInMakerchipDisclosure}
                                       openInMakerchipUrl={openInMakerchipUrl} makerchipOpening={makerchipOpening}
                                       setDisclosureAndUrl={setDisclosureAndUrl}
                                       configuratorCustomProgramName={configuratorCustomProgramName}
                                       configuratorGlobalSettings={configuratorGlobalSettings}
                                       setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                       getSVForTlv={getSVForTlv} coreJson={coreJson} setCoreJson={setCoreJson}
                                       macrosForJson={macrosForJson} setMacrosForJson={setMacrosForJson}
                                       setSVForJson={setSVForJson} setTlvForJson={setTlvForJson}
                                       pipelineDefaultDepth={pipelineDefaultDepth}
                                       setPipelineDefaultDepth={setPipelineDefaultDepth}
                                       setDownloadingCode={setDownloadingCode}
                                       setMakerchipOpening={setMakerchipOpening}
                                       validateForm={validateForm} scrollToDetailsComponent={scrollToDetailsComponent}
                                       handleOpenInMakerchipButtonClicked={handleOpenInMakerchipButtonClicked}
                                       handleDownloadRTLVerilogButtonClicked={handleDownloadRTLVerilogButtonClicked}
                        >
                            <HomePage configuratorGlobalSettings={configuratorGlobalSettings}
                                      setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                      getSVForTlv={getSVForTlv}
                                      sVForJson={sVForJson}
                                      setSVForJson={setSVForJson}
                                      macrosForJson={macrosForJson}
                                      coreJson={coreJson}
                                      setCoreJson={setCoreJson}
                                      tlvForJson={tlvForJson}
                                      setTlvForJson={setTlvForJson}
                                      setMacrosForJson={setMacrosForJson}
                                      configuratorCustomProgramName={configuratorCustomProgramName}
                                      setConfiguratorCustomProgramName={setConfiguratorCustomProgramName}
                                      programText={programText}
                                      setProgramText={setProgramText}
                                      userChangedStages={userChangedStages}
                                      downloadingCode={downloadingCode}
                                      detailsComponentRef={detailsComponentRef}
                                      openInMakerchipDisclosure={openInMakerchipDisclosure}
                                      openInMakerchipUrl={openInMakerchipUrl}
                                      setFormErrors={setFormErrors}
                                      formErrors={formErrors}
                                      setDisclosureAndUrl={setDisclosureAndUrl}
                                      handleDownloadRTLVerilogButtonClicked={handleDownloadRTLVerilogButtonClicked}
                                      handleOpenInMakerchipButtonClicked={handleOpenInMakerchipButtonClicked}
                                      makerchipOpening={makerchipOpening}
                                      scrollToDetailsComponent={scrollToDetailsComponent}
                                      selectedFile={selectedFile}
                                      setSelectedFile={setSelectedFile}
                                      setUserChangedStages={setUserChangedStages}
                            />
                        </WarpVPageBase>
                    </Route>
                </Switch>
            </Box>

            <Footer/>
        </Box>
    </ChakraProvider>;
}

const initialProgramText = `// /=====================\\
// | Count to 10 Program |
// =====================/
//
// Default program for RV32I test
// Add 1,2,3,...,9 (in that order).
// Store incremental results in memory locations 0..9. (1, 3, 6, 10, ...)
//
// Regs:
// 1: cnt
// 2: ten
// 3: out
// 4: tmp
// 5: offset
// 6: store addr

m4_asm(ORI, r6, r0, 0)// store_addr = 0
m4_asm(ORI, r1, r0, 1)// cnt = 1
m4_asm(ORI, r2, r0, 1010) // ten = 10
m4_asm(ORI, r3, r0, 0)// out = 0
m4_asm(ADD, r3, r1, r3)   //  -> out += cnt
m4_asm(SW, r6, r3, 0) // store out at store_addr
m4_asm(ADDI, r1, r1, 1)   // cnt ++
m4_asm(ADDI, r6, r6, 100) // store_addr++
m4_asm(BLT, r1, r2, 1111111110000) //  ^- branch back if cnt < 10
m4_asm(LW, r4, r6, 111111111100) // load the final value into tmp
m4_asm(BGE, r1, r2, 1111111010100) // TERMINATE by branching to -1
`

export default App;
