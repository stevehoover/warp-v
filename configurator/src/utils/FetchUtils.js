export function downloadFile(filename, text) {
    const element = document.createElement('a');
    element.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(text));
    element.setAttribute('download', filename);

    element.style.display = 'none';
    document.body.appendChild(element);

    element.click();

    document.body.removeChild(element);
}

export function openInMakerchip(source, setMakerchipOpening) {
    setMakerchipOpening(true)
    const formBody = new URLSearchParams();
    formBody.append("source", source);
    fetch(
        "https://makerchip.com/project/public",
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
            window.open(`https://makerchip.com${url}`)
            setMakerchipOpening(false)
        })
}