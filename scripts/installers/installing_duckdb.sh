#!/bin/bash
# duckdb_snap_install.sh
# Install DuckDB via snap on Ubuntu/Debian

set -e  # Exit on any error

echo "Updating snap..."
sudo snap install core

# --- Install DuckDB CLI via snap ---
echo "Installing DuckDB CLI via snap..."
sudo snap install duckdb

echo "DuckDB CLI installed. Version:"
duckdb --version

# --- Optional: Install DuckDB Python package via pip ---
echo "Installing DuckDB Python package via pip..."
python3 -m pip install --upgrade pip
python3 -m pip install duckdb

echo "DuckDB Python installed successfully!"
