#!/bin/bash

# Function to display the help message
function show_help {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Record Python package versions across different LCG views."
    echo
    echo "Options:"
    echo "  -p, --pattern       Pattern to filter LCG views (e.g., '^LCG_[0-9]{3}[a-zA-Z]?$')."
    echo "  -o, --output-file   Name of the output YAML file (default: 'all_lcg_package_versions.yaml')."
    echo "  -l, --packages      Comma-separated list of package names (default: 'ROOT,cppyy,pydantic,numpy,pandas,matplotlib')."
    echo "  -h, --help          Show this help message and exit."
    echo
    echo "Examples:"
    echo "  $0 -p '^LCG_102' -o versions.yaml -l 'numpy,pandas,matplotlib'"
    echo "  $0 --pattern='^LCG_[0-9]{2}[a-zA-Z]$' --output-file='versions.yaml'"
}

get_script_dir() {
    local SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
        local DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, resolve it relative to the path where the symlink file was located
    done
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    echo "$DIR"
}

SCRIPT_DIR=$(get_script_dir)

# Default values
PATTERN="^LCG_[0-9]{3}[a-zA-Z]?$"
OUTPUT_FILE="all_lcg_package_versions.yaml"
PACKAGES=("ROOT" "cppyy" "pydantic" "numpy" "pandas" "matplotlib")

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--pattern) PATTERN="$2"; shift ;;
        -o|--output-file) OUTPUT_FILE="$2"; shift ;;
        -l|--packages) IFS=',' read -r -a PACKAGES <<< "$2"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown parameter passed: $1" >&2 ; show_help >&2; return 1 ;;
    esac
    shift
done

# Initialize the YAML dictionary
echo "lcg_package_versions:" > "$OUTPUT_FILE"

# Set up ATLAS environment
export ATLAS_LOCAL_ROOT_BASE=/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase
source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh

# Loop through each LCG view matching the pattern
for LCG_VIEW in $(source "${SCRIPT_DIR}/list_lcg_views.sh $PATTERN"); do

    # Find the first recommended LCG release for the view
    LCG_RELEASE=$(source "${SCRIPT_DIR}/list_lcg_release.sh" "$LCG_VIEW" | head -n 1)

    # Check if a compatible LCG release was found
    if [ -z "$LCG_RELEASE" ]; then
        echo "No compatible LCG release found for $LCG_VIEW. Skipping..." >&2
        continue
    fi
    
    # Set up the LCG environment
    lsetup "views $LCG_VIEW $LCG_RELEASE"

    echo "Working on LCG Release $LCG_VIEW ($LCG_RELEASE)"
    
    # Initialize the sub-dictionary for the current LCG view
    echo "  $LCG_VIEW:" >> "$OUTPUT_FILE"

    # Loop through each package and check version using Python
    for package in "${PACKAGES[@]}"; do
        version=$(python -c "
try:
    pkg = __import__('$package')
    print(getattr(pkg, '__version__', 'None'))
except ImportError:
    print('None')
" 2>/dev/null)

        # Append the package name and version to the YAML file
        echo "    $package: $version" >> "$OUTPUT_FILE"
    done

done

echo "All package versions saved to $OUTPUT_FILE"
