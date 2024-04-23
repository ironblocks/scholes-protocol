#!/bin/bash
# A script to calculate the size of deployed bytecode for all contracts in the Foundry output directory
# and check for EIP-170 violations. Optionally prints all sizes with -v flag.

OUT_DIR="./out" # Path to the output directory where contract artifacts are stored

VERBOSE=false

# Check for verbose flag
while getopts "v" option; do
    case $option in
        v) VERBOSE=true ;;
        *) echo "Usage: $0 [-v]"; exit 1 ;;
    esac
done

# Check if the output directory exists
if [ ! -d "$OUT_DIR" ]; then
    echo "Output directory does not exist: $OUT_DIR"
    exit 1
fi

# Find all JSON files in the output directory
find "$OUT_DIR" -name '*.json' | while read -r json_file; do
    # Extract the contract name from the file path
    contract_name=$(basename "$json_file" .json)

    # Attempt to extract bytecode using jq; if not present, skip
    bytecode=$(jq -r '.bytecode.object // empty' "$json_file")

    # Check if bytecode is present and non-empty
    if [ -n "$bytecode" ] && [ "$bytecode" != "0x" ]; then
        # Calculate the size of the bytecode
        size=$((${#bytecode} / 2 - 1)) # Divide by 2 to convert hex digits to bytes and remove the leading '0x'
        if [ "$size" -gt 24576 ]; then
            echo "$contract_name: Bytecode size is $size bytes (WARNING: exceeds 24KB - EIP-170 violation!)"
        elif [ "$VERBOSE" = true ]; then
            echo "$contract_name: Bytecode size is $size bytes"
        fi
    fi
done
