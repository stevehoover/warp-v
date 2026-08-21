// Minimal client for the Makerchip "connected third-party pane" PaneChannel protocol
// (postMessage, protocol version 1). Lets the configurator, when loaded as a Makerchip
// pane, subscribe to bus events (e.g. `sourceAsm` from a Compiler Explorer pane), call
// whitelisted IDE operations over RPC (e.g. `loadCode`), and expose its own methods for the
// host IDE to call inward (e.g. `build`, via the host's `callPane` Plugin API).
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
const paneMethods = new Map();         // method -> handler (inbound host->pane RPC)

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
        } else if (msg.kind === "rpc-call") {
            handleInboundRpc(msg);
        } else if (typeof msg.type === "string") {
            const handlers = busHandlers.get(msg.type);
            if (handlers) for (const fn of handlers) fn(msg.payload, msg);
        }
    });
}

// Service a host->pane RPC request ({kind:"rpc-call", id, method, args}) by dispatching to a
// handler registered via registerPaneMethod, and reply with {kind:"rpc-call-result", id, result}
// (or {kind:"rpc-call-error", id, error}). Only fired when the pane declared channel.rpc on the
// host side (see mono BusParticipant); the id correlates the reply.
function handleInboundRpc(msg) {
    const {id, method, args} = msg;
    Promise.resolve()
        .then(() => {
            const handler = paneMethods.get(method);
            if (!handler) throw new Error(`No pane method '${method}'`);
            return handler(...(Array.isArray(args) ? args : []));
        })
        .then(result => {
            window.parent.postMessage({v: V, kind: "rpc-call-result", id, result}, TARGET_ORIGIN);
        })
        .catch(err => {
            window.parent.postMessage({v: V, kind: "rpc-call-error", id, error: err?.message ?? String(err)}, TARGET_ORIGIN);
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

/**
 * Expose a pane method the host IDE can invoke inward via its `callPane` Plugin API (host->pane
 * RPC). `handler(...args)` may return a value or a Promise; its (awaited) result is returned to
 * the host. Requires the pane to have been opened with `channel.rpc: true`. Registering the same
 * method again replaces the handler.
 * @returns an unregister function.
 */
export function registerPaneMethod(method, handler) {
    attach();
    paneMethods.set(method, handler);
    return () => { if (paneMethods.get(method) === handler) paneMethods.delete(method); };
}
