#!/bin/bash

# Default pattern for matching LCG release directories
DEFAULT_PATTERN="^LCG_[0-9]{3}[a-zA-Z]?$"
PATTERN=$DEFAULT_PATTERN

# Function to display the help message
function show_help {
    echo "Usage: $0 [PATTERN]"
    echo
    echo "List LCG releases based on directory names in the /cvmfs/sft.cern.ch/lcg/views directory."
    echo
    echo "Arguments:"
    echo "  PATTERN    Optional. A regex pattern to filter the LCG releases. Defaults to '^LCG_[0-9]{3}[a-zA-Z]?\$'."
    echo
    echo "Options:"
    echo "  -h, --help  Show this help message."
}

# Parse command-line arguments
if [ "$#" -ge 1 ]; then
    case "$1" in
        -h|--help)
            show_help
            ;;
        *)
            PATTERN=$1
            ;;
    esac
fi

ls -d /cvmfs/sft.cern.ch/lcg/views/* | xargs -n 1 basename | grep -E "$PATTERN"