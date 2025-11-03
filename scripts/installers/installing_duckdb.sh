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



echo "DuckDB Python installed successfully!"
