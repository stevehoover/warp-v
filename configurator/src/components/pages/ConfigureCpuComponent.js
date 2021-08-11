import {Alert, AlertIcon, Box, Heading, Tab, TabList, TabPanel, TabPanels, Tabs, Text} from "@chakra-ui/react";
import {GeneralSettingsForm} from "../forms/GeneralSettingsForm";
import {GenericSettingsFormComponent} from "../forms/GenericSettingsFormComponent";
import {VerilogSettingsForm} from "./VerilogSettingsForm";
import {EnterProgramForm} from "./EnterProgramForm";
import React from "react";
import {hazardsParams, pipelineParams} from "./HomePage";

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
                                          userChangedStages1
                                      }) {
    return <Box mt={5} mb={15} mx='auto' maxW='100vh' pb={10} borderBottomWidth={2}>

        <Heading size="lg" mb={4}>Configure your CPU now</Heading>
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
                    <EnterProgramForm configuratorGlobalSettings={configuratorGlobalSettings}
                                      setConfiguratorGlobalSettings={setConfiguratorGlobalSettings}
                                      programText={programText} setProgramText={setProgramText}
                    />
                </TabPanel>
            </TabPanels>
        </Tabs>
    </Box>;
}