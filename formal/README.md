
# WARP-V Formal Verification

## Workflow

For fomal verification work:

```sh
cd <repo>/formal
```

The `Makefile` contains all the necessary dependencies to install riscv-formal as a
git submodule, build the necessary environment locally, and run formal verification.

```sh
make verif
```

WARP-V uses riscv-formal for formal verification. The tools (Yosys, SymbiYosys, and solvers) come from the prebuilt
<a href="https://github.com/YosysHQ/oss-cad-suite-build" target="_blank" atom_fix="_">OSS CAD Suite</a>. The build to use is pinned by
`OSS_CAD_SUITE_VERSION` in the `Makefile` (and CI uses the same version). If `sby` is not found on your `PATH`, `make verif`
downloads that build into `env/` (`make env`). To use your own installation, put it on your `PATH`.

`warp-v.tlv` can be compiled with SandPiper(TM) SaaS Edition (running in the cloud) for formal verification using:

```sh
make compile
```

(The first time, you must agree to the SandPiper-SaaS terms of service, e.g. using `make tos_agree`.)

The configuration to verify can be selected on the command line:

```sh
make verif STANDARD_CONFIG=1-stage  # Default is 4-stage. Check depths for each config are in depths/<config>.cfg.
make verif EXT_C=1                  # Enable the (incomplete, currently failing) compressed instruction support.
```

The checks you want to run can be selected in `checks.cfg` (then rerun `make verif`).

The results will appear in `out/checks/`. `make verif` reports a summary and fails if any checks do not pass.
(`make results` reports the summary again.) Counterexample traces for failing checks are in
`out/checks/<check>/engine_0/trace.vcd`. These can be viewed in Makerchip VIZ using the model in
`out/warp-v_formal.m5out.tlv` (see "CI Debug" in the top-level `README.md`).

## Continuous Integration

Formal verification runs in GitHub Actions (`.github/workflows/formal.yml`) for changes to `warp-v.tlv` or `formal/`.
On failure, logs and traces are available as a workflow artifact.


## Upgrading riscv-formal

Until riscv-formal pulls https://github.com/SymbioticEDA/riscv-formal/pull/11 (or `#46`, or similar), we are using
a side-version of RISC-V formal. Beware.
