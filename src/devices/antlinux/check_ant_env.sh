#!/bin/sh
# check_ant_env.sh
# Helper script to query Python environment for qmake
# Place this file in: src/devices/antlinux/

# This script is called by antlinux.pri with the venv Python path as argument
VENV_PYTHON="$1"

if [ -z "$VENV_PYTHON" ]; then
    echo "ERROR: No Python path provided" >&2
    exit 1
fi

if [ ! -x "$VENV_PYTHON" ]; then
    echo "ERROR: Python executable not found or not executable: $VENV_PYTHON" >&2
    exit 1
fi

# Execute the Python command to get pybind11 include path
# The output goes to stdout, errors to stderr
exec "$VENV_PYTHON" -c 'import sys, site; sys.path.insert(0, site.getsitepackages()[0]); import pybind11; print(pybind11.get_include(), end="")'