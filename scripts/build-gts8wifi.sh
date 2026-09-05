#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out/gts8wifi}"
VARIANT="${TARGET_BUILD_VARIANT:-user}"
DEFCONFIG_ONLY=0
TARGETS=()

while (($#)); do
	case "$1" in
		--variant)
			VARIANT="${2:?missing variant}"
			shift 2
			;;
		--defconfig-only)
			DEFCONFIG_ONLY=1
			shift
			;;
		--out-dir)
			OUT_DIR="${2:?missing output directory}"
			shift 2
			;;
		--)
			shift
			TARGETS+=("$@")
			break
			;;
		*)
			TARGETS+=("$1")
			shift
			;;
	esac
done

if [[ "${VARIANT}" != "user" && "${VARIANT}" != "userdebug" && "${VARIANT}" != "eng" ]]; then
	echo "Unsupported variant: ${VARIANT}" >&2
	exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
	echo "clang is required" >&2
	exit 1
fi

if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
	echo "aarch64-linux-gnu-gcc is required" >&2
	exit 1
fi

mkdir -p "${OUT_DIR}"

declare -a make_args=(
	"O=${OUT_DIR}"
	"ARCH=arm64"
	"CC=clang"
	"CROSS_COMPILE=aarch64-linux-gnu-"
	"CLANG_TRIPLE=aarch64-linux-gnu-"
)

if command -v ld.lld >/dev/null 2>&1; then
	make_args+=("LLVM=1" "LLVM_IAS=1")
else
	make_args+=("LD=ld.bfd")
fi

declare -a fragments=(
	"${ROOT_DIR}/arch/arm64/configs/vendor/waipio_sec_defconfig"
	"${ROOT_DIR}/lego.config"
	"${ROOT_DIR}/arch/arm64/configs/vendor/waipio_nethunter.config"
)

if [[ "${VARIANT}" != "user" ]]; then
	fragments+=("${ROOT_DIR}/arch/arm64/configs/vendor/waipio_sec_${VARIANT}_defconfig")
fi

make -C "${ROOT_DIR}" "${make_args[@]}" vendor/waipio-gki_defconfig
KCONFIG_CONFIG="${OUT_DIR}/.config" \
ARCH=arm64 \
"${ROOT_DIR}/scripts/kconfig/merge_config.sh" \
	-O "${OUT_DIR}" \
	-m -r -y \
	"${ROOT_DIR}/arch/arm64/configs/vendor/waipio-gki_defconfig" \
	"${fragments[@]}"
make -C "${ROOT_DIR}" "${make_args[@]}" olddefconfig

if ((DEFCONFIG_ONLY)); then
	echo "Generated ${OUT_DIR}/.config"
	exit 0
fi

if ((${#TARGETS[@]} == 0)); then
	TARGETS=(Image modules dtbs)
fi

make -C "${ROOT_DIR}" "${make_args[@]}" -j"$(nproc)" "${TARGETS[@]}"