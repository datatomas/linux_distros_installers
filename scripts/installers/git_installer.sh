#!/bin/bash
# install_git.sh
# Installs Git on Ubuntu/Debian

set -e  # Exit on any error

echo "Updating package list..."
sudo apt update -y

echo "Installing Git..."
sudo apt install git -y

echo "Git installed successfully!"
git --version
