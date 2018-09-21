#!/bin/bash

# A script to build the environment needed for formal verification of warp-v using riscv-formal.
# The build is performed in a 'env_build' directory within the current working directory, and
# installed in an 'env' directory also within the current working directory. Each tool is built
# in its own directory within 'env_build'. If this directory already exists, the tool will not
# be built. Each tool is built sequentially even if preceding builds failed. Passing tools will
# touch a "PASSED" file in their directory, and the entire script will touch "PASSED" in /env.

die() { echo "$*" 1>&2 ; exit 1; }
skip() { true; }  # Use this to skip a command.
comment() { true; } # This can be used for comments within multiline commands.


# Check to see whether the given tool has already been built, and whether it passed.
# Return 1 if the tool must be built (o.w. 0).
check_previous_build() {
  cd "$BUILD_DIR"
  if [ -e "$1" ]; then
    if [ -e "$1/PASSED" ]; then
      echo && echo "Info: Skipping $1 build, which previously passed." && echo
      STATUS[$1]=0
    else
      echo && \
      echo "*******************************************************" && \
      echo "Warning: Skipping $1 build, which previously FAILED." && \
      echo "*******************************************************" && \
      echo
      STATUS[$1]=1
    fi
    return 0
  else
    echo && \
    echo "------------------------" && \
    echo "Info: Building $1." && \
    echo
    return 1
  fi
}

(mkdir -p env/bin env/share env_build) || die "Failed to make 'env' directories."
cd env_build

BUILD_DIR=`pwd`
echo "$BUILD_DIR"

# Yosys:
check_previous_build "yosys"
if [ $? -eq 1 ]; then
  git clone https://github.com/cliffordwolf/yosys.git && \
  cd yosys && \
  comment 'Capture the commit ID' && \
  (git rev-parse HEAD > ../../env/yosys_commit_id.txt) && \
  make config-clang && \
  make && \
  echo "pwd of env_build/yosys: $PWD"
  mv yosys* ../../env/bin && \
  mv share/* ../../env/share && \
  comment 'Stuff in share/python3 is not in a standard include path. Seems to work in share/yosys, so move it.'
  mv ../../env/share/python3/* ../../env/share/yosys/python3 && \
  touch PASSED
  STATUS[yosys]=$?
fi

## RISCV-Formal:
#cd "$BUILD_DIR"
#git clone https://github.com/cliffordwolf/riscv-formal.git riscv-formal && \
#cd riscv-formal && \
#`# Record commit ID.` \
#(git rev-parse HEAD > commit_id.txt) && \
#git checkout 51076e93d70648cf813ef00d7e4cd93b94ea55f5 `# Currently stuck on this version.`
#STATUS[riscv-formal]=$?

# SymbiYosys:
check_previous_build "SymbiYosys"
if [ $? -eq 1 ]; then
  git clone https://github.com/cliffordwolf/SymbiYosys.git SymbiYosys && \
  cd SymbiYosys && \
  comment 'Capture the commit ID' && \
  (git rev-parse HEAD > ../../env/SymbiYosys_commit_id.txt) && \
  make install PREFIX=../../env && \
  touch PASSED
  STATUS[SymbiYosys]=$?
fi

## Z3
#cd "$BUILD_DIR"
#git clone https://github.com/Z3Prover/z3.git z3 && \
#cd z3 && \
#python scripts/mk_make.py && \
#cd build && \
#make -j$(nproc) && \
## TODO: install

# Boolector
check_previous_build "boolector"
if [ $? -eq 1 ]; then
  mkdir boolector && \
  cd boolector && \
  wget http://fmv.jku.at/boolector/boolector-2.4.1-with-lingeling-bbc.tar.bz2 && \
  tar xvjf boolector-2.4.1-with-lingeling-bbc.tar.bz2 && \
  cd boolector-2.4.1-with-lingeling-bbc/ && \
  make && \
  cp boolector/bin/boolector ../../../env/bin && \
  touch ../PASSED
  STATUS[boolector]=$?
fi

cd "$BUILD_DIR"
if (( ${STATUS[yosys]} || $STATUS[SymbiYosys] || $STATUS[boolector] )); then
  echo && \
  echo "*********************" && \
  echo "Some build(s) FAILED." && \
  echo "*********************" && \
  echo "(${STATUS[yosys]}, ${STATUS[SymbiYosys]}, ${STATUS[boolector]})"
  echo `ls */PASSED` && \
  echo
  touch ../env/PASSED
  exit 1
else
  exit 0
fi
