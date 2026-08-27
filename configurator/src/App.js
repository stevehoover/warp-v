import React, {createRef, useEffect, useRef, useState} from 'react';
import ReactDOM from 'react-dom';
import {Box, ChakraProvider, theme, useColorMode, useDisclosure} from '@chakra-ui/react';
import {Route, Switch} from 'react-router-dom';
import HomePage from './components/pages/HomePage';
import {ConfigurationParameters} from "./components/translation/ConfigurationParameters";
import {getTLVCodeForDefinitions, translateJsonToM4Macros} from "./components/translation/Translation";
import {Footer} from "./components/header/Footer";
import {Header} from "./components/header/Header";
import {WarpVPageBase} from "./components/pages/WarpVPageBase";
import {callIde, isFramed, onPaneEvent, postReady, registerPaneMethod} from "./utils/PaneChannelClient";

// Extract the delivered assembly text and PC-tracking metadata from a `sourceAsm`/`build`
// payload (as sent by a Compiler Explorer pane).
function deliveredFromPayload(payload) {
    const asm = typeof payload?.asmText === "string" ? payload.asmText : ""
    const asmRows = Array.isArray(payload?.asm) ? payload.asm : []
    return {
        asm,
        meta: {
            source_code: typeof payload?.sourceText === "string" ? payload.sourceText : "",
            asm_lines: asmRows.map(r => (typeof r?.text === "string" ? r.text : "")),
            // Per asm row, the 1-based source line it came from (or null for label/blank rows).
            asm_line_to_source_line: asmRows.map(r => (typeof r?.line === "number" ? r.line : null)),
            // Entry-point label the CE pane detected (language-specific, e.g. `main` or Fortran's
            // `MAIN__`); drives the crt0 preamble. Null/absent for older CE panes.
            entry: typeof payload?.entry === "string" ? payload.entry : null,
            // Producer language/compiler tag (e.g. `c`, `fortran`); selects a runtime shim in
            // m5_assemble (self-serve: tags with no registered shim inject nothing). Null for older panes.
            lang: typeof payload?.lang === "string" ? payload.lang : null,
        },
    }
}

