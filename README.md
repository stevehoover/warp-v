# WARP-V

## Overview

WARP-V is an open-source RISC-V CPU core generator that is quickly getting a lot of attention. It is written in TL-Verilog and demonstrates a "transaction-level design" methodology providing an unprecedented level of flexibility. It can implement a single-stage, low-power microcontroller or a mid-range 7-stage CPU. It can even implement other instruction-set architectures (ISAs). WARP-V is an evolving library of CPU components as well as various compositions of them. It is driven by a community interested in transforming the silicon industry through open-source hardware and revolutionary design methodology.

## Links

WARP-V is written in a single source file for compatibility with the Makerchip.com IDE.
<a href="http://www.makerchip.com/sandbox?code_url=https:%2F%2Fraw.githubusercontent.com%2Fstevehoover%2Fwarp-v%2Fmaster%2Fwarp-v.tlv" target="_blank">Open the latest WARP-V in Makerchip</a>.

There is a Google Drive area for this and other <a href="https://drive.google.com/drive/folders/1l9YTvpNZ0km3IlzlPaMvoLdriLw9B8Yk?usp=sharing" target="_blank">open-source TL-Verilog projects</a>.

There is a <a href="https://gitter.im/librecores/warp-v" target="_blank">public communication forum</a> (be respectful) for WARP-V. This is a LibreCores Gitter Room.

Steve Hoover presented early work at DAC 2018:
  - <a href="http://www.makerchip.com/module/pane/DAC2018_WARP-V_Presentation.pdf" target="_blank">Slides</a>
  - <a href="http://www.makerchip.com/module/pane/DAC2018_WARP-V_Poster.pdf" target="_blank">Poster</a>
  
Akos Hadnagy presented formal verification of WARP-V at ORConf 2018 and VSDOpen 2018:
  - <a href="https://docs.google.com/presentation/d/e/2PACX-1vQobRU9_QxRI8dguy0U9WYulMJUm4IWjHHKzz9o8nwId-KGiz8pOrTXsAgwjWEI8GLEipMQj2s8ChMy/pub?start=false&loop=false&delayms=30000" target="_blank">Slides</a>
  - <a href="https://www.youtube.com/watch?v=fqr4Z9wLNvQ&list=PLUg3wIOWD8yoZLznLfhXjlICGlx2tuwvT&index=14&t=21s" target="_blank">Presentation</a>
  - <a href="https://arxiv.org/pdf/1811.12474.pdf" target="_blank">Paper</a>
  - Article: "Verifying a RISC-V in 1 Page of Code!" published on <a href="https://www.linkedin.com/pulse/verifying-risc-v-1-page-code-steve-hoover/" target="_blank">Linkedin</a> and <a href="https://www.semiwiki.com/forum/content/7850-verifying-risc-v-1-page-code-e.html" target="_blank">SemiWiki</a>

## Goals

WARP-V originated as an exploration vehicle for capabilities that are not yet defined in the <a href="http://tl-x.org/" target="_blank">TL-Verilog language spec</a>. As such, it intentionally pushes the limits, using an undocumented proof-of-concept framework (even when old-school Verilog features might suffice).

WARP-V has attracted interest for academic exploration of both the design methodology and CPU microarchitecture. It has significant potential for commercial use.

## Status

WARP-V includes core components only. There is no memory hierarchy, CSR infrastructure, TLB, IO, etc. The design is formally verified, and formal verification is run for continuous integration testing. There is interest in integrating WARP-V with other RISC-V SoC infrastructure to leverage these environments while providing greater flexibility in the CPU. There is also interest in characterizing and optimizing the implementation, and performance. For a detailed understanding of project status, consult the Google Drive and chat room.

## Installation

In a clean directory:

```sh
git clone --recurse-submodules https://github.com/stevehoover/warp-v.git
```

Note the use of `--recurse-submodules`. If you already cloned without it, you can:

```sh
cd warp-v
git submodule init
git submodule update
```

## Contributing to WARP-V

### Considerations

Contributions are welcomed, however, WARP-V is probably the worst possible first exposure to TL-Verilog. It utilizes advanced capabilities that are not yet officially supported. If you are new to TL-Verilog, utilize the resources available in Makerchip to learn TL-Verilog in baby steps before jumping into WARP-V.

With a clear understanding of where to tread, you can navigate WARP-V and contribute successfully. WARP-V is a library with plenty of room to grow. Be aware, however, that working with CPU microarchitecture means walking in a minefield of patents. Work with the community to define your contributions.

To work with WARP-V without stumbling over the undocumented features it utilizes, it is important to understand the tool stack. TL-Verilog is well-defined with reasonable documentation, examples, and interactive tutorials in Makerchip. It is a mature and extremely compelling tool stack that supports timing-abstract and transaction-level design techniques you cannot find elsewhere. WARP-V goes a step further, utilizing an undocumented proof-of-concept framework that supports advanced features for modularity, reuse, parameterization, and code generation. These features are provided using a macro preprocessor called M4 plus a bit of Perl. Though they can be used in Makerchip, they have no long-term support.

There is a clear distinction between these layers, and Makerchip helps to work with them. If you load WARP-V into Makerchip (using the link above), you'll see the source code in the "Editor" pane, and the pre-processed TL-Verilog code (which you can navigate and debug) in the "Nav-TLV" pane. Clicking line numbers in this pane will take you to the source line that generated it. You can cut and paste from Nat-TLV into the Editor to avoid the preprocessing all together.

### Workflow

Work in a fork and submit push requests that have passed continuous integration (CI) testing (below). Your work is much more likely to be accepted if it is aligned with the community and doesn't risk patent infringement.

### Formal Verification

WARP-V is verified using the <a href="https://github.com/cliffordwolf/riscv-formal" target="_blank">riscv-formal</a> open-source formal verification framework. Everything for formal verification is in the `formal` directory. See the <a href="https://github.com/stevehoover/warp-v/tree/master/formal" target="_blank">README.md</a> file there.

### CI

<a href="https://travis-ci.com/" target="_blank">Travis-CI</a> is used for continuous integration testing: <a href="https://travis-ci.com/stevehoover/warp-v" target="_blank">WARP-V Travis CI</a>. CI runs formal verification tests.

**`pre-commit`**: Currently, SandPiper is not available for public download due to export restrictions, so it cannot be available in the CI environment. SV sources must be pre-built and included in the repository. Run the `pre-commit` script to run sandpiper locally. This will also configure your local repo to run `pre-commit` as a pre-commit hook in the future.

**CI Environment**: CI uses the `formal/make_env.sh` script to built the necessary tools from source. The result of this build is cached between builds (per branch) using a <a href="https://docs.travis-ci.com/user/caching" target="_blank">caching feature of Travis-CI</a>. Caching is applied blindly, without regard to the availability of newer sources. CI scripts will check the latest sources against the ones from the cache and report differences near the end of the log. The cache can be cleared manually from the build page. Look under "More options" (upper-right).

**CI Debug**: <a href="https://docs.travis-ci.com/user/running-build-in-debug-mode" target="_blank">Debugging Travis-CI failures</a> can be awkward. To simplify things, if a formal check fails, CI scripts attempt to upload the failure traces using https://transfer.sh/. Look for messages near the end of the log file containing links to the uploaded traces for download and debug.

