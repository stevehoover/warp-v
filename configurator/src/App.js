import React, {createRef, useEffect, useState} from 'react';
import ReactDOM from 'react-dom';
import {Box, ChakraProvider, theme, useDisclosure} from '@chakra-ui/react';
import {Route, Switch} from 'react-router-dom';
import HomePage from './components/pages/HomePage';
import {ConfigurationParameters} from "./components/translation/ConfigurationParameters";
import {Footer} from "./components/header/Footer";
import {Header} from "./components/header/Header";
import {WarpVPageBase} from "./components/pages/WarpVPageBase";
import {isFramed, onPaneEvent, postReady} from "./utils/PaneChannelClient";

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
                "--fmtNoSource"
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
    const [configuratorCustomProgramName] = useState("my_custom")
    const [programText, setProgramText] = useState(initialProgramText)
    // Bumped when the program textarea loses focus, to trigger a SandPiper preview recompile.
    // Program edits don't change coreJson, which otherwise gates the preview recompile.
    const [programCommitKey, setProgramCommitKey] = useState(0)
    const [formErrors, setFormErrors] = useState([]);

    const [userChangedStages, setUserChangedStages] = useState([])
    const [pipelineDefaultDepth, setPipelineDefaultDepth] = useState()
    const [makerchipOpening, setMakerchipOpening] = useState(false)
    const [downloadingCode, setDownloadingCode] = useState(false)
    const detailsComponentRef = createRef()
    const [selectedFile, setSelectedFile] = useState("m4")
    const openInMakerchipDisclosure = useDisclosure()
    const [openInMakerchipUrl, setOpenInMakerchipUrl] = useState()
    const [pendingBuild, setPendingBuild] = useState(null)
    // Static PC-tracking data delivered alongside the asm (source text + asm-row -> source-line
    // map), forwarded into the generated TLV so a VIZ widget can highlight the executing source
    // and asm line each cycle. Null unless a `sourceAsm` delivery carried it.
    const [ceMeta, setCeMeta] = useState(null)

    // When loaded as a Makerchip pane, listen for a `sourceAsm` event (e.g. from a Compiler
    // Explorer pane): enable the custom program, load the delivered assembly, and — if the
    // sender requested a build — flag a pending build that WarpVPageBase runs in the host IDE.
    useEffect(() => {
        if (!isFramed()) return undefined
        const off = onPaneEvent("sourceAsm", (payload) => {
            const asm = typeof payload?.asmText === "string" ? payload.asmText : ""
            const asmRows = Array.isArray(payload?.asm) ? payload.asm : []
            const meta = {
                source_code: typeof payload?.sourceText === "string" ? payload.sourceText : "",
                asm_lines: asmRows.map(r => (typeof r?.text === "string" ? r.text : "")),
                // Per asm row, the 1-based source line it came from (or null for label/blank rows).
                asm_line_to_source_line: asmRows.map(r => (typeof r?.line === "number" ? r.line : null)),
            }
            // This handler runs from a raw postMessage callback (outside React's synthetic-event
            // system), so in React 17 each setState would trigger a separate render. Without
            // batching, the preview effect fires after the customProgramEnabled update but before
            // setProgramText, baking the stale (default) program into the m4 preview. Batch them
            // so a single render carries both the enabled flag and the delivered program.
            ReactDOM.unstable_batchedUpdates(() => {
                setConfiguratorGlobalSettings(prev => ({
                    ...prev,
                    generalSettings: {...prev.generalSettings, customProgramEnabled: true}
                }))
                setProgramText(asm)
                setCeMeta(meta)
                if (payload?.build) setPendingBuild({asm})
            })
        })
        postReady()
        return off
    }, [])

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
                                       pendingBuild={pendingBuild}
                                       setPendingBuild={setPendingBuild}
                                       programCommitKey={programCommitKey}
                                       ceMeta={ceMeta}
                        >
                            <HomePage configuratorGlobalSettings={configuratorGlobalSettings}
                                      setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                      programText={programText}
                                      setProgramText={setProgramText}
                                      onProgramBlur={() => setProgramCommitKey(k => k + 1)}
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

export const warpVLatestSupportedCommit = "58691a6"
export const warpVLatestVersionCommit = "master"
