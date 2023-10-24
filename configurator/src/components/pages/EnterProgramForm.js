import React from "react";
import {Box, Checkbox, Text, Textarea, Stack} from "@chakra-ui/react";

export function EnterProgramForm({
                                     configuratorGlobalSettings,
                                     setConfiguratorGlobalSettings,
                                     programText,
                                     setProgramText
                                 }) {
    return <>
        <Box>
            <Stack direction="column">
            <Checkbox value={configuratorGlobalSettings.generalSettings.customProgramEnabled}
                      isDisabled={configuratorGlobalSettings.generalSettings.isa === "MIPSI"}
                      onChange={e => setConfiguratorGlobalSettings({
                          ...configuratorGlobalSettings,
                          generalSettings: {
                              ...configuratorGlobalSettings.generalSettings,
                              customProgramEnabled: e.target.checked
                          }
                      })}>Enable custom program</Checkbox>
            <Checkbox mb={5} value={configuratorGlobalSettings.generalSettings.customInstructionsEnabled}
                    isDisabled={configuratorGlobalSettings.generalSettings.isa === "MIPSI"}
                    onChange={e => setConfiguratorGlobalSettings({
                        ...configuratorGlobalSettings,
                        generalSettings: {
                            ...configuratorGlobalSettings.generalSettings,
                            customInstructionsEnabled: e.target.checked
                        }
                    })}>Include template for custom instructions</Checkbox>
            </Stack>


            <Text mb={2}>
                Here, you can provide your own assembly program that will be hardcoded into the instruction memory
                of
                your core.
                The syntax roughly mimics that defined by the RISC-V ISA, but not exactly.
            </Text>
            <Textarea rows={programText.split("\n").length}
                      isDisabled={!configuratorGlobalSettings.generalSettings.customProgramEnabled}
                      value={programText}
                      onChange={e => setProgramText(e.target.value)}
                      fontFamily="'Courier New', monospace"
            />
        </Box>
    </>
}