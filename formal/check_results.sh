#!/bin/bash

# Summarize riscv-formal results in the given checks directory (default: out/checks).
# SymbiYosys exits successfully for FAILing checks (the generated .sby files "expect pass,fail"),
# so this script inspects each check's status file and exits non-zero unless all checks PASS.
# If $GITHUB_STEP_SUMMARY is set, a Markdown summary is appended to it.

CHECKS_DIR="${1:-out/checks}"
[[ -e "$CHECKS_DIR/makefile" ]] || { echo "Error: No checks found in $CHECKS_DIR." 1>&2; exit 1; }

# Check names are the prerequisites of "all" in the generated makefile.
CHECKS=$(sed -n 's/^all: //p' "$CHECKS_DIR/makefile")

declare -A COUNT
FAILED=()
for CHECK in $CHECKS; do
  # Status file contents are, e.g., "PASS 0 16" (status, return code, seconds).
  STATUS=$(cut -d' ' -f1 "$CHECKS_DIR/$CHECK/status" 2>/dev/null)
  STATUS=${STATUS:-MISSING}
  COUNT[$STATUS]=$(( ${COUNT[$STATUS]:-0} + 1 ))
  [[ $STATUS == PASS ]] || FAILED+=("$CHECK: $STATUS")
done

TOTALS=$(for STATUS in "${!COUNT[@]}"; do echo -n "$STATUS: ${COUNT[$STATUS]}  "; done)
echo "riscv-formal results ($CHECKS_DIR): $TOTALS"
for F in "${FAILED[@]}"; do echo "  $F"; done

if [[ -n $GITHUB_STEP_SUMMARY ]]; then
  {
    echo "### riscv-formal results"
    echo
    echo "$TOTALS"
    echo
    for F in "${FAILED[@]}"; do echo "- $F"; done
  } >> "$GITHUB_STEP_SUMMARY"
fi

(( ${#FAILED[@]} == 0 ))
