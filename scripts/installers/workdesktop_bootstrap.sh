#!/bin/bash

# Update system
sudo apt update && sudo apt upgrade -y

# Install essential utilities
sudo apt install -y curl vim nano git build-essential net-tools software-properties-common apt-transport-https

# Install Python 3.12
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install -y python3.12 python3.12-dev python3.12-distutils

# Install Visual Studio Code
wget -O vscode.deb https://go.microsoft.com/fwlink/?LinkID=760868
sudo apt install ./vscode.deb



# Install Google Chrome
curl -sSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o google-chrome-stable_current_amd64.deb
sudo dpkg -i google-chrome-stable_current_amd64.deb
sudo apt --fix-broken install -y

# Install Geany
sudo apt install -y geany

# Clone and install Geany themes (follow repository instructions)
git clone https://github.com/codebrainz/geany-plugins.git
cd geany-plugins

# Install Vim and Nano
sudo apt install -y vim nano

# Install networking tools
sudo apt install -y curl iputils-ping net-tools

# Set up firewall
sudo ufw enable
sudo ufw allow ssh

# Print completion message
echo "Setup complete. Reboot your system for changes to take effect."

