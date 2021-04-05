import {useEffect, useState} from "react";

export default function useFetch(baseUrl) {
    const [loading, setLoading] = useState(true);
    const [loadingTime, setLoadingTime] = useState(Date.now())

    useEffect(() => {
        if (!loading && loadingTime !== null) setLoadingTime(null)
    }, [loading])


    function get(url) {
        return new Promise((resolve, reject) => {
            fetch(baseUrl + url)
                .then(response => response.json())
                .then(data => {
                    if (!data) {
                        setLoading(false);
                        return reject(data);
                    }
                    setLoading(false);
                    resolve(data);
                })
                .catch(error => {
                    setLoading(false);
                    reject(error);
                });
        });
    }

    function post(url, body, formData = false, cors = false) {
        const fetchBody = !formData ? JSON.stringify(body) : new URLSearchParams()
        if (formData) {
            for (const [key, value] of Object.entries(body)) {
                fetchBody.append(key, value);
            }
        }
        return new Promise((resolve, reject) => {
            fetch(baseUrl + url, {
                ...{
                    method: "post",
                    body: fetchBody,
                    headers: {
                        "Content-Type": "text/plain"
                    },
                    mode: "cors"
                },
            })
                .then(response => {
                    const data = response.json()
                    if (!data) {
                        setLoading(false);
                        return reject(data);
                    }
                    setLoading(false);
                    if (response.status >= 400 && response.status < 600) reject(data)
                    else resolve(data);
                })
                .catch(error => {
                    setLoading(false);
                    reject(error);
                });
        });
    }

    return { get, post, loading, loadingTime: loadingTime };
};
