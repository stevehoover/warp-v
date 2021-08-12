import React, {createRef, useState} from 'react';
import {Box, ChakraProvider, theme, useDisclosure} from '@chakra-ui/react';
import {Route, Switch} from 'react-router-dom';
import HomePage from './components/pages/HomePage';
import {ConfigurationParameters} from "./components/translation/ConfigurationParameters";
import {Footer} from "./components/header/Footer";
import {Header} from "./components/header/Header";
import {getWarpVFileForCommit, warpVLatestSupportedCommit} from "./utils/WarpVUtils";
import {WarpVPageBase} from "./components/pages/WarpVPageBase";


function App() {
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
                                       selectedFile={selectedFile}
                                       setSelectedFile={setSelectedFile}
                                       setUserChangedStages={setUserChangedStages}
                                       userChangedStages={userChangedStages}
                                       downloadingCode={downloadingCode}
                                       detailsComponentRef={detailsComponentRef}
                                       openInMakerchipDisclosure={openInMakerchipDisclosure}
                                       openInMakerchipUrl={openInMakerchipUrl}
                                       makerchipOpening={makerchipOpening}
                                       configuratorCustomProgramName={configuratorCustomProgramName}
                                       configuratorGlobalSettings={configuratorGlobalSettings}
                                       setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                       coreJson={coreJson}
                                       setCoreJson={setCoreJson}
                                       macrosForJson={macrosForJson}
                                       setMacrosForJson={setMacrosForJson}
                                       setSVForJson={setSVForJson}
                                       setTlvForJson={setTlvForJson}
                                       pipelineDefaultDepth={pipelineDefaultDepth}
                                       setPipelineDefaultDepth={setPipelineDefaultDepth}
                                       setDownloadingCode={setDownloadingCode}
                                       setMakerchipOpening={setMakerchipOpening}
                                       setOpenInMakerchipUrl={setOpenInMakerchipUrl}
                        >
                            <HomePage configuratorGlobalSettings={configuratorGlobalSettings}
                                      setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                      programText={programText}
                                      setProgramText={setProgramText}
                                      userChangedStages={userChangedStages}
                                      setUserChangedStages={setUserChangedStages}
                                      formErrors={formErrors}
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
