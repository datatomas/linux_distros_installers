#!/bin/bash
# simple_duckdb_install.sh
# Simple installation of DuckDB Python package (CLI optional)

set -e  # Exit on any error

echo "Updating package list..."
sudo apt update -y

# --- Install Python pip if not installed ---
sudo apt install python3-pip -y

# --- Install DuckDB Python package ---
python3 -m pip install --upgrade pip
python3 -m pip install duckdb

# --- Optional: DuckDB CLI ---
# wget https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip -O /tmp/duckdb_cli.zip
# unzip /tmp/duckdb_cli.zip -d /tmp
# sudo mv /tmp/duckdb /usr/local/bin/duckdb
# rm /tmp/duckdb_cli.zip

echo "DuckDB Python installed successfully!"
