import {Box, Button, Code, Heading, HStack, Icon, Image, Link, Text, Tooltip} from '@chakra-ui/react';
import {FaLongArrowAltRight} from 'react-icons/all';
import {useState} from "react";
import {downloadFile, openInMakerchip} from "../utils/FetchUtils";
import {QuestionOutlineIcon} from "@chakra-ui/icons";

const m4fileName = "your_warpv_core_configuration.m4"
const tlvFileName = "your_warpv_core_tlv.tlv"
const systemVerilogFileName = "your_warpv_core_verilog.sv"

export function CoreDetailsComponent({
                                         coreJson,
                                         tlvForJson,
                                         macrosForJson,
                                         sVForJson,
                                         selectedFile,
                                         setSelectedFile,
                                         ...rest
                                     }) {
    const [makerchipOpening, setMakerchipOpening] = useState(false)

    if (!coreJson || !macrosForJson || !sVForJson) return null;

    function handleDisplayButtonClicked(toDisplay) {
        setSelectedFile(toDisplay);
    }

    function handleDownloadSelectedFileClicked() {
        if (selectedFile === "m4") downloadFile(m4fileName, macrosForJson.join("\n"))
        else if (selectedFile === "tlv") downloadFile(tlvFileName, tlvForJson)
        else if (selectedFile === "rtl") downloadFile(systemVerilogFileName, sVForJson)
    }

    function handleOpenInMakerchipClicked() {
        if (selectedFile === "m4") openInMakerchip(macrosForJson.join("\n"), setMakerchipOpening)
        else if (selectedFile === "tlv") openInMakerchip(tlvForJson, setMakerchipOpening)
        else if (selectedFile === "rtl") {
            const modifiedSVToOpen = `\\m4_TLV_version 1d: tl-x.org
\\SV
` + sVForJson.replaceAll(/`include ".+"\s+\/\/\s+From: "(.+)"/gm, `m4_sv_include_url(['$1']) // Originally: $&`)
            // For the generated SV to be used as source code, we must revert the inclusion of files, so they will be download when compiled.

            openInMakerchip(modifiedSVToOpen, setMakerchipOpening)
        }
    }

    return <Box mx='auto' maxW='100vh' mb={30} {...rest}>
        <Box mb={10}>
            <Heading mb={1}>Core Details</Heading>
            <Text mt={5}>Your CPU is constructed in the following steps.</Text>
        </Box>

        <HStack mb={10}>
            <Box>
                <Link onClick={() => handleDisplayButtonClicked('configuration')}>
                    <Image src="paramsboxpreviewleft.png" maxW={150} mx="auto"/>
                </Link>
            </Box>
            <Tooltip label="Your configuration selections are codified.">
                <HStack>
                    <QuestionOutlineIcon/>
                    <Icon as={FaLongArrowAltRight} fontSize="30px"/>
                </HStack>
            </Tooltip>

            <Box>
                <Link onClick={() => handleDisplayButtonClicked('m4')}>
                    <Text borderWidth={1} borderRadius={15} p={2} textAlign='center' mb={2}>Macro Configuration</Text>
                    <Image src="macropreviewlight.png" maxW={150} mx="auto"/>
                </Link>
            </Box>
            <Tooltip label="A macro-preprocessor (M4) applies parameters and instantiates components.">
                <HStack>
                    <QuestionOutlineIcon />
                    <Icon as={FaLongArrowAltRight} fontSize="30px"/>
                </HStack>
            </Tooltip>

            <Box>
                <Link onClick={() => handleDisplayButtonClicked('tlv')}>
                    <Text borderWidth={1} borderRadius={15} p={2} textAlign='center'>Transaction-Level Design
                        (TL-Verilog)</Text>
                    <Image src="tlv-tlvpreview.png" maxW={200} mx="auto"/>
                </Link>
            </Box>
            <Tooltip
                label="Redwood EDA's SandPiper(TM) SaaS Edition expands your Transaction-Level Verilog code into Verilog.">
                <HStack>
                    <QuestionOutlineIcon />
                    <Icon as={FaLongArrowAltRight} fontSize="30px"/>
                </HStack>
            </Tooltip>

            <Box>
                <Link onClick={() => handleDisplayButtonClicked('rtl')}>
                    <Text borderWidth={1} borderRadius={15} p={2} textAlign='center' mb={2}>RTL (Verilog)</Text>
                    <Image src="rtlpreview.png" maxW={200} mx="auto"/>
                </Link>
            </Box>
        </HStack>

        <Box maxW='100vh'>
            {!selectedFile && <Text>No file selected</Text>}
            {selectedFile && <>
                {selectedFile === 'configuration' && <Text mb={2}><b>Core Configuration</b></Text>}
                {selectedFile === 'm4' && <Text mb={2}><b>{m4fileName}</b></Text>}
                {selectedFile === 'tlv' && <Text mb={2}><b>{tlvFileName}</b></Text>}
                {selectedFile === 'rtl' && <Text mb={2}><b>{systemVerilogFileName}</b></Text>}

                <HStack mb={3}>
                    <Button colorScheme="teal" onClick={handleDownloadSelectedFileClicked}>Download File</Button>
                    <Button colorScheme="blue" onClick={handleOpenInMakerchipClicked} isDisabled={makerchipOpening}
                            isLoading={makerchipOpening}>Edit this File in Makerchip (as source code)</Button>
                </HStack>

                <Code as="pre" borderWidth={3} borderRadius={15} p={2} overflow="auto" w="100vh">
                    {selectedFile === 'configuration' &&
                    <Text>Your configuration is determined by your core selections on the homepage.</Text>}
                    {selectedFile === 'm4' && macrosForJson.join("\n")/*.map((line, index) => <Text
                        key={index}>{line}</Text>)*/}
                    {selectedFile === 'tlv' && tlvForJson && tlvForJson/*.split("\n").map((line, index) => <Text
                        key={index}>{line}</Text>)*/}
                    {selectedFile === 'rtl' && sVForJson && sVForJson/*.split("\n").map((line, index) => <Text
                        key={index}>{line}</Text>)*/}
                </Code>
            </>}
        </Box>
    </Box>;
}