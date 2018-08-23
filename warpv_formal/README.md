
# WARP-V Formal Testbench

WARP-V uses riscv-formal for formal verification. You'll need to satisfy all of the prerequisits
of this environment, as described in the <a href="https://github.com/cliffordwolf/riscv-formal/blob/master/docs/quickstart.md" target="_blank">QuickStart Guide</a>.

You'll also need an installation of SandPiper(TM), which can be obtained from [www.redwoodeda.com].

In a clean directory:

```sh
git clone https://github.com/cliffordwolf/riscv-formal.git
git clone https://github.com/stevehoover/warp-v.git
cp -rf warp-v/warpv_formal riscv-formal/cores/
cp warp-v/warp-v.tlv riscv-formal/cores/warpv_formal/
```

There are some modifications you have to make in the configuration section of the code:

```
// Include testbench (for Makerchip simulation) (defaulted to 1).
m4_default(['M4_TB'], 0) // 0 to disable testbench and instrumentation code.
// Build for formal verification (defaulted to 0).
m4_default(['M4_FORMAL'], 1) // 1 to enable code for formal verification
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

