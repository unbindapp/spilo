#!/bin/bash
# compress_build.sh - Safely compress Docker image by removing unnecessary files
# while preserving essential system functionality

# Enable error tracing and exit on error
set -ex

# Install required packages
apt-get update
apt-get install -y busybox xz-utils
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /usr/share/doc /usr/share/man /etc/rc?.d /etc/systemd

# Store original /bin/sh if it exists
if [ -f /bin/sh ]; then
    cp /bin/sh /bin/sh.original
fi

# Find busybox path
BUSYBOX_PATH=$(command -v busybox)
echo "Using busybox at: $BUSYBOX_PATH"

# Create symlink for /bin/sh to busybox
ln -snf $BUSYBOX_PATH /bin/sh
files="/bin/sh $BUSYBOX_PATH"

# Get architecture information
arch=$(uname -m)
darch=$(uname -m | sed 's/_/-/')

# Find required libraries and ensure they're protected
IFS=" " read -r -a libs <<< "$(ldd $files 2>/dev/null | awk '{print $3;}' | grep '^/' | sort -u)"
critical_libs=(/lib/ld-linux-"$darch".so.* \
/lib/"$arch"-linux-gnu/ld-linux-"$darch".so.* \
/lib/"$arch"-linux-gnu/libnsl.so.* \
/lib/"$arch"-linux-gnu/libnss_compat.so.* \
/lib64/ld-linux-*.so.* \
/lib/"$arch"-linux-gnu/libc.so.* \
/lib/"$arch"-linux-gnu/libdl.so.* \
/lib/"$arch"-linux-gnu/libpthread.so.* \
/lib/"$arch"-linux-gnu/librt.so.*)

# Combine critical libraries
libs=("${libs[@]}" "${critical_libs[@]}")

# Create exclude list with all critical files
critical_files="/bin/sh $BUSYBOX_PATH /var/run /var/spool /bin/bash /usr/bin/env"
(echo "$critical_files" "${libs[@]}" | tr ' ' '\n' && realpath $files "${libs[@]}" 2>/dev/null) | sort -u | sed 's/^\///' > /exclude

# Show what's being excluded for debugging
echo "Files being excluded from removal:"
cat /exclude

# Clean up symlinks
find /etc/alternatives -xtype l -delete 2>/dev/null || true

# Directories to save
save_dirs=(usr lib var bin sbin etc/ssl etc/init.d etc/alternatives etc/apt)

# Archive essential files
XZ_OPT=-e9v tar -X /exclude -cpJf a.tar.xz "${save_dirs[@]}" 2>/dev/null || true

# Clean Python packages
rm -fr /usr/local/lib/python* 2>/dev/null || true

# Generate list of files to remove while protecting critical files
echo "Generating list of files to safely remove..."
find_output=$(mktemp)

# Find all non-directory files in save_dirs
for dir in "${save_dirs[@]}"; do
    find /$dir -type f 2>/dev/null >> "$find_output" || true
done

# Create list of files to remove
files_to_remove=$(mktemp)
grep -vxFf /exclude "$find_output" > "$files_to_remove" || true

# Remove files in batches to avoid command line length limits
echo "Removing unnecessary files..."
xargs -a "$files_to_remove" -r -n 100 rm -f 2>/dev/null || true

# Clean up temp files
rm -f "$find_output" "$files_to_remove" || true

# Install busybox utilities
$BUSYBOX_PATH --install -s

# Clean up empty directories, but carefully
echo "Cleaning empty directories..."
for dir in "${save_dirs[@]}"; do
    find /$dir -type d -empty -delete 2>/dev/null || true
done

# Verify /bin/sh still exists and is executable
if [ ! -x /bin/sh ]; then
    echo "ERROR: /bin/sh was removed or is not executable!"
    # Restore original if we saved it
    if [ -f /bin/sh.original ]; then
        echo "Restoring original /bin/sh"
        mv /bin/sh.original /bin/sh
        chmod +x /bin/sh
    else
        echo "Creating new /bin/sh symlink"
        ln -sf $BUSYBOX_PATH /bin/sh
    fi
fi

echo "Compression completed successfully!"
