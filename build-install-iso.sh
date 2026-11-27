#! /bin/sh

# Build a bootable ESOS install ISO from this tree.
# The long compile is the chroot build. --check only verifies the host tools
# and prints the package pins that the image will use.

set -eu

usage() {
    echo "Usage: $(basename "$0") [--check] [-j N]"
    echo "  --check   verify host tools and print image pins, then stop"
    echo "  -j N      parallel jobs for make and the chroot build"
    echo "The build itself must run as root. The ISO is written in this directory."
    exit 1
}

JOBS="$(nproc 2> /dev/null || echo 4)"
CHECK_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        -j)
            [ $# -ge 2 ] || usage
            JOBS="$2"
            shift 2
            ;;
        -j*)
            JOBS="${1#-j}"
            shift
            ;;
        -h|--help) usage ;;
        *)
            echo "Unknown argument: $1"
            usage
            ;;
    esac
done

case "$JOBS" in
    ''|*[!0-9]*)
        echo "Job count must be a positive integer."
        exit 1
        ;;
esac

ROOT="$(readlink -f "$(dirname "$0")")"
cd "$ROOT"

missing=""
for tool in autoconf gcc g++ make wget git patch rsync cpio gzip xz zip \
    sfdisk losetup kpartx mksquashfs mkfs.vfat mkfs.ext4; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        missing="$missing $tool"
    fi
done
if ! command -v genisoimage > /dev/null 2>&1 && \
    ! command -v xorriso > /dev/null 2>&1; then
    missing="$missing genisoimage"
fi

echo "### Image pins"
grep -E '^[[:space:]]+(linux-5\.|openssl-|scst-3|glibc-2\.|Python-3)' \
    Makefile.in || true
if [ -f dist-upstreams.txt ]; then
    echo "### Upstream fallback when the ESOS mirror misses: dist-upstreams.txt"
fi
echo

if [ -n "$missing" ]; then
    echo "ERROR: missing host tools:$missing"
    echo "Debian/Ubuntu packages:"
    echo "  sudo apt-get install -y autoconf build-essential wget fdisk \\"
    echo "    genisoimage kpartx dosfstools e2fsprogs squashfs-tools \\"
    echo "    cpio rsync git patch zip xz-utils bison flex texinfo gawk"
    exit 1
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "### Host tools are present."
    echo "### Build the install ISO with: sudo $0 -j $JOBS"
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: the ISO build must run as root (symlink /tools, chroot, loop devices)."
    echo "Re-run: sudo $0 -j $JOBS"
    exit 1
fi

echo "### Generating configure..."
autoconf
echo "### Configuring..."
./configure
echo "### Bootstrap (fetch, extract, toolchain)..."
make -j"$JOBS" symlink
make -j"$JOBS" -w -Orecurse
echo "### Chroot build..."
./chroot_build.sh -j"$JOBS" -w -Orecurse
rm -f /tools
echo "### Disk image..."
make image
echo "### Install ISO..."
./esos2iso.sh isolinux

iso="$(echo ./*-*.iso)"
echo "### Install ISO ready: ${ROOT}/${iso}"
