import {Box, Button, Code, Container, Heading, HStack, Icon, Image, Link, Text, Tooltip} from '@chakra-ui/react';
import {FaLongArrowAltRight} from 'react-icons/all';
import {useState} from "react";
import {downloadOrCopyFile, openInMakerchip} from "../../utils/FetchUtils";
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
                                         setDiscloureAndUrl,
                                         ...rest
                                     }) {
    const [makerchipOpening, setMakerchipOpening] = useState(false)
    if (!coreJson || !macrosForJson || !sVForJson) return null;


    function handleDisplayButtonClicked(toDisplay) {
        setSelectedFile(toDisplay);
    }

    function handleDownloadSelectedFileClicked() {
        handleDownloadOrCopySelectedFileClicked(false);
    }

    function handleCopySelectedFileClicked() {
        handleDownloadOrCopySelectedFileClicked(true);
    }

    function handleDownloadOrCopySelectedFileClicked(copy) {
        if (selectedFile === "m4") downloadOrCopyFile(copy, m4fileName, macrosForJson.join("\n"))
        else if (selectedFile === "tlv") downloadOrCopyFile(copy, tlvFileName, tlvForJson)
        else if (selectedFile === "rtl") downloadOrCopyFile(copy, systemVerilogFileName, sVForJson)
    }

    function replaceImports(old) {
        return old.replaceAll(/`include ".+"\s+\/\/\s+From: "(.+)"/gm, `m4_sv_include_url(['$1']) // Originally: $&`)
        // .replaceAll(/`include "(.+)"/gm, `m4_sv_include_url(['$1']) // Originally: $&`)
    }

    function handleOpenInMakerchipClicked() {
        if (selectedFile === "m4") openInMakerchip(macrosForJson.join("\n"), setMakerchipOpening, setDiscloureAndUrl)
        else if (selectedFile === "tlv") {
            openInMakerchip(
                replaceImports(tlvForJson)
                    .replace("\\TLV_version", "\\m5_TLV_version"),
                setMakerchipOpening,
                setDiscloureAndUrl
            )
        } else if (selectedFile === "rtl") {
            const modifiedSVToOpen = `\\m5_TLV_version 1d: tl-x.org
\\SV
` + sVForJson.replaceAll(/`include ".+"\s+\/\/\s+From: "(.+)"/gm, `m4_sv_include_url(['$1']) // Originally: $&`)
            // For the generated SV to be used as source code, we must revert the inclusion of files, so they will be download when compiled.

            openInMakerchip(replaceImports(modifiedSVToOpen), setMakerchipOpening, setDiscloureAndUrl)
        }
    }

    return <Box mx='auto' maxW='100vh' mb={30} {...rest}>
        <Box mb={3}>
            <Heading size="lg">Core Details</Heading>
            <Text mt={1}>Your CPU is constructed in the following steps.</Text>
        </Box>

        <HStack mb={10} flexWrap="wrap">
            <HStack mb={5} mx="auto">
                <Link onClick={() => handleDisplayButtonClicked('m4')}>
                    <Text backgroundColor={selectedFile === "m4" ? "#CDCDCD" : null} borderWidth={1}
                          borderRadius={15} p={2} textAlign='center' mb={2}>Macro Configuration</Text>
                    <Image src="macropreviewlight.png" maxW={200} mx="auto"/>
                </Link>
                <Tooltip label="A macro-preprocessor (M4) applies parameters and instantiates components.">
                    <Container centerContent mx={0} px={0} width={30}>
                        <Icon as={FaLongArrowAltRight} fontSize="30px"/>
                        <QuestionOutlineIcon mx="auto" marginLeft="auto"/>
                    </Container>
                </Tooltip>
            </HStack>

            <HStack mb={5} mx="auto">
                <Link onClick={() => handleDisplayButtonClicked('tlv')}>
                    <Text backgroundColor={selectedFile === "tlv" ? "#CDCDCD" : null} borderWidth={1} borderRadius={15}
                          p={1} textAlign='center'>Transaction-Level Design
                        (TL-Verilog)</Text>
                    <Image src="tlv-tlvpreview.png" maxW={200} mx="auto"/>
                </Link>
                <Tooltip
                    label="Redwood EDA, LLC's SandPiper(TM) SaaS Edition expands your Transaction-Level Verilog code into Verilog.">
                    <Container centerContent mx={0} px={0} width={30}>
                        <Icon as={FaLongArrowAltRight} fontSize="30px"/>
                        <QuestionOutlineIcon mx="auto" marginLeft="auto"/>
                    </Container>
                </Tooltip>
            </HStack>

            <HStack mx="auto">
                <Link onClick={() => handleDisplayButtonClicked('rtl')}>
                    <Text backgroundColor={selectedFile === "rtl" ? "#CDCDCD" : null} borderWidth={1} borderRadius={15}
                          p={2} textAlign='center' mb={2}>RTL (Verilog)</Text>
                    <Image src="rtlpreview.png" maxW={200} mx="auto"/>
                </Link>
            </HStack>
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
                            isLoading={makerchipOpening}>Edit in Makerchip as Source</Button>
                    <Button colorScheme="teal" onClick={handleCopySelectedFileClicked}>Copy Code</Button>
                </HStack>

                <Code as="pre" borderWidth={3} borderRadius={15} p={2} overflow="auto" w="100vh" maxW="100%">
                    {selectedFile === 'configuration' &&
                    <Text>Your configuration is determined by your core selections on the homepage.</Text>}
                    {selectedFile === 'm4' && macrosForJson.join("\n")/*.map((line, index) => <Text
                        key={index}>{line}</Text>)*/}
                    {selectedFile === 'tlv' && tlvForJson && replaceImports(tlvForJson)/*.split("\n").map((line, index) => <Text
                        key={index}>{line}</Text>)*/}
                    {selectedFile === 'rtl' && sVForJson && replaceImports(sVForJson)/*.split("\n").map((line, index) => <Text
                        key={index}>{line}</Text>)*/}
                </Code>
            </>}
        </Box>
    </Box>;
}
