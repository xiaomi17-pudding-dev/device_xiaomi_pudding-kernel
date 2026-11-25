# device_xiaomi_pudding-kernel

Kernel prebuilts for the **Xiaomi 17** (`pudding`, Snapdragon 8 Elite Gen 5 / SM8850, platform
`canoe`), used by the `pudding` device tree:
- the GKI kernel and its 103 GKI modules, **built from source** (Android Common Kernel, see
  [GKI kernel](#gki-kernel-built-from-source));
- device trees and the vendor modules, taken from the stock firmware, except `arm_smmu.ko`
  (built from source, see [arm_smmu](#arm_smmu-built-from-source)).

## Source firmware
The device trees and vendor modules are taken unmodified from the official Xiaomi fastboot ROM
**HyperOS OS3.0.335.0.XPCEUXM** (EEA global, build 20260929):

`pudding_eea_global_images_OS3.0.335.0.XPCEUXM_20260929.0000.00_17.0_eea_af0aef5577.tgz`
(sha256 `cc9129729b64e46cfc245c4dc20d8ec25887feae7bc61e89b256393fa7124fa8`)

Its kernel is `6.12.69-android16-6-gc8366273ff73-ab15162216-4k`, Google's GKI build of
[ACK](https://android.googlesource.com/kernel/common) tag `android16-6.12-2026-03_r7`
(`c8366273ff73f3794018cd64ea13cbd6f5f5286a`). The kernel here is built from the newer ACK release
`android16-6.12-2026-09_r18` of the same KMI generation; the stock vendor modules load unchanged
(every symbol they import exists with the same CRC), except `arm_smmu.ko`, which is built from
source.

## Contents
| Path | From | Notes |
|---|---|---|
| `kernel` | Built from source | Uncompressed ARM64 `Image`, 4K pages: `6.12.92-android16-6-gea16424de190-4k` |
| `dtb/NN_dtbdump_<model>.dtb` | `vendor_boot.img` | The 12 DTBs of the stock blob, one file each; `BOARD_PREBUILT_DTBIMAGE_DIR` concatenates them in name order, which gives the stock blob byte for byte |
| `dtbo.img` | `dtbo.img` | DT table only (2 entries); AVB footer and padding removed |
| `vendor_ramdisk/` | `vendor_boot.img` ramdisk `lib/modules` | 462 modules; `modules.load` (first stage), `modules.load.recovery`, `modules.blocklist`; `arm_smmu.ko` is built from source |
| `vendor_dlkm/` | `vendor_dlkm` partition `lib/modules` | 403 modules; `modules.load`, `modules.blocklist`, `system_dlkm.modules.blocklist` |
| `system_dlkm/` | Built from source; `modules.load` from the `system_dlkm` partition | 103 GKI modules, signed by the same build as `kernel` |
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

The stock vendor modules are built against the GKI KMI of `android16-6.12-2026-03_r7`; `kernel` and
`system_dlkm/` must come from the **same** build (see below).

## GKI kernel (built from source)
`kernel` and `system_dlkm/*.ko` are a plain GKI build (`gki_defconfig`, no changes) of
[kernel/common](https://android.googlesource.com/kernel/common) tag
`android16-6.12-2026-09_r18` (`ea16424de190`), the newest android16-6.12 release.

Before moving to another tag, check that every symbol the stock vendor modules import
(`modprobe --dump-modversions`) is in the new `kernel_aarch64_Module.symvers` with the same CRC.

In a LineageOS or PixelOS tree the Kleaf kernel platform comes from the manifest snippet
`snippets/kernel-6.12.xml` (`kernel/platform/kernel-6.12`). Pin `kernel/common` to the tag in a
local manifest:

```xml
<manifest>
  <include name="manifests/snippets/kernel-6.12.xml" />
  <extend-project name="kernel/common" path="kernel/platform/kernel-6.12/common"
                  revision="refs/tags/android16-6.12-2026-09_r18" />
</manifest>
```

Then build (from the top of the Android tree) and copy:

```bash
python3 vendor/lineage/build/tools/kernel_kleaf_manifest.py 6.12 > /tmp/kernel-manifest.xml
cd kernel/platform/kernel-6.12
tools/bazel run --repo_manifest="$PWD:/tmp/kernel-manifest.xml" --config=stamp \
    //common:kernel_aarch64_dist -- --destdir=/tmp/gki-dist
cp /tmp/gki-dist/Image <this repo>/kernel
for ko in <this repo>/system_dlkm/*.ko; do cp "/tmp/gki-dist/${ko##*/}" "$ko"; done
```

The build signs the modules with a key it generates, and the kernel only trusts that key, so
always copy `Image` and all modules of one build together. Two builds differ only in that key:
the module contents are identical without their signature.

## arm_smmu (built from source)
`vendor_ramdisk/arm_smmu.ko` (the Qualcomm ARM SMMU driver, first stage) is built from
[LineageOS/android_kernel_qcom_sm8850](https://github.com/LineageOS/android_kernel_qcom_sm8850)
`lineage-24.0` (`557159b6a0d0`, CLO `KERNEL.PLATFORM.5.0.r1-19800`), target `canoe_perf`, against the
GKI kernel of this repo.

The stock module also contains the NVIDIA Tegra SMMU implementation (`nvidia_smmu_*`), which
imports `tegra_mc_probe_device` and `devm_tegra_memory_controller_get` from the kernel. ACK
changed the CRCs of both symbols in `android16-6.12-2026-06`, so the stock module no longer
loads on newer kernels and the device does not boot. The module built here is the same driver
without the Tegra part (`CONFIG_ARM_SMMU_NVIDIA` is off for `canoe`): apart from the 11
`nvidia_smmu_*` functions it defines the same functions as the stock module, has the same
dependencies (`qcom_iommu_util`, `iommu-logger`, `qcom-scm`) and exports no symbols.

Build (in a tree with the kernel platform and the three LineageOS `kernel/qcom/sm8850*` repos at
`kernel/platform/kernel-6.12/vendor/qcom/`, as `vendor/lineage/build/tasks/kernel.mk` uses them):

```bash
cd kernel/platform/kernel-6.12
tools/bazel run --cpu=arm64 --repo_manifest="$PWD:/tmp/kernel-manifest.xml" --config=stamp \
    --//build/kernel/kleaf:allow_ddk_unsafe_headers \
    //vendor/qcom/sm8850:canoe_perf_dist -- --destdir=/tmp/canoe-dist
cp /tmp/canoe-dist/arm_smmu.ko <this repo>/vendor_ramdisk/arm_smmu.ko
```

`extract-files.sh` keeps it (`SOURCE_BUILT_MODULES`).

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
`extract-files.sh` recreates `dtb/`, `dtbo.img`, `vendor_ramdisk/` and `vendor_dlkm/` from an
unpacked fastboot ROM: `vendor_boot.img` and `dtbo.img` anywhere below the dump, the
`vendor_dlkm` partition extracted as `<dump>/vendor_dlkm` (`lpunpack` for `super.img`,
`fsck.erofs --extract` for the partition). Run it from the synced Android tree (it uses AOSP
`system/tools/mkbootimg/unpack_bootimg.py`; needs `python3`, `lz4` and `cpio`):

```bash
cd device/xiaomi/pudding-kernel
./extract-files.sh <dump>
git status   # review: dtb/, dtbo.img and the module directories
```

Then update the firmware name and checksum in this README. If the stock kernel version changed,
rebuild `kernel` and `system_dlkm/` from the new tag (see above; the vendor modules need that
KMI) and take `system_dlkm/modules.load` from the new `system_dlkm` partition; update the
kernel headers if needed.

## License
The kernel and GKI modules are GPL-2.0 (ACK). Vendor modules are distributed as shipped by
Xiaomi in the firmware above.
