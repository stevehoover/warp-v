import React from "react";
import {Box, Checkbox, HStack, Input, Text, Textarea, Stack} from "@chakra-ui/react";

export function EnterProgramForm({
                                     configuratorGlobalSettings,
                                     setConfiguratorGlobalSettings,
                                     programText,
                                     setProgramText,
                                     onProgramBlur
                                 }) {
    return <>
        <Box>
            <Stack direction="column">
            <Checkbox isChecked={configuratorGlobalSettings.generalSettings.customProgramEnabled}
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
                      onBlur={onProgramBlur}
                      fontFamily="'Courier New', monospace"
            />
            <HStack mt={3} align="center">
                <Text whiteSpace="nowrap">Entry label (optional):</Text>
                <Input size="sm" maxW="220px"
                       placeholder="auto (reset:, or main for compiled code)"
                       isDisabled={!configuratorGlobalSettings.generalSettings.customProgramEnabled}
                       value={configuratorGlobalSettings.generalSettings.programEntry || ""}
                       onChange={e => setConfiguratorGlobalSettings({
                           ...configuratorGlobalSettings,
                           generalSettings: {
                               ...configuratorGlobalSettings.generalSettings,
                               programEntry: e.target.value
                           }
                       })}
                       onBlur={onProgramBlur}
                       fontFamily="'Courier New', monospace"
                />
            </HStack>
            <Text mt={1} fontSize="sm" color="gray.500">
                Runs the program from this label via a crt0 preamble; the label's integer return
                signals pass (0) / fail (non-0). Leave blank to auto-detect. For a gfortran
                <code> integer function chk()</code>, use <code>chk_</code>.
            </Text>
        </Box>
    </>
}