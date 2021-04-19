import { Box, Flex, useColorModeValue, useColorModeValue as mode, VisuallyHidden } from '@chakra-ui/react';
import { Logo } from './Logo';
import { NavContent } from './NavContent';
import React from 'react';

export function Header() {
  return <Box mt={2} as='header' height='16' bg={mode('white', 'gray.800')} position='relative'>
    <Box
      height='100%'
      maxW='7xl'
      mx='auto'
      ps={{ base: '6', md: '8' }}
      pe={{ base: '5', md: '0' }}
    >
      <Flex
        as='nav'
        aria-label='Site navigation'
        align='center'
        height='100%'
      >
        <Box as='a' href='/' rel='home'>
          <VisuallyHidden>Redwood EDA</VisuallyHidden>
          <Logo h='6' iconColor={useColorModeValue('blue.600', 'blue.200')} />
        </Box>
        <NavContent.Desktop ml={10} display={{ base: 'none', md: 'flex' }} />
        <NavContent.Mobile display={{ base: 'flex', md: 'none' }} />
      </Flex>
    </Box>
  </Box>;
}