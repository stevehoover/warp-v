
# WARP-V Formal Testbench


WARP-V uses riscv-formal for the formal verification procedure: https://github.com/cliffordwolf/riscv-formal

To use the framwork copy the riscv_formal directory into the cores directory in the riscv-formal directory structure and put the latest warp-v.tlv into the riscv_formal directory as well.


There are some modifications you have to make in the configuration section of the code:

```
// Include testbench (for Makerchip simulation) (defaulted to 1).
m4_default(['M4_TB'], 0) // 0 to disable testbench and instrumentation code.
// Build for formal verification (defaulted to 0).
m4_default(['M4_FORMAL'], 1) // 1 to enable code for formal verification
```

The checks you want to run can be selected in the checks.cfg file

Running the verification:
```
cd cores/warpv_formal
make compile
make genchecks
make verif -j$(nproc)
```

The results will appear in warpv_formal/checks.

