#!/bin/bash

create_conda () {
    
    if [[ -f ${CONDADIR}/miniconda/etc/profile.d/conda.sh ]];
    then
        echo "INFO: conda already installed."
        return 0
    fi
    
    mkdir -p "$CONDADIR"
    
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
    
    if ! command -v wget >/dev/null 2>&1; then
        echo "ERROR: wget is not installed. Please install wget and rerun the script."
        return 1
    fi
    
    wget https://repo.anaconda.com/miniconda/${CONDABASHFILE}
    bash "${CONDABASHFILE}" -b -p "${CONDADIR}/miniconda"
}

configure_conda() {
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
    echo "Usage: $0 [-d|--dir VALUE] [-n|--name VALUE] [-p|--python VALUE] [-r|--root] [-m|--mlbase] [--rootver VALUE] [--alkaid] [...]"
    echo "  -d, --dir     : Directory to install conda"
    echo "  -n, --name    : Name of conda environment"
    echo "  -p, --python  : Python version"
    echo "  -r, --root    : (flag) Install ROOT"
    echo "  '--tensorflow : (flag) Install Tensorflow"
    echo "  -m, --mlbase  : (flag) Install basic ML packages"
    echo "  --rootver     : Version of ROOT to install"
    echo "  --alkaid      : (flag) Install Alkaid's packages"
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
    CONDAENV_EXIST=$(conda env list | grep "$CONDA_ENV_NAME")
    if [ -n "$CONDAENV_EXIST" ]; then
        echo "INFO: Conda environment $CONDA_ENV_NAME already exists. Skip creation."
    else
        conda create -y -c conda-forge --name "$CONDA_ENV_NAME" python="$CONDA_PYTHON_VERSION"
    fi
    
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

#source create.sh -d /pscratch/sd/c/chlcheng/local/ --root --mlbase --tensorflow --alkaid -n ml-gpu