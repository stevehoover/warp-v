import {
    Button,
    Modal,
    ModalBody,
    ModalCloseButton,
    ModalContent,
    ModalFooter,
    ModalHeader,
    ModalOverlay,
    Text
} from "@chakra-ui/react";

export function downloadOrCopyFile(copy, filename, text) {
    if (copy) {
        navigator.clipboard.writeText(text);
    } else {
        const element = document.createElement('a');
        element.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(text));
        element.setAttribute('download', filename);

        element.style.display = 'none';
        document.body.appendChild(element);

        element.click();

        document.body.removeChild(element);
    }
}

export function OpenInMakerchipModal({disclosure, url}) {
    const {isOpen, onClose} = disclosure
    return <Modal isOpen={isOpen} onClose={onClose}>
        <ModalOverlay/>
        <ModalContent>
            <ModalHeader>Your project is ready.</ModalHeader>
            <ModalCloseButton/>
            <ModalBody>
                <Text>To avoid this confirmation in the future, disable your browser's pop-up blocker for this
                    site.</Text>
            </ModalBody>

            <ModalFooter>
                <Button variant="ghost" mr={3} onClick={onClose}>Close</Button>
                <Button colorScheme="blue" onClick={() => window.open(url)}>Open in Makerchip</Button>
            </ModalFooter>
        </ModalContent>
    </Modal>
}

function encodeBase64Url(str) {
    try {
        const bytes = new TextEncoder().encode(str);
        // Handle large files by processing in chunks to avoid spread operator limits
        const chunkSize = 32768;
        let binary = '';
        for (let i = 0; i < bytes.length; i += chunkSize) {
            const chunk = bytes.slice(i, i + chunkSize);
            binary += String.fromCharCode.apply(null, chunk);
        }
        return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    } catch (error) {
        console.error('Error encoding to base64url:', error);
        throw new Error('File is too large to encode in URL. Please use a smaller file or try TLV instead.');
    }
}

export function openInMakerchip(source, setMakerchipOpening, setDisclosureAndUrl) {
    setMakerchipOpening(true)
    try {
        const encoded = encodeBase64Url(source);
        const url = `https://beta.makerchip.com/ide#code=${encoded}`;
        
        // Check URL length (most browsers support at least 2MB, but warn if over 1MB)
        if (url.length > 1000000) {
            console.warn(`URL length is ${url.length} characters - this may be too large for some browsers`);
        }
        
        openInNewTabOrFallBack(url, "_blank", setDisclosureAndUrl);
    } catch (error) {
        alert(error.message || 'Failed to open in Makerchip. The file may be too large.');
    } finally {
        setMakerchipOpening(false);
    }
}

function openInNewTabOrFallBack(urlToRedirectTo, target, setDisclosureAndUrl) {
    const newWindow = window.open(urlToRedirectTo, target)

    if (!newWindow || newWindow.closed || typeof newWindow.closed == 'undefined') {
        setDisclosureAndUrl(urlToRedirectTo)
    } // fallback
}
