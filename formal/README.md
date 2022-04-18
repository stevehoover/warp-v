
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

WARP-V uses riscv-formal for formal verification. The script `make_env.sh` (run by the `Makefile`) is provided to
download and build the necessary tools in the manner described in this <a href="https://github.com/cliffordwolf/riscv-formal/blob/master/docs/quickstart.md" target="_blank" atom_fix="_">QuickStart Guide</a>.

`warp-v.tlv` can be compiled with SandPiper(TM) SaaS Edition (running in the cloud) for formal verification using:

```sh
make compile
```

The checks you want to run can be selected in `checks.cfg` (then rerun `make verif`).

The results will appear in `checks/`.


## Upgrading riscv-formal

Until riscv-formal pulls https://github.com/SymbioticEDA/riscv-formal/pull/11 (or `#46`, or similar), we are using
a side-version of RISC-V formal. Beware.
