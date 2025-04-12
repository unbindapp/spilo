#!/bin/bash
set -ex

# Make sure busybox is installed
apt-get update
apt-get install -y busybox xz-utils
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /usr/share/doc /usr/share/man /etc/rc?.d /etc/systemd

# Verify busybox exists and is executable
BUSYBOX_PATH=$(which busybox)
if [ ! -x "$BUSYBOX_PATH" ]; then
  echo "Error: busybox not found or not executable"
  exit 1
fi

# Create symlink to busybox for /bin/sh
ln -snf $BUSYBOX_PATH /bin/sh
files="/bin/sh"

# Get architecture information
arch=$(uname -m)
darch=$(uname -m | sed 's/_/-/')

# Find required libraries
IFS=" " read -r -a libs <<< "$(ldd $files | awk '{print $3;}' | grep '^/' | sort -u)"
libs+=(/lib/ld-linux-"$darch".so.* \
/lib/"$arch"-linux-gnu/ld-linux-"$darch".so.* \
/lib/"$arch"-linux-gnu/libnsl.so.* \
/lib/"$arch"-linux-gnu/libnss_compat.so.*)

# Create exclude list
(echo /var/run /var/spool "$files" "${libs[@]}" | tr ' ' '\n' && realpath "$files" "${libs[@]}") | sort -u | sed 's/^\///' > /exclude

# Clean up symlinks
find /etc/alternatives -xtype l -delete

# Directories to save
save_dirs=(usr lib var bin sbin etc/ssl etc/init.d etc/alternatives etc/apt)

# Archive essential files
XZ_OPT=-e9v tar -X /exclude -cpJf a.tar.xz "${save_dirs[@]}"

# Clean Python packages
rm -fr /usr/local/lib/python*

# Remove files using find directly instead of xargs busybox
for file in $(find ${save_dirs[*]} -not -type d | sort | grep -vxF -f /exclude); do
  rm -f "$file" || true
done

# Install busybox utilities
$BUSYBOX_PATH --install -s

# Clean up empty directories
for dir in $(find ${save_dirs[*]} -type d -depth); do
  rmdir -p "$dir" 2>/dev/null || true
done