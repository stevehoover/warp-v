import {Box, Container, Icon, Image, Link} from "@chakra-ui/react";
import * as React from "react";
import {MdOpenInNew} from "react-icons/all";

export function Footer() {
    return <>
        <Box textAlign="center" mt={13} mb={2} mx="auto">
            <FooterLink to="https://github.com/stevehoover/warp-v" mr={30}>
                Dig deeper in the github repository <Icon as={MdOpenInNew}/>
            </FooterLink>

            <FooterLink to="https://www.redwoodeda.com">
                Courtesy of Redwood EDA <Icon as={MdOpenInNew}/>
            </FooterLink>
        </Box>
        <Container centerContent mb={5}>
            <Link href="https://www.redwoodeda.com" target="_blank">
                <Image src="rwedaLogo2.svg" w={150} />
            </Link>
        </Container>
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