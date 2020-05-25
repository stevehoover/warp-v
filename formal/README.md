
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

`warp-v_formal.tlv` can be compiled with SandPiper(TM) SaaS Edition (running in the cloud) using:

```sh
make compile
```

The checks you want to run can be selected in `checks.cfg` (then rerun `make verif`).

The results will appear in `checks/`.


## Upgrading riscv-formal

The file `riscv-formal/checks/genchecks.py` required modifications that were not accepted in riscv-formal.
There is a local copy of this file that must be maintained if riscv-formal is updated.
To apply the patch, run apply_genchecks.py.patch.
