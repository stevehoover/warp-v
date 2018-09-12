
# WARP-V Formal Testbench

WARP-V uses riscv-formal for formal verification. You'll need to satisfy all of the prerequisits
of this environment, as described in the <a href="https://github.com/cliffordwolf/riscv-formal/blob/master/docs/quickstart.md" target="_blank">QuickStart Guide</a>. Or, we've pre-built the necessary environment for Ubuntu <a href="https://github.com/stevehoover/warp-v_ci_env" target="_blank">QuickStart Guide</a>. If your
environment is compatible, you can (in bash):

```sh
git clone https://github.com/stevehoover/warp-v_ci_env.git
PATH=$PATH:<dir>/warp-v_ci_env/env/bin
```

You'll also need an installation of SandPiper(TM), which can be obtained from http://www.redwoodeda.com.

In a clean directory:

```sh
git clone https://github.com/cliffordwolf/riscv-formal.git
git clone https://github.com/stevehoover/warp-v.git
cp -rf warp-v/warpv_formal riscv-formal/cores/
```

The checks you want to run can be selected in the checks.cfg file

Running the verification:
```sh
cd riscv-formal/cores/warpv_formal
make compile
make genchecks
make verif -j$(nproc)
```

The results will appear in warpv_formal/checks.

