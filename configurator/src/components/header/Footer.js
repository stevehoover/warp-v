import {Box, Icon, Image, Link} from "@chakra-ui/react";
import * as React from "react";
import {MdOpenInNew} from "react-icons/all";

export function Footer() {
    return <>
        <Box textAlign="center" mt={13} mb={10} mx="auto">
            <FooterLink to="https://github.com/stevehoover/warp-v" mr={30}>
                Dig deeper in the github repository <Icon as={MdOpenInNew}/>
            </FooterLink>

            <FooterLink to="https://www.redwoodeda.com">

                Courtesy of<Image mb={7} display="inline" src="rwedaLogo2.svg" w="110px"/> <Icon as={MdOpenInNew}/>
            </FooterLink>
        </Box>
    </>
}

function FooterLink({to, children, ...rest}) {
    return <Link href={to}
                 fontWeight='bold'
                 fontSize='lg'
                 _hover={{
                     bg: 'blackAlpha.200',
                 }}
                 target="_blank"
                 {...rest}
    >{children}</Link>
}