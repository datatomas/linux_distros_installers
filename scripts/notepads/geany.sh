# Install Geany + Git
sudo apt update
sudo apt install -y geany git

# Workspace
mkdir -p /home/ares/data/gitrepos
cd /home/ares/data/gitrepos

# Clone Geany themes (this is what you want)
git clone https://github.com/geany/geany-themes.git

# Install the themes for your user
mkdir -p ~/.config/geany/colorschemes
cp geany-themes/colorschemes/*.conf ~/.config/geany/colorschemes/
