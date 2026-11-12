#!/bin/bash
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Extract the stock kernel prebuilts of the Xiaomi 17 (pudding) from an unpacked
# fastboot ROM:
#   kernel                   boot.img kernel
#   dtb/NN_dtbdump_*.dtb     the DTBs of vendor_boot.img, one file each (the build
#                            concatenates them again in name order)
#   dtbo.img                 dtbo.img without its AVB footer and padding
#   vendor_ramdisk/          vendor_boot.img ramdisk modules and load lists
#   vendor_dlkm/             vendor_dlkm partition modules and load lists
#   system_dlkm/             system_dlkm partition modules (flattened) and load list
# kernel-headers/ is not part of the firmware and is left untouched.
#
# Usage: ./extract-files.sh <dump>
#   <dump> holds boot.img, vendor_boot.img and dtbo.img (anywhere below it) and the
#   extracted vendor_dlkm and system_dlkm partitions as <dump>/vendor_dlkm and
#   <dump>/system_dlkm.
# Needs python3, lz4, cpio and unpack_bootimg.py of AOSP system/tools/mkbootimg (found
# in the Android source tree this repo is synced into, or set UNPACK_BOOTIMG).

set -e

MY_DIR="$(cd "${BASH_SOURCE%/*}" && pwd)"
ANDROID_ROOT="${MY_DIR}/../../.."
UNPACK_BOOTIMG="${UNPACK_BOOTIMG:-${ANDROID_ROOT}/system/tools/mkbootimg/unpack_bootimg.py}"

DUMP="${1%/}"
if [ -z "${DUMP}" ] || [ ! -d "${DUMP}" ]; then
    echo "Usage: ${0} <dump>" >&2
    exit 1
fi
if [ ! -f "${UNPACK_BOOTIMG}" ]; then
    echo "unpack_bootimg.py not found at ${UNPACK_BOOTIMG}; set UNPACK_BOOTIMG" >&2
    exit 1
fi

find_image() {
    local img
    img="$(find "${DUMP}" -name "${1}" -type f -print -quit)"
    [ -n "${img}" ] || { echo "${1} not found in ${DUMP}" >&2; exit 1; }
    echo "${img}"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Extracting from ${DUMP}:"

### Kernel
python3 "${UNPACK_BOOTIMG}" --boot_img "$(find_image boot.img)" \
    --out "${TMP_DIR}/boot" > /dev/null
cp -f "${TMP_DIR}/boot/kernel" "${MY_DIR}/kernel"
echo "  - kernel ($(strings "${MY_DIR}/kernel" | grep -m1 -o 'Linux version [^ ]*'))"

### DTBs: split the concatenated blob of vendor_boot into one file per DTB
python3 "${UNPACK_BOOTIMG}" --boot_img "$(find_image vendor_boot.img)" \
    --out "${TMP_DIR}/vendor_boot" > /dev/null
rm -rf "${MY_DIR}/dtb"
mkdir "${MY_DIR}/dtb"
python3 - "${TMP_DIR}/vendor_boot/dtb" "${MY_DIR}/dtb" << 'EOF'
import os, re, struct, sys

def model(fdt):
    # Value of the "model" property of the root node
    off_struct, off_strings = struct.unpack_from('>II', fdt, 8)
    p, depth = off_struct, 0
    while p < len(fdt):
        tok, = struct.unpack_from('>I', fdt, p)
        p += 4
        if tok == 1:  # FDT_BEGIN_NODE
            p = (fdt.index(b'\0', p) + 4) & ~3
            depth += 1
        elif tok == 2:  # FDT_END_NODE
            depth -= 1
            if depth == 0:
                break
        elif tok == 3:  # FDT_PROP
            length, nameoff = struct.unpack_from('>II', fdt, p)
            p += 8
            start = off_strings + nameoff
            name = fdt[start:fdt.index(b'\0', start)]
            value = fdt[p:p + length]
            p = (p + length + 3) & ~3
            if depth == 1 and name == b'model':
                return value.rstrip(b'\0').decode()
        elif tok != 4:  # not FDT_NOP
            break
    return 'unknown'

blob = open(sys.argv[1], 'rb').read()
offset, index = 0, 0
while offset < len(blob):
    magic, size = struct.unpack_from('>II', blob, offset)
    if magic != 0xd00dfeed:
        sys.exit(f'no DTB at offset {offset}')
    fdt = blob[offset:offset + size]
    index += 1
    name = '%02d_dtbdump_%s.dtb' % (index, re.sub(r'[ /]', '_', model(fdt)))
    open(os.path.join(sys.argv[2], name), 'wb').write(fdt)
    print('  - dtb/' + name)
    offset += size
EOF
cat "${MY_DIR}"/dtb/*.dtb | cmp -s - "${TMP_DIR}/vendor_boot/dtb" || {
    echo "dtb/*.dtb do not concatenate to the stock DTB blob" >&2
    exit 1
}

### DTBO: keep the DT table only (total_size in its header)
python3 - "$(find_image dtbo.img)" "${MY_DIR}/dtbo.img" << 'EOF'
import struct, sys
data = open(sys.argv[1], 'rb').read()
magic, total_size = struct.unpack_from('>II', data, 0)
if magic != 0xd7b7ab1e:
    sys.exit('dtbo.img: no DT table header')
open(sys.argv[2], 'wb').write(data[:total_size])
EOF
echo "  - dtbo.img"

### Kernel modules
copy_modules() {
    local src="${1}" dst="${MY_DIR}/${2}"
    shift 2
    rm -rf "${dst}"
    mkdir "${dst}"
    find "${src}" -name '*.ko' -type f -exec cp {} "${dst}/" \;
    for list in "$@"; do
        cp "${src}/${list}" "${dst}/"
    done
    echo "  - ${dst##*/}/: $(find "${dst}" -name '*.ko' | wc -l) modules, $*"
}

# vendor_boot ramdisk (first stage and recovery)
mkdir "${TMP_DIR}/vendor_ramdisk"
lz4 -dc "${TMP_DIR}/vendor_boot/vendor_ramdisk00" | \
    (cd "${TMP_DIR}/vendor_ramdisk" && cpio -idm --quiet)
copy_modules "${TMP_DIR}/vendor_ramdisk/lib/modules" vendor_ramdisk \
    modules.load modules.load.recovery modules.blocklist

# vendor_dlkm
copy_modules "${DUMP}/vendor_dlkm/lib/modules" vendor_dlkm \
    modules.load modules.blocklist system_dlkm.modules.blocklist

# system_dlkm: GKI modules from the versioned module directory, flattened
SYSTEM_DLKM="$(find "${DUMP}/system_dlkm/lib/modules" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[ -n "${SYSTEM_DLKM}" ] || { echo "no module directory in ${DUMP}/system_dlkm/lib/modules" >&2; exit 1; }
copy_modules "${SYSTEM_DLKM}" system_dlkm modules.load

echo "Done."
