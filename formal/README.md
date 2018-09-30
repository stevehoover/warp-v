
# WARP-V Formal Verification

You'll need an installation of SandPiper(TM), which can be obtained from http://www.redwoodeda.com.

With the exception of SandPiper, the `Makefile` contains all the necessary dependencies to install riscv-formal as a
git submodule, build the necessary environment locally, and run formal verification.

```sh
cd warp-v/formal
make verif
```

WARP-V uses riscv-formal for formal verification. The script `make_env.sh` (run by the `Makefile`) is provided to
download and build the necessary tools in the manner described in this <a href="https://github.com/cliffordwolf/riscv-formal/blob/master/docs/quickstart.md" target="_blank">QuickStart Guide</a>.

`warp-v_formal.tlv` can be compiled with SandPiper using:

```sh
make compile
```

The checks you want to run can be selected in `checks.cfg` (then rerun `make verif`).

The results will appear in `checks/`.
