#!/bin/bash
# install_duckdb.sh
# Installs DuckDB CLI and Python package on Ubuntu/Debian

set -e  # Exit on any error

echo "Updating package list..."
sudo apt update -y

# --- Install DuckDB CLI ---
echo "Installing DuckDB CLI..."
sudo apt install duckdb -y
echo "DuckDB CLI installed. Version: $(duckdb --version || echo 'CLI not available')"
echo

# --- Install DuckDB Python package ---
echo "Installing DuckDB Python package..."
pip3 install --upgrade pip
pip3 install duckdb
echo "DuckDB Python package installed. Version: $(python3 -c 'import duckdb; print(duckdb.__version__)')"
echo

echo "DuckDB installation complete!"
