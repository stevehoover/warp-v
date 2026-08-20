# WARP-V Configurator

The web application behind [warp-v.org](https://warp-v.org) — an interactive tool for building a
custom [WARP-V](https://github.com/stevehoover/warp-v) RISC-V/MIPS CPU core and generating its
[TL-Verilog](https://tl-x.org) source.

Point-and-click through the CPU parameters (ISA, pipeline depth, branch prediction, memory sizes,
etc.), enter a test program, and the configurator generates the corresponding WARP-V TL-Verilog and
opens it in [Makerchip](https://makerchip.com) for simulation and inspection.

## Features

- **Interactive CPU configuration** — choose the ISA, number of pipeline stages, and other core
  parameters through a guided form.
- **Custom program entry** — supply your own assembly/machine-code test program or use a built-in
  default.
- **TL-Verilog generation** — produces ready-to-simulate WARP-V TL-Verilog from the chosen settings.
- **Makerchip integration** — opens the generated core in the Makerchip IDE to compile, simulate, and
  visualize.
- **Embeddable pane mode** — the configurator can run framed as a third-party pane inside Makerchip,
  where it exchanges data with sibling panes (e.g. loading assembly from a
  [Compiler Explorer](https://godbolt.org) pane) and drives compilation in the host IDE. See
  [Pane / embedded mode](#pane--embedded-mode).

## Tech stack

- [React 17](https://reactjs.org/) (bootstrapped with [Create React App](https://github.com/facebook/create-react-app), `react-scripts` 4)
- [Chakra UI](https://chakra-ui.com/) for components and theming
- [React Router](https://reactrouter.com/) for navigation

## Getting started

Requires [Node.js](https://nodejs.org/) and [Yarn](https://yarnpkg.com/).

```sh
yarn         # install dependencies (run once)
yarn start   # start the dev server at http://localhost:3009
```

The page reloads on edits, and lint errors appear in the console.

> **Note:** the `start` and `build` scripts set `NODE_OPTIONS=--openssl-legacy-provider` for
> compatibility with newer Node versions. The dev server port is pinned to `3009` via `.env`
> (`PORT=3009`) to avoid clashing with other local dev servers that use the Create React App
> default of `3000`.

## Scripts

| Command | Description |
| --- | --- |
| `yarn start` | Run the app in development mode at [localhost:3009](http://localhost:3009) (port pinned via `.env`). |
| `yarn build` | Produce an optimized production build in `build/`. |
| `yarn test` | Launch the test runner in interactive watch mode. |
| `yarn eject` | Eject from Create React App (one-way; not normally needed). |

## Project structure

```
src/
  App.js                     App root, routing, and pane-mode wiring
  index.js                   React entry point
  components/
    pages/                   Main configurator screens
      HomePage.js            Landing page
      WarpVPageBase.js       Core configurator layout / TL-Verilog generation
      ConfigureCpuComponent.js
      CoreDetailsComponent.js
      EnterProgramForm.js
      VerilogSettingsForm.js
    forms/                   Reusable form controls
    header/                  Header / navigation
    translation/             Settings → TL-Verilog translation
  utils/
    MakerchipPlugin.js       Launches / drives an embedded Makerchip instance
    PaneChannelClient.js     Third-party pane communication channel client
    FetchUtils.js, useFetch.js
```

## Pane / embedded mode

When the configurator is loaded inside a Makerchip iframe pane (detected via
[`isFramed()`](src/utils/PaneChannelClient.js)) it adapts its UI and behavior:

- Non-essential landing content (logo/video, embedded Makerchip preview, etc.) is hidden so the
  configurator form fills the pane.
- It subscribes to the pane communication channel and can receive a `sourceAsm` event — for example,
  assembly produced by a Compiler Explorer pane — loading it as the custom program and compiling the
  resulting core in the host IDE.
- Compilation and code loading are driven through the host IDE over the channel's RPC transport,
  rather than through an embedded Makerchip instance.

`PaneChannelClient.js` implements the client side of that channel (readiness handshake, inbound
event subscription, and `callIde(...)` RPC).

## Publishing

`yarn publish:npm` builds the components under `src/components` into `dist/` via Babel for reuse as a
package. The web app itself is deployed from the `yarn build` output.

## Related

- [WARP-V](https://github.com/stevehoover/warp-v) — the CPU core generator this configures.
- [Makerchip](https://makerchip.com) — the TL-Verilog IDE the configurator targets.
- [TL-Verilog](https://tl-x.org) — the design language WARP-V is written in.
