import React from "react";
import {Box, FormControl, FormLabel, Input, Text, Textarea, VStack} from "@chakra-ui/react";

export function EnterProgramForm({
                                     configuratorCustomProgramName,
                                     setConfiguratorCustomProgramName,
                                     programText,
                                     setProgramText
                                 }) {
    return <>
        <VStack spacing={4}>
            <FormControl>
                <FormLabel>Your Program Name</FormLabel>
                <Input value={configuratorCustomProgramName}
                       onChange={e => setConfiguratorCustomProgramName(e.target.value.replaceAll(" ", ""))}
                       placeholder="Enter program name..."/>
            </FormControl>

            <Box>
                <Text mb={2}>
                    Here, you can provide your own assembly program that will be hardcoded into the instruction memory
                    of
                    your core.
                    The syntax roughly mimics that defined by the RISC-V ISA, but not exactly.
                </Text>
                <Textarea rows={programText.split("\n").length}
                          value={programText}
                          onChange={e => setProgramText(e.target.value)}
                          fontFamily="'Courier New', monospace"
                />
            </Box>
        </VStack>
    </>
}