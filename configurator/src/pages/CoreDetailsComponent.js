import {Box, Code, Heading, HStack, Icon, Image, Link, Text} from '@chakra-ui/react';
import {BsArrowRight} from 'react-icons/all';
import {useState} from 'react';

export function CoreDetailsComponent({coreJson, tlvForJson, macrosForJson, sVForJson}) {
    const [selectedFile, setSelectedFile] = useState();
    if (!coreJson || !macrosForJson || !sVForJson) return null;

    function handleDisplayButtonClicked(toDisplay) {
        setSelectedFile(toDisplay);
    }

    return <Box mx='auto' maxW='85vh' mb={30}>
        <Box mb={10}>
            <Heading mb={1}>Core Details</Heading>
            <Text mt={5}>Your CPU is constructed in the following steps.</Text>
            <Text> After generation, any of these can be taken as source and modified by hand.</Text>
        </Box>

        <HStack mb={10}>
            <Box>
                <Link onClick={() => handleDisplayButtonClicked('configuration')}>
                    <Text borderWidth={1} borderRadius={15} p={2} textAlign='center' mb={2}>UI Configuration</Text>
                    <Image src="paramboxpreview.png" maxW={250} mx="auto"/>
                </Link>
            </Box>
            <Icon as={BsArrowRight}/>

            <Box>
                <Link onClick={() => handleDisplayButtonClicked('m4')}>
                    <Text borderWidth={1} borderRadius={15} p={2} textAlign='center' mb={2}>Macro Configuration</Text>
                    <Image src="macropreview.png" maxW={150} mx="auto"/>
                </Link>
            </Box>
            <Icon as={BsArrowRight}/>

            <Box>
                <Link onClick={() => handleDisplayButtonClicked('tlv')}>
                    <Text borderWidth={1} borderRadius={15} p={2} textAlign='center'>Transaction-Level Design
                        (TL-Verilog)</Text>
                    <Image src="tlv-tlvpreview.png" maxW={200} mx="auto"/>
                </Link>
            </Box>
            <Icon as={BsArrowRight}/>

            <Box>
                <Link onClick={() => handleDisplayButtonClicked('rtl')}>
                    <Text borderWidth={1} borderRadius={15} p={2} textAlign='center' mb={2}>RTL (Verilog)</Text>
                    <Image src="rtlpreview.png" maxW={200} mx="auto"/>
                </Link>
            </Box>
        </HStack>

        <Box maxW='85vh'>
            {!selectedFile && <Text>No file selected</Text>}
            {selectedFile && <>
                {selectedFile === 'configuration' && <Text mb={2}><b>Core Configuration</b></Text>}
                {selectedFile === 'm4' && <Text mb={2}><b>your_warpv_core_configuration.m4</b></Text>}
                {selectedFile === 'tlv' && <Text mb={2}><b>your_warpv_core_tlv.tlv</b></Text>}
                {selectedFile === 'rtl' && <Text mb={2}><b>your_warpv_core_verilog.sv</b></Text>}

                <Code as="pre" borderWidth={3} borderRadius={15} p={2} overflow="auto" maxW="85vh">
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