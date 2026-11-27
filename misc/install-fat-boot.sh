#! /bin/sh

# Fill an ESOS FAT boot partition when the build kernel cannot mount vfat.
# The boot tree is already staged in BOOTDIR (kernels, initramfs, grub.cfg).
# GRUB is embedded in the post-MBR gap, and the same tree is copied with mtools.

set -eu

if [ "$#" -ne 7 ]; then
    echo "Usage: $0 DISK PART BOOTDIR GRUB_PC GRUB_EFI MKIMAGE BIOS_SETUP" >&2
    exit 1
fi

DISK="$1"
PART="$2"
BOOTDIR="$3"
GRUB_PC="$4"
GRUB_EFI="$5"
MKIMAGE="$6"
BIOS_SETUP="$7"

if ! command -v mcopy > /dev/null 2>&1; then
    echo "ERROR: mtools is required to fill the boot partition without vfat." >&2
    exit 1
fi

echo "### Installing GRUB and copying the boot tree onto the FAT partition..."
mkdir -p "$BOOTDIR/grub/i386-pc" "$BOOTDIR/grub/x86_64-efi" "$BOOTDIR/EFI/BOOT"
cp -a "$GRUB_PC/." "$BOOTDIR/grub/i386-pc/"
cp -a "$GRUB_EFI/." "$BOOTDIR/grub/x86_64-efi/"

"$MKIMAGE" -O i386-pc -d "$GRUB_PC" -p '(hd0,msdos1)/grub' \
    -o "$BOOTDIR/grub/i386-pc/core.img" \
    biosdisk part_msdos fat normal configfile search search_label \
    serial terminal linux gzio boot cat echo test true
"$MKIMAGE" -O x86_64-efi -d "$GRUB_EFI" -p /grub \
    -o "$BOOTDIR/EFI/BOOT/BOOTX64.EFI" \
    part_msdos fat normal configfile search search_label \
    serial terminal linux gzio efi_gop efi_uga font gfxterm \
    boot cat echo test true

MTOOLS_SKIP_CHECK=1 mcopy -s -i "$PART" "$BOOTDIR"/* ::/
"$BIOS_SETUP" -s -d "$BOOTDIR/grub/i386-pc" "$DISK"
echo "### FAT boot partition is populated."
