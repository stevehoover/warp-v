import { chakra, useColorModeValue } from '@chakra-ui/react';
import * as React from 'react';

function DesktopNavLink(props) {
  return (
    <chakra.a
      fontWeight='medium'
      display='flex'
      alignItems='center'
      justifyContent='center'
      borderBottom='2px'
      borderColor='transparent'
      transition='all 0.2s'
      _hover={{
        borderColor: 'currentcolor',
        color: useColorModeValue('blue.600', 'blue.200'),
      }}
      {...props}
    />
  );
}

function MobileNavLink(props) {
  return (
    <chakra.a
      display='block'
      textAlign='center'
      fontWeight='bold'
      py='5'
      fontSize='lg'
      color='white'
      w='full'
      _hover={{
        bg: 'blackAlpha.200',
      }}
      {...props}
    />
  );
}

export const NavLink = {
  Mobile: MobileNavLink,
  Desktop: DesktopNavLink,
};
