import React, {useEffect, useState} from 'react';
import {Box, ChakraProvider, theme} from '@chakra-ui/react';
import {Header} from './components/header/Header';
import {Route, Switch} from 'react-router-dom';
import HomePage from './pages/HomePage';
import {getTLVCodeForDefinitions, translateJsonToM4Macros} from './translation/Translation';
import useFetch from './utils/useFetch';
import {ConfigurationParameters} from "./translation/ConfigurationParameters";

function App() {
    const [generalSettings, setGeneralSettings] = useState({
        isa: 'RISCV',
        depth: 4
    });
    const [settings, setSettings] = useState(getInitialSettings());
    const [coreJson, setCoreJson] = useState(null)
    const [macrosForJson, setMacrosForJson] = useState(null)
    const [tlvForJson, setTlvForJson] = useState(null)
    const makerchipFetch = useFetch("https://faas.makerchip.com")
    const [sVForJson, setSVForJson] = useState(null)


    function getInitialSettings() {
        const settings = {
            cores: 1
        }
        ConfigurationParameters.forEach(param => settings[param.jsonKey] = param.defaultValue)
        return settings
    }

    function getSVForTlv(tlv, callback) {
        makerchipFetch.post(
            "/function/sandpiper-faas",
            {
                args: "-i test.tlv -o test.sv --m4out out/m4out",
                responseType: "json",
                sv_url_inc: "true",
                files: {
                    "test.tlv": tlv
                }
            },
            false,
        ).then(data => {
            console.log(data)
           // console.log(data["m4out"])
            setTlvForJson(data["m4out"])
            const verilog = data["test_gen.sv"] + "\n" + data["test.sv"]
            callback(verilog)
        })
    }

    useEffect(() => {
        if (!coreJson) {
            setMacrosForJson(null)
            setTlvForJson(null)
        } else {
            const macros = translateJsonToM4Macros(coreJson)
            const tlv = getTLVCodeForDefinitions(macros)
            setMacrosForJson(tlv.split("\n"))

            const timerTask = setTimeout(() => {
                getSVForTlv(tlv, sv => setSVForJson(sv))
            }, 1000)

            return () => clearTimeout(timerTask)
        }
    }, [coreJson])

    return <ChakraProvider theme={theme}>
        <Box minHeight='480px'>
            <Header/>

            <Box mx={5} overflowWrap>
                <Switch>
                    <Route exact path='/'>
                        <HomePage generalSettings={generalSettings} setGeneralSettings={setGeneralSettings}
                                  settings={settings} setSettings={setSettings}
                                  setCoreJson={setCoreJson} coreJson={coreJson} getSVForTlv={getSVForTlv}
                                  tlvForJson={tlvForJson}
                                  macrosForJson={macrosForJson} sVForJson={sVForJson}/>
                    </Route>
                </Switch>
            </Box>
        </Box>
    </ChakraProvider>;
}

export default App;
