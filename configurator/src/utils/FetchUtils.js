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

export function openInMakerchip(source, setMakerchipOpening, setDisclosureAndUrl) {
    setMakerchipOpening(true)
    const formBody = new URLSearchParams();
    formBody.append("source", source);
    fetch(
        "https://warp-v.makerchip.com/project/public",
        {
            method: 'POST',
            body: formBody,
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded'
            }
        }
    )
        .then(resp => resp.json())
        .then(json => {
            const url = json.url
            openInNewTabOrFallBack(`https://warp-v.makerchip.com${url}`, "_blank", setDisclosureAndUrl)
            setMakerchipOpening(false)
        })
}

function openInNewTabOrFallBack(urlToRedirectTo, target, setDisclosureAndUrl) {
    const newWindow = window.open(urlToRedirectTo, target)

    if (!newWindow || newWindow.closed || typeof newWindow.closed == 'undefined') {
        setDisclosureAndUrl(urlToRedirectTo)
    } // fallback
}
