import React, { useState } from "react";
import { Alert, AlertIcon, Box, Heading, Tab, TabList, TabPanel, TabPanels, Tabs, Text } from "@chakra-ui/react";
import { GeneralSettingsForm } from "../forms/GeneralSettingsForm";
import { GenericSettingsFormComponent } from "../forms/GenericSettingsFormComponent";
import { VerilogSettingsForm } from "./VerilogSettingsForm";
import { EnterProgramForm } from "./EnterProgramForm";
import { hazardsParams, pipelineParams } from "./HomePage";

export function ConfigureCpuComponent({
  configuratorGlobalSettings,
  setConfiguratorGlobalSettings,
  formErrors,
  generalSettings,
  onFormattingChange,
  onVersionChange,
  programText,
  setProgramText,
  settings,
  userChangedStages,
  userChangedStages1,
}) {
  const [receivedAsmCode, setReceivedAsmCode] = useState("");

  const receiveAsmCode = (event) => {
    // Check the origin of the event
    // Add your origin check here if needed

    // Access the asm code array from the compiler
    var asmCodeArray = event.data.asmCode;

    // Check if asmCodeArray is defined and is an array
    if (asmCodeArray && Array.isArray(asmCodeArray)) {
        // Convert the array of objects into a string
        var asmCodeString = asmCodeArray.map(instruction => instruction.text).join('\n');

        // Use the asm code string as needed, e.g., display in the code editor
        console.log("ASM code sent from parent window to warp-v");
        
        // Update the state with the received ASM code (if you're using React state)
        setReceivedAsmCode(asmCodeString);
    } else {
        console.warn("Invalid asmCodeArray:", asmCodeArray);
    }
};

// Listen for messages
window.addEventListener("message", receiveAsmCode);


  return (
    <Box mt={5} mb={15} mx="auto" maxW="100vh" pb={10} borderBottomWidth={2}>
      <Heading size="lg" mb={4}>
        Configure your CPU now
      </Heading>
      <Tabs borderWidth={1} borderRadius="lg" p={3} isFitted>
        <TabList className="tab-list">
                <Tab>General</Tab>
                <Tab>Multi-Core</Tab>
                <Tab>Pipeline</Tab>
                <Tab>Components</Tab>
                <Tab>Hazards</Tab>
                <Tab>Memory</Tab>
                <Tab>I/O</Tab>
                <Tab>Verilog</Tab>
                <Tab>Program</Tab>
            </TabList>
            <TabPanels>
                <TabPanel>
                    <GeneralSettingsForm configuratorGlobalSettings={configuratorGlobalSettings}
                                         setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                         formErrors={formErrors}/>
                </TabPanel>
                <TabPanel>
                    <GenericSettingsFormComponent configuratorGlobalSettings={configuratorGlobalSettings}
                                                  setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                                  configurationParametersSubset={(settings["cores"] && settings["cores"] > 1) ? ["cores", "vcs", "prios", "max_packet_size"] : ["cores"]}/>
                </TabPanel>
                <TabPanel>
                    <GenericSettingsFormComponent configuratorGlobalSettings={configuratorGlobalSettings}
                                                  setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                                  configurationParametersSubset={pipelineParams}
                                                  userChangedStages={userChangedStages}
                                                  setUserChangedStages={userChangedStages1}
                                                  mustBeMonotonicallyNonDecreasing={true}/>
                </TabPanel>
                <TabPanel>
                    <GenericSettingsFormComponent configuratorGlobalSettings={configuratorGlobalSettings}
                                                  setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                                  configurationParametersSubset={["branch_pred"]}/>
                </TabPanel>
                <TabPanel>
                    <Alert status="info" mb={5}>
                        <AlertIcon/>
                        EXTRA_*_BUBBLEs (0 or 1). Set to 1 to add a cycle to the replay condition and relax circuit
                        timing. (Not all configurations are valid.)
                    </Alert>

                    <GenericSettingsFormComponent configuratorGlobalSettings={configuratorGlobalSettings}
                                                  setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                                  configurationParametersSubset={hazardsParams}/>
                </TabPanel>
                <TabPanel>
                    <Text>WARP-V currently supports only the CPU core itself, with a small instruction memory and
                        data memory.</Text>
                </TabPanel>
                <TabPanel>
                    <Text>WARP-V does not currently provide any I/O components.</Text>
                </TabPanel>
                <TabPanel>
                    <VerilogSettingsForm generalSettings={generalSettings}
                                         onFormattingChange={onFormattingChange}
                                         onVersionChange={onVersionChange}
                    />
                </TabPanel>
                <TabPanel>
            <EnterProgramForm
              configuratorGlobalSettings={configuratorGlobalSettings}
              setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
              programText={programText}
              setProgramText={setProgramText}
              receivedAsmCode={receivedAsmCode}
            />
          </TabPanel>
        </TabPanels>
      </Tabs>
    </Box>
  );
}