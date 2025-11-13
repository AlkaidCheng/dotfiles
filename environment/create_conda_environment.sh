#!/bin/bash

# Function to create or ensure Miniconda installation
create_conda () {

    # Check if conda is already installed
    if [[ -f "${CONDADIR}/miniconda/etc/profile.d/conda.sh" ]]; then
        echo "INFO: conda already installed."
        return 0
    fi

    # Create CONDADIR if it doesn't exist
    if [[ ! -d "$CONDADIR" ]]; then
        mkdir -p "$CONDADIR"
    fi

    # Determine the correct Miniconda installer file based on OS and architecture
    if [[ "$OSTYPE" == "linux"* ]]; then
        # Linux
        CONDABASHFILE="Miniconda3-latest-Linux-x86_64.sh"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # MacOS
        if [[ "$(uname -m)" == "arm"* ]]; then
            CONDABASHFILE="Miniconda3-latest-MacOSX-arm64.sh"
        else
            CONDABASHFILE="Miniconda3-latest-MacOSX-x86_64.sh"
        fi
    else
        echo "ERROR: unsupported operating system: $OSTYPE"
        return 1
    fi

    # --- Download Utility Selection Logic ---
    local download_cmd=""
    local download_option_out="" # Option for output file (-O for wget, -o for curl)

    # Check for wget
    if command -v wget >/dev/null 2>&1; then
        download_cmd="wget"
        download_option_out="-P" # wget uses -P for directory
        echo "INFO: Using wget for download."
    # Check for curl if wget is not found
    elif command -v curl >/dev/null 2>&1; then
        download_cmd="curl"
        download_option_out="-o" # curl uses -o for output file name, needs full path
        echo "INFO: Using curl for download."
    else
        echo "ERROR: Neither wget nor curl is installed. Please install one of them and rerun the script."
        return 1
    fi

    # Construct the full download URL
    local download_url="https://repo.anaconda.com/miniconda/${CONDABASHFILE}"
    local local_installer_path="${CONDADIR}/${CONDABASHFILE}"

    # Only download the shell script if it doesn't exist
    if [[ ! -f "${local_installer_path}" ]]; then
        echo "INFO: Downloading Miniconda installer: ${CONDABASHFILE}..."
        if [[ "$download_cmd" == "wget" ]]; then
            # wget -P <directory> <URL>
            "$download_cmd" "${download_option_out}" "${CONDADIR}" "${download_url}"
        elif [[ "$download_cmd" == "curl" ]]; then
            # curl -o <output_file_path> <URL>
            "$download_cmd" "${download_option_out}" "${local_installer_path}" "${download_url}"
        fi

        # Check if the download was successful
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to download Miniconda installer using $download_cmd."
            return 1
        fi
    else
        echo "INFO: Miniconda installer already exists: ${CONDABASHFILE}. Skipping download."
    fi

    # Run the Miniconda installer
    echo "INFO: Installing Miniconda to ${CONDADIR}/miniconda..."
    bash "${local_installer_path}" -b -p "${CONDADIR}/miniconda"
    if [ $? -ne 0 ]; then
        echo "ERROR: Miniconda installation failed."
        return 1
    fi
}

# Function to configure conda settings
configure_conda() {
    echo "INFO: Configuring conda..."
    conda config --set channel_priority strict
    conda config --set solver libmamba
}

CONDA_ENV_NAME="envbase"
CONDA_PYTHON_VERSION="3.11"
CONDADIR_SET=false
INSTALL_ROOT=false
INSTALL_MLBASE=false
INSTALL_ALKAID=false
INSTALL_TENSORFLOW=false
ROOT_INSTALL_VERSION="latest"

usage() {
    echo "Usage: $0 [-d|--dir VALUE] [-n|--name VALUE] [-p|--python VALUE] [-r|--root] [-m|--mlbase] [--rootver VALUE] [--alkaid] [--tensorflow]"
    echo "  -d, --dir       : Directory to install conda (REQUIRED)"
    echo "  -n, --name      : Name of conda environment (default: $CONDA_ENV_NAME)"
    echo "  -p, --python    : Python version for the environment (default: $CONDA_PYTHON_VERSION)"
    echo "  -r, --root      : (flag) Install ROOT data analysis framework"
    echo "  --rootver       : Version of ROOT to install (default: $ROOT_INSTALL_VERSION, only with -r)"
    echo "  -m, --mlbase    : (flag) Install basic Machine Learning packages"
    echo "  --tensorflow    : (flag) Install TensorFlow (with CUDA support if available)"
    echo "  --alkaid        : (flag) Install Alkaid's specific packages"
    return 1
}

