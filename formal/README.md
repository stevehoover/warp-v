
# WARP-V Formal Testbench

```sh
cd warp-v/formal
```

WARP-V uses riscv-formal for formal verification. A script is provided to download and build the necessary tools, as described in this <a href="https://github.com/cliffordwolf/riscv-formal/blob/master/docs/quickstart.md" target="_blank">QuickStart Guide</a>.

```sh
make_env.sh
```

You'll also need an installation of SandPiper(TM), which can be obtained from http://www.redwoodeda.com.

`warp-v_formal.tlv` can be compiled with SandPiper using:

```sh
make compile
```

The checks you want to run can be selected in `checks.cfg`.

To run verification:

```sh
make verif
```

The results will appear in `checks`.

