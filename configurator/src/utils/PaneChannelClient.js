// Minimal client for the Makerchip "connected third-party pane" PaneChannel protocol
// (postMessage, protocol version 1). Lets the configurator, when loaded as a Makerchip
// pane, subscribe to bus events (e.g. `sourceAsm` from a Compiler Explorer pane) and call
// whitelisted IDE operations over RPC (e.g. `compile`).
//
// See mono doc-src/plugin/Third_Party_Pane_API.md. The IDE stamps/validates `source`; a
// pane only ever talks to its own `window.parent`.

const V = 1;
const TARGET_ORIGIN = "*";

let attached = false;
let readySent = false;
let rpcSeq = 0;
const rpcPending = new Map();          // id -> {resolve, reject}
const busHandlers = new Map();         // type -> Set(handler)

/** True when running inside a frame (i.e. potentially as a Makerchip pane). */
export function isFramed() {
    return typeof window !== "undefined" && window.parent !== window;
}

// Attach the single window message listener (idempotent; safe under React StrictMode).
function attach() {
    if (attached || !isFramed()) return;
    attached = true;
    window.addEventListener("message", event => {
        if (event.source !== window.parent) return;
        const msg = event.data;
        if (!msg || typeof msg !== "object" || msg.v !== V) return;
        if (msg.kind === "rpc-result") {
            rpcPending.get(msg.id)?.resolve(msg.result);
            rpcPending.delete(msg.id);
        } else if (msg.kind === "rpc-error") {
            rpcPending.get(msg.id)?.reject(new Error(msg.error));
            rpcPending.delete(msg.id);
        } else if (typeof msg.type === "string") {
            const handlers = busHandlers.get(msg.type);
            if (handlers) for (const fn of handlers) fn(msg.payload, msg);
        }
    });
}

/**
 * Announce readiness so the IDE flushes any queued inbound event deliveries. Idempotent.
 */
export function postReady() {
    if (!isFramed()) return;
    attach();
    if (readySent) return;
    readySent = true;
    window.parent.postMessage({v: V, type: "ready"}, TARGET_ORIGIN);
}

/**
 * Subscribe to a bus event type. `handler(payload, envelope)` is called for each delivery.
 * @returns an unsubscribe function.
 */
export function onPaneEvent(type, handler) {
    attach();
    let handlers = busHandlers.get(type);
    if (!handlers) {
        handlers = new Set();
        busHandlers.set(type, handlers);
    }
    handlers.add(handler);
    return () => handlers.delete(handler);
}

/**
 * Call a whitelisted IDE RPC method. Resolves with its result, rejects on error.
 */
export function callIde(method, ...args) {
    attach();
    const id = ++rpcSeq;
    return new Promise((resolve, reject) => {
        if (!isFramed()) {
            reject(new Error("callIde: not running as a pane (no parent frame)"));
            return;
        }
        rpcPending.set(id, {resolve, reject});
        // `target: "ide"` addresses the RPC destination; only "ide" is supported today.
        window.parent.postMessage({v: V, kind: "rpc", id, target: "ide", method, args}, TARGET_ORIGIN);
    });
}
