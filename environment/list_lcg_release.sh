#!/bin/bash

# Function to display the help message
function show_help {
    echo "Usage: $0 LCG_VERSION"
    echo
    echo "Prints out the appropriate LCG versions usable by the machine."
    echo
    echo "Arguments:"
    echo "  LCG_VERSION   The LCG version to search for (e.g., LCG_102)."
}

# Check for LCG version argument
if [ "$#" -ne 1 ]; then
    echo "Error: You must specify the LCG version." >&2
    show_help >&2
    return 1  # Use return instead of exit to avoid closing the shell
fi

find_lcg_versions() {
    local LCG_VERSION=$1

    # Get the machine architecture
    local ARCH=$(uname -m)

    # Convert architecture to match LCG subdirectory format
    case "$ARCH" in
        x86_64)
            ARCH="x86_64"
            ;;
        aarch64)
            ARCH="aarch64"
            ;;
        *)
            echo "Unsupported architecture: $ARCH"
            return 1
            ;;
    esac

    # Get the Linux distribution
    local DISTRO=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        # Extract the leading number from VERSION_ID
        local VERSION_MAJOR=${VERSION_ID%%.*}
        case "$ID" in
            centos)
                DISTRO="centos${VERSION_MAJOR}"
                ;;
            rhel|el|elma|almalinux)
                DISTRO="el${VERSION_MAJOR}"
                ;;
            *)
                echo "Unsupported Linux distribution: $ID" >&2
                return 1
                ;;
        esac
    else
        echo "Cannot determine Linux distribution." >&2
        return 1
    fi

    # Directory where LCG releases are stored
    local LCG_DIR="/cvmfs/sft.cern.ch/lcg/views/$LCG_VERSION"

    # Check if the directory exists
    if [ ! -d "$LCG_DIR" ]; then
        echo "LCG version $LCG_VERSION does not exist." >&2
        return 1
    fi

    # List and filter appropriate subdirectories
    local VALID_VERSIONS=$(ls -d "$LCG_DIR"/* | xargs -n 1 basename | grep -E "^$ARCH-$DISTRO-gcc[0-9]+-(opt|dbg)$")

    # If no valid versions are found, exit
    if [ -z "$VALID_VERSIONS" ]; then
        echo "No compatible versions found for architecture $ARCH and distribution $DISTRO." >&2
        return 1
    fi

    # Sort by GCC version (descending), then by type (opt first)
    local SORTED_VERSIONS=$(echo "$VALID_VERSIONS" | sort -t- -k3,3r -k4,4r -k4,4 -s)

    # Return the sorted versions
    echo "$SORTED_VERSIONS"
}

find_lcg_versions "$1"