Quick-n-dirty...

# Clone

- Clone w/ `git clone ...`
- Work in a branch (`git checkout -b new_branch`)

# Edit

The file `warp-v.tlv` is the TL-Verilog WARP-V source code, formatted for editing using makerchip.com. The file contains:
- configuration parameters and standard configurations of these parameters
- the generic CPU model
- ISA-specific macros
- An ISA-specific test program per ISA
- An ISA-specific mini-assembler per ISA (none for DUMMY or MINI (where instructions are strings)).

The single-file organization is due to a current restrictions of Makerchip. This file will get big and unwieldy. Partition the
file with gigantic comment headers to help.

Cut-n-paste this file into the makerchip.com IDE. Save the project and bookmark with a meaningful name.

Edit to your heart's content.

# Regress

The only regression content, currently, is the single test within the source file -- actually, one test per ISA (excluding DUMMY).

Make sure this test passes for all ISAs and all standard configurations (very manually).

# Push/Pull

Cut-n-paste out of the IDE.

`git gui` is an option for reviewing, committing, and pushing changes. Clean-up your work, comment, and
document appropriately before committing (with a clear message) and pushing.

Create a pull request within gitlab.

Address any feedback.

Update this document where it is deficient.
