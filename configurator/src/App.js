import React, {useEffect, useState} from 'react';
import {Box, ChakraProvider, theme, useToast} from '@chakra-ui/react';
import {Route, Switch} from 'react-router-dom';
import HomePage from './pages/HomePage';
import useFetch from './utils/useFetch';
import {ConfigurationParameters} from "./translation/ConfigurationParameters";
import {translateParametersToJson} from "./translation/Translation";
import {Footer} from "./components/header/Footer";
import {Header} from "./components/header/Header";

function App() {
    const makerchipFetch = useFetch("https://faas.makerchip.com")

    const [configuratorGlobalSettings, setConfiguratorGlobalSettings] = useState({
        settings: getInitialSettings(),
        coreJson: null,
        generalSettings: {
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

    const toast = useToast()
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
                args: `-i test.tlv -o test.sv --m4out out/m4out ${configuratorGlobalSettings.generalSettings.formattingSettings.filter(setting => setting === "--fmtNoSource").join(" ")}`,
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
        if (data["out/m4out"]) setTlvForJson(data["out/m4out"].replaceAll("\n\n", "\n")) // remove some extra spacing by removing extra newlines
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

    return <ChakraProvider theme={theme}>
        <Box minHeight='480px'>
            {<Header/>}

            <Box mx={5} overflowWrap>
                <Switch>
                    <Route exact path='/'>
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
                        />
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
