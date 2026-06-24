import {useEffect, useRef} from "react";
import {Box} from "@chakra-ui/react";

// Host serving the Makerchip IDE plugin. Keep in sync with the host used in FetchUtils.
export const MAKERCHIP_HOST = "https://beta.makerchip.com";

// The plugin is published as an ES module. We load it once via an injected
// module script (rather than a bundler import) so the cross-origin URL is not
// processed by webpack.
let pluginModulePromise = null;

function loadPluginModule() {
    if (pluginModulePromise) return pluginModulePromise;
    pluginModulePromise = new Promise((resolve, reject) => {
        const callbackName = "__makerchipPluginModuleLoaded";
        window[callbackName] = (IdePlugin) => {
            delete window[callbackName];
            resolve(IdePlugin);
        };
        const script = document.createElement("script");
        script.type = "module";
        script.textContent =
            `import IdePlugin from '${MAKERCHIP_HOST}/dist/makerchip-plugin.js';\n` +
            `window.${callbackName}(IdePlugin);`;
        script.onerror = () => reject(new Error("Failed to load the Makerchip plugin module"));
        document.head.appendChild(script);
    });
    return pluginModulePromise;
}

let instanceCounter = 0;

/**
 * Embeds an interactive Makerchip IDE.
 *
 * @param onReady Called with the plugin instance once the IDE is initialized.
 *                The instance exposes `setCode(code, readOnly)`, `compile(code)`, etc.
 * @param code Optional initial TL-Verilog source to load. Instantiation is deferred until
 *             this is provided (non-null) so the IDE seeds with this code rather than its
 *             own default. Later changes are ignored (the IDE is only created once).
 * @param defaultPane Optional name of a pane (e.g. "Viz") to activate once the IDE is ready.
 */
export function MakerchipPlugin({onReady, code, defaultPane, ...rest}) {
    const containerId = useRef(`makerchip-plugin-${++instanceCounter}`).current;
    const startedRef = useRef(false);
    // Track the latest code so the IDE can be seeded with the settled config once the module loads.
    const codeRef = useRef(code);
    codeRef.current = code;
    const hasCode = code != null;

    useEffect(() => {
        // Create the IDE exactly once, as soon as initial code is available. Keyed on `hasCode`
        // (a stable boolean) rather than `code` so that later config changes don't tear down the
        // in-flight creation and discard the ready instance.
        if (startedRef.current || !hasCode) return;
        startedRef.current = true;
        loadPluginModule()
            .then((IdePlugin) => new IdePlugin(containerId, {hasEditor: true, code: codeRef.current}))
            .then((instance) => {
                if (defaultPane) {
                    // onReady fires once the IDE iframe is fully loaded (after the initial code load).
                    instance.onReady = () => instance.activatePane(defaultPane)
                        .catch((err) => console.error(`Failed to activate pane '${defaultPane}':`, err));
                }
                if (onReady) onReady(instance);
            })
            .catch((err) => console.error("Failed to initialize the Makerchip plugin:", err));
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [hasCode]);

    return <Box id={containerId} w="100%" {...rest}/>;
}
