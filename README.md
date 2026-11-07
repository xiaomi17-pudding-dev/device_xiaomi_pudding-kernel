# device_xiaomi_pudding-kernel

Prebuilt stock kernel, device trees and kernel modules for the **Xiaomi 17** (`pudding`,
Snapdragon 8 Elite Gen 5 / SM8850, platform `canoe`). Used by the `pudding` device tree
until a source-built kernel replaces it.

## Source firmware
Everything here is taken unmodified from the official Xiaomi fastboot ROM
**HyperOS OS3.0.335.0.XPCEUXM** (EEA global, build 20260929):

`pudding_eea_global_images_OS3.0.335.0.XPCEUXM_20260929.0000.00_17.0_eea_af0aef5577.tgz`
(sha256 `cc9129729b64e46cfc245c4dc20d8ec25887feae7bc61e89b256393fa7124fa8`)

Kernel: `6.12.69-android16-6-gc8366273ff73-ab15162216-4k`, the GKI build of
[ACK](https://android.googlesource.com/kernel/common) tag `android16-6.12-2026-03_r7`
(`c8366273ff73f3794018cd64ea13cbd6f5f5286a`).

## Contents
| Path | From | Notes |
|---|---|---|
| `kernel` | `boot.img` | Uncompressed ARM64 `Image`, 4K pages |
| `dtb/NN_dtbdump_<model>.dtb` | `vendor_boot.img` | The 12 DTBs of the stock blob, one file each; `BOARD_PREBUILT_DTBIMAGE_DIR` concatenates them in name order, which gives the stock blob byte for byte |
| `dtbo.img` | `dtbo.img` | DT table only (2 entries); AVB footer and padding removed |
| `vendor_ramdisk/` | `vendor_boot.img` ramdisk `lib/modules` | 462 modules; `modules.load` (first stage), `modules.load.recovery`, `modules.blocklist` |
| `vendor_dlkm/` | `vendor_dlkm` partition `lib/modules` | 403 modules; `modules.load`, `modules.blocklist`, `system_dlkm.modules.blocklist` |
| `system_dlkm/` | `system_dlkm` partition (flattened) | 103 GKI modules; `modules.load` |
| `kernel-headers/` | Kernel sources, see below | Installed kernel UAPI headers for the Qualcomm HALs built from source |

Generated files (`modules.dep`, `modules.alias`, `modules.softdep`, …) are not stored; the
build regenerates them with `depmod`.

Boot image facts the device tree must match: boot header v4, vendor_boot page size 4096,
LZ4 (legacy) ramdisks, dedicated A/B `recovery` partition.

## Use
Add this repo to your local manifest (see
[local_manifests_pudding](https://github.com/xiaomi17-pudding-dev/local_manifests_pudding))
at `device/xiaomi/pudding-kernel`. The device tree only names the directory; the common
tree's [`kernel/kernel-platform.mk`](https://github.com/xiaomi17-pudding-dev/device_xiaomi_sm8850-common/blob/lineage-24.0/kernel/kernel-platform.mk)
sets up the kernel headers, `dtb/`, `dtbo.img` and the three module sets from it:

```make
# BoardConfig.mk (before including BoardConfigCommon.mk)
KERNEL_PREBUILT_DIR := device/xiaomi/pudding-kernel

# device.mk
PRODUCT_COPY_FILES += device/xiaomi/pudding-kernel/kernel:kernel
```

Keep the kernel and all three module sets from the **same** firmware: the vendor modules are
built against this exact GKI kernel.

## Kernel headers
The Qualcomm HALs that LineageOS builds from source include kernel UAPI headers of the
Qualcomm drivers (for example `display/media/mmm_color_fmt.h`, `audio/linux/msm_audio.h`).
LineageOS generates them with `make headers_install` in `TARGET_KERNEL_SOURCE`;
`kernel-headers/Makefile` provides that target and copies the installed headers.

The headers were installed with the kernel's own `scripts/headers_install.sh`, in this
order (later sources replace earlier files of the same name):

| Source | Revision | Part |
|---|---|---|
| [kernel/common](https://android.googlesource.com/kernel/common) | `android16-6.12-2026-03_r7` (`c8366273ff73`), the source of the stock GKI kernel | `make ARCH=arm64 headers_install` (980 files) |
| [android_kernel_xiaomi_sm8850](https://github.com/xiaomi17-pudding-dev/android_kernel_xiaomi_sm8850) | `popsicle-w-oss` (`45705be1220b`), Xiaomi's msm kernel | `include/uapi` (19 files) |
| [LineageOS/android_kernel_qcom_sm8850-modules](https://github.com/LineageOS/android_kernel_qcom_sm8850-modules) | `lineage-24.0` (`f2ecb6a09ea5`) | every `*/include/uapi` directory (61 files) |

To regenerate (from the three trees above):

```bash
make -C common ARCH=arm64 O=$OUT headers_install
cd $OUT
for d in msm-kernel/include/uapi $(find modules -type d -path '*/include/uapi' | sort); do
  (cd "$d" && find . -name '*.h') | while read -r f; do
    mkdir -p "usr/include/$(dirname "$f")"
    sh common/scripts/headers_install.sh "$d/$f" "usr/include/$f"
  done
done
cp -a usr/include/. kernel-headers/   # keep kernel-headers/Makefile
```

The LineageOS rule only tracks `Makefile`, `include/` and `arch/` of `TARGET_KERNEL_SOURCE`,
so after updating the headers remove
`out/soong/.intermediates/vendor/lineage/build/soong/generated_kernel_includes` once to have
them regenerated.

## Updating to a new firmware
`extract-files.sh` recreates everything above except `kernel-headers/` from an unpacked
fastboot ROM: `boot.img`, `vendor_boot.img` and `dtbo.img` anywhere below the dump, the
`vendor_dlkm` and `system_dlkm` partitions extracted as `<dump>/vendor_dlkm` and
`<dump>/system_dlkm` (`lpunpack` for `super.img`, `fsck.erofs --extract` for the
partitions). Run it from the synced Android tree (it uses AOSP
`system/tools/mkbootimg/unpack_bootimg.py`; needs `python3`, `lz4` and `cpio`):

```bash
cd device/xiaomi/pudding-kernel
./extract-files.sh <dump>
git status   # review: kernel, dtb/, dtbo.img and the module directories
```

Then update the firmware name, checksum and kernel version in this README, and the kernel
headers if the kernel changed (see above). The vendor modules only load on the kernel they
were built for: always update kernel and modules together, from the same firmware.

## License
The kernel and GKI modules are GPL-2.0 (ACK). Vendor modules are distributed as shipped by
Xiaomi in the firmware above.