main() {
    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -d|--dir)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    CONDADIR=$2
                    CONDADIR_SET=true
                    shift
                else
                    echo "ERROR: Argument for $1 is missing" >&2
                    usage
                    return 1
                fi
                ;;    
            -n|--name)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    CONDA_ENV_NAME=$2
                    shift
                else
                    echo "ERROR: Argument for $1 is missing" >&2
                    usage
                    return 1
                fi
                ;;
            -p|--python)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    CONDA_PYTHON_VERSION=$2
                    shift
                else
                    echo "ERROR: Argument for $1 is missing" >&2
                    usage
                    return 1
                fi
                ;;
            -r|--root)
                INSTALL_ROOT=true
                ;;
            --rootver)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    ROOT_INSTALL_VERSION=$2
                    shift
                else
                    echo "ERROR: Argument for $1 is missing" >&2
                    usage
                    return 1
                fi
                ;;            
            -m|--mlbase)
                INSTALL_MLBASE=true
                ;;
            --tensorflow)
                INSTALL_TENSORFLOW=true
                ;; 
            --alkaid)
                INSTALL_ALKAID=true
                ;;             
            *)
                usage
                return 1
                ;;
        esac
        shift
    done

    if ! $CONDADIR_SET; then
        echo "Please specify the directory to install conda" >&2
        usage
        return 1
    fi

    SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done

    export DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

    create_conda
    if [ $? -ne 0 ]; then
        return 1
    fi
    source "${CONDADIR}/miniconda/etc/profile.d/conda.sh"
    configure_conda
    if [ -d "${CONDADIR}/miniconda/envs/${CONDA_ENV_NAME}" ]; then
        echo "INFO: Conda environment $CONDA_ENV_NAME already exists. Skip creation."
    else
        conda create -y -c conda-forge --name "$CONDA_ENV_NAME" python="$CONDA_PYTHON_VERSION" 
    fi


    # Add conda clean command to clear cache and prevent lock issues
    conda clean -y --all
    echo "INFO: Cleaned conda cache to prevent lock issues."
    
    conda activate "$CONDA_ENV_NAME"

    #install TensorFlow
    if $INSTALL_TENSORFLOW; then
        pip install tensorflow[and-cuda]
    fi
    
    # install ROOT
    if $INSTALL_ROOT; then
        if [ "$ROOT_INSTALL_VERSION" = "latest" ]; then
            conda install -y -c conda-forge root
        else
            conda install -y -c conda-forge root==$ROOT_INSTALL_VERSION
        fi
    fi

    PIP_CACHE_DIR=${CONDADIR}/.cache/pip
    mkdir -p "$PIP_CACHE_DIR"
    
    # basic packages
    pip --cache-dir "$PIP_CACHE_DIR" install pyyaml numpy scipy matplotlib pandas h5py
    conda install -y -c twine jupyterlab jupyterhub
    conda install -y -c numba ruff click
    pip --cache-dir "$PIP_CACHE_DIR" install pyarrow fsspec tables sympy tqdm
    # jupyter extensions
    pip --cache-dir "$PIP_CACHE_DIR" install jupyterlab-nvdashboard jupyterlab-favorites

    # ROOT related packages
    if $INSTALL_ROOT; then
        pip --cache-dir "$PIP_CACHE_DIR" install awkward uproot vector 
    fi

    # install basic ML packages
    if $INSTALL_MLBASE; then
        conda install -y -c conda-forge scikit-learn scikit-optimize hyperopt nevergrad
        pip --cache-dir "$PIP_CACHE_DIR" install xgboost nflows shapely ray ray[tune]
    fi

    # install Alkaid's packages
    if $INSTALL_ALKAID; then
        pip --cache-dir "$PIP_CACHE_DIR" install hpogrid quickstats aliad
        #pip install quple
    fi

    pip --cache-dir "$PIP_CACHE_DIR" cache purge

    #conda install -y -c conda-forge pytorch tensorflow
    #conda install -c conda-forge tensorflow-gpu==2.12.1
    #conda install -c "nvidia/label/cuda-11.8.0" cuda-toolkit
    #conda install -c conda-forge tensorflow-gpu==2.9.0
    #conda install -c "nvidia/label/cuda-11.7.0" cuda-toolkit
    #pip install tensorflow[and-cuda]
    #conda install -c conda-forge cudatoolkit=11.8 cudnn=8.7.0
}

main "$@"