// When loaded as a Makerchip pane, follow the host IDE's dark/light mode. One-way: the pane
// mirrors the IDE and never pushes its color mode back. Reads the initial theme from the
// `getContext` RPC and then tracks live `theme` broadcasts. Rendered inside ChakraProvider so
// it can drive Chakra's color mode.
function PaneThemeSync() {
    const {setColorMode} = useColorMode()
    useEffect(() => {
        if (!isFramed()) return undefined
        const off = onPaneEvent("theme", (payload) => {
            if (payload && typeof payload.dark === "boolean") setColorMode(payload.dark ? "dark" : "light")
        })
        callIde("getContext")
            .then(ctx => {
                if (ctx?.theme && typeof ctx.theme.dark === "boolean") setColorMode(ctx.theme.dark ? "dark" : "light")
            })
            .catch(() => {})
        return off
    }, [setColorMode])
    return null
}

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
            customInstructionsEnabled: false,
            programEntry: ""
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

    // Mirror the latest state so the pane-RPC handlers below (registered once at mount) can read
    // fresh values, dodging stale closures. Updated on every render.
    const liveStateRef = useRef(null)
    liveStateRef.current = {configuratorGlobalSettings, programText, ceMeta, configuratorCustomProgramName}

    // When loaded as a Makerchip pane, accept a delivered program (assembly + PC-tracking
    // metadata) from a Compiler Explorer pane, two ways:
    //   - the `sourceAsm` bus event (fire-and-forget), and
    //   - the `build` inbound RPC, whose caller can additionally get the resulting host compile id
    //     back (so an AI/extension can await/poll the compilation it triggered).
    // Both enable the custom program and load the delivered assembly; if a build is requested they
    // flag a pending build that WarpVPageBase runs in the host IDE.
    useEffect(() => {
        if (!isFramed()) return undefined

        // Apply a delivered payload's program to state. `build` (when non-null) requests a build,
        // optionally carrying a resolver that WarpVPageBase settles with the host compile id.
        const applyDelivered = (payload, build) => {
            const {asm, meta} = deliveredFromPayload(payload)
            // This runs from a raw postMessage callback (outside React's synthetic-event system),
            // so in React 17 each setState would trigger a separate render. Without batching, the
            // preview effect fires after the customProgramEnabled update but before setProgramText,
            // baking the stale (default) program into the m4 preview. Batch them so a single render
            // carries both the enabled flag and the delivered program.
            ReactDOM.unstable_batchedUpdates(() => {
                setConfiguratorGlobalSettings(prev => ({
                    ...prev,
                    generalSettings: {...prev.generalSettings, customProgramEnabled: true}
                }))
                setProgramText(asm)
                setCeMeta(meta)
                if (build) setPendingBuild({asm, resolve: build.resolve ?? null})
            })
        }

        const off = onPaneEvent("sourceAsm", (payload) => {
            applyDelivered(payload, payload?.build ? {} : null)
        })

        // `build(payload, waitForCompileId)`: like a `sourceAsm` build, but if waitForCompileId the
        // returned promise resolves with the host compile id (WarpVPageBase relays it); otherwise
        // it resolves immediately (fire-and-forget, avoiding the host round-trip).
        const offBuild = registerPaneMethod("build", (payload, waitForCompileId) =>
            new Promise((resolve) => {
                applyDelivered(payload, {resolve: waitForCompileId ? resolve : null})
                if (!waitForCompileId) resolve(null)
            })
        )

        // Read the current configuration. In addition to providing the actual configuration data
        // this method may also be used to discover the shape of the configuration to provide
        // to `setConfig`:
        //   { general, pipeline, programText }
        // where `general` is the top-of-form settings (warpVVersion, isa, depth, custom-program
        // flags, ...), `pipeline` maps each ConfigurationParameter jsonKey to its value, and
        // `programText` is the (assembly) program source.
        const offGetConfig = registerPaneMethod("getConfig", () => {
            const {configuratorGlobalSettings: cgs, programText: pt} = liveStateRef.current
            return {general: cgs.generalSettings, pipeline: cgs.settings, programText: pt}
        })

        // Apply a partial configuration: { general?, pipeline?, programText? }. Objects are
        // shallow-merged over current state; arrays and scalars replace. Pipeline values are
        // validated with each parameter's own validator; unknown keys (either bucket) are rejected.
        // Cross-field / general-value validity (e.g. stage ordering) is left to the WARP-V compile,
        // matching the UI. Setting `general.depth` re-derives default pipeline stages (as in the
        // UI), so to customise stages either omit depth or set it in a separate, earlier call.
        // Returns { applied, rejected } describing what took effect.
        const generalKeys = new Set([
            "warpVVersion", "isa", "isaExtensions", "depth",
            "formattingSettings", "customProgramEnabled", "customInstructionsEnabled", "programEntry"
        ])
        const offSetConfig = registerPaneMethod("setConfig", (patch) => {
            if (!patch || typeof patch !== "object") {
                return {error: "setConfig expects an object { general?, pipeline?, programText? }"}
            }
            const general = {}
            const pipeline = {}
            let programText
            const rejected = {}
            for (const [k, v] of Object.entries(patch.general || {})) {
                if (generalKeys.has(k)) general[k] = v
                else rejected["general." + k] = "unknown general setting"
            }
            for (const [k, v] of Object.entries(patch.pipeline || {})) {
                const param = ConfigurationParameters.find(p => p.jsonKey === k)
                if (!param) rejected["pipeline." + k] = "unknown pipeline parameter"
                else if (param.validator && !param.validator(v, param)) rejected["pipeline." + k] = "failed validation"
                else pipeline[k] = v
            }
            if (typeof patch.programText === "string") programText = patch.programText
            else if (patch.programText !== undefined) rejected["programText"] = "must be a string"

            ReactDOM.unstable_batchedUpdates(() => {
                if (Object.keys(general).length || Object.keys(pipeline).length) {
                    setConfiguratorGlobalSettings(prev => ({
                        ...prev,
                        generalSettings: {...prev.generalSettings, ...general},
                        settings: {...prev.settings, ...pipeline}
                    }))
                }
                if (programText !== undefined) {
                    setProgramText(programText)
                    // Program edits don't change coreJson, which otherwise gates the preview
                    // recompile; bump the commit key to refresh the preview (as the textarea blur does).
                    setProgramCommitKey(k => k + 1)
                }
            })

            return {
                applied: {
                    general: Object.keys(general),
                    pipeline: Object.keys(pipeline),
                    programText: programText !== undefined
                },
                rejected
            }
        })

        // Return the generated TLV for the current configuration (same source the configurator's
        // preview/"Open in Makerchip" use). Throws (surfaced as an RPC error) if a pipeline value
        // fails m4 translation.
        const offGetTlv = registerPaneMethod("getTlv", () => {
            const {configuratorGlobalSettings: cgs, programText: pt, ceMeta: meta, configuratorCustomProgramName: name} = liveStateRef.current
            const gs = cgs.generalSettings
            const macros = translateJsonToM4Macros({general: gs, pipeline: cgs.settings})
            return getTLVCodeForDefinitions(macros, name, pt, gs.isa, gs, meta)
        })

        postReady()
        return () => { off(); offBuild(); offGetConfig(); offSetConfig(); offGetTlv() }
    }, [])

    function getInitialSettings() {
        const settings = {
            cores: 1
        }
        ConfigurationParameters.forEach(param => settings[param.jsonKey] = param.defaultValue)
        return settings
    }

    return <ChakraProvider theme={theme}>
        <PaneThemeSync/>
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

export const warpVLatestSupportedCommit = "37b7dc46815418c5af746aee0516cba4a403e33b"
export const warpVLatestVersionCommit = "master"
