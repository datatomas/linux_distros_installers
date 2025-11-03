#!/bin/bash
# install_dev_tools.sh
# Installs Git, Visual Studio Code, and Python 3 on Ubuntu/Debian.

set -e  # Exit on any error

echo "Updating package list..."
sudo apt update -y

# --- Install Git ---
echo "Installing Git..."
sudo apt install git -y
echo "Git installed. Version: $(git --version)"
echo

# --- Install Python 3 and pip ---
echo "Installing Python 3 and pip..."
sudo apt install python3 python3-pip python3-venv -y
echo "Python installed. Version: $(python3 --version)"
echo "pip installed. Version: $(pip3 --version)"
echo

# --- Install Visual Studio Code ---
echo "Installing VS Code..."
# Install prerequisites
sudo apt install software-properties-common apt-transport-https wget -y

# Import Microsoft GPG key
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/

# Add VS Code repository
sudo sh -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'

# Update and install
sudo apt update -y
sudo apt install code -y

echo "VS Code installed. Version: $(code --version | head -n 1)"
echo

# --- Clean up ---
rm packages.microsoft.gpg
echo "Installation complete!"
