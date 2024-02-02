import React, {createRef, useState} from 'react';
import {Box, ChakraProvider, theme, useDisclosure} from '@chakra-ui/react';
import {Route, Switch} from 'react-router-dom';
import HomePage from './components/pages/HomePage';
import {ConfigurationParameters} from "./components/translation/ConfigurationParameters";
import {Footer} from "./components/header/Footer";
import {Header} from "./components/header/Header";
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
                "--inlineGen",
                "--bestsv",
                "--noline",
                "--fmtNoSource",
                "--noDirectiveComments"
            ],
            customProgramEnabled: false,
            customInstructionsEnabled: false
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

const initialProgramText = `# /=====================\\
# | Count to 10 Program |
# \\=====================/
#
# Default program for RV32I test
# Add 1,2,3,...,9 (in that order).
# Store incremental results in memory locations 0..9. (1, 3, 6, 10, ...)
#
# Regs:
# t0: cnt
# a2: ten
# a0: out
# t1: final value
# a1: expected result
# t2: store addr
reset:
   ORI t2, zero, 0          #     store_addr = 0
   ORI t0, zero, 1          #     cnt = 1
   ORI a2, zero, 10         #     ten = 10
   ORI a0, zero, 0          #     out = 0
loop:
   ADD a0, t0, a0           #  -> out += cnt
   SW a0, 0(t2)             #     store out at store_addr
   ADDI t0, t0, 1           #     cnt++
   ADDI t2, t2, 4           #     store_addr++
   BLT t0, a2, loop         #  ^- branch back if cnt < 10
# Result should be 0x2d.
   LW t1, -4(t2)            #     load the final value
   ADDI a1, zero, 0x2d      #     expected result (0x2d)
   BEQ t1, a1, pass         #     pass if as expected

   # Branch to one of these to report pass/fail to the default testbench.
fail:
   ADD a1, a1, zero         #     nop fail
pass:
   ADD t1, t1, zero         #     nop pass
`

export default App;

export function getWarpVFileForCommit(version) {
    return `https://raw.githubusercontent.com/stevehoover/warp-v/${version}/warp-v.tlv`
}

export const warpVLatestSupportedCommit = "92121a3ca0acb3d711a5779b50dc9550ea999f9b"
export const warpVLatestVersionCommit = "master"
