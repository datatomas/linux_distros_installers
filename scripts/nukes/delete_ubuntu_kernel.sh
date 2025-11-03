
OLD=" 6.8.0-86"

# Purge that kernel’s packages (image, modules, headers)
sudo apt purge -y \
  "linux-image-$OLD-generic" \
  "linux-image-unsigned-$OLD-generic" \
  "linux-modules-$OLD-generic" \
  "linux-modules-extra-$OLD-generic" \
  "linux-headers-$OLD" \
  "linux-headers-$OLD-generic" || true
