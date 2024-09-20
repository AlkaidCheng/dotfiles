#!/bin/bash

remove_duplicate_paths() {
    local path_value="$1"
    
    # Convert the input path string into an array using ':' as the delimiter
    IFS=':' read -r -a path_array <<< "$path_value"

    # Initialize an empty array for storing unique paths
    unique_paths=()

    for path in "${path_array[@]}"; do
        # Check if the path is already in unique_paths
        if [[ ! " ${unique_paths[*]} " == *" $path "* ]]; then
            unique_paths+=("$path")
        fi
    done

    # Join the array back into a single string and output the cleaned path
    echo "$(IFS=:; echo "${unique_paths[*]}")"
}

export PATH=$(remove_duplicate_paths "$PATH")
export PYTHONPATH=$(remove_duplicate_paths "$PYTHONPATH")