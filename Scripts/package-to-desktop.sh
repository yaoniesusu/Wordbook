#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
	export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
else
	echo "错误：未找到 /Applications/Xcode.app。请先安装完整 Xcode，再重新运行打包脚本。" >&2
	exit 1
fi

# 使用「真实登录用户」的主目录，避免 sudo 时写到 /var/root/Desktop 导致你在自己桌面看不到。
resolve_real_home() {
	local uid
	uid="$(id -u)"
	if [[ "$uid" -eq 0 ]]; then
		if [[ -z "${SUDO_USER:-}" ]]; then
			echo "" >&2
			echo "错误：正在以 root 运行且没有 SUDO_USER。" >&2
			echo "请不要使用 sudo；在「终端.app」里用你自己的账户直接执行本脚本。" >&2
			echo "若曾用 sudo 打包，应用可能在 /var/root/Desktop，你的桌面不会出现。" >&2
			exit 1
		fi
		local h
		h="$(/usr/bin/dscl . -read "/Users/${SUDO_USER}" NFSHomeDirectory 2>/dev/null | /usr/bin/sed -n 's/^NFSHomeDirectory: //p')"
		if [[ -n "$h" && -d "$h" ]]; then
			echo "$h"
			return
		fi
		echo "" >&2
		echo "错误：无法解析用户 ${SUDO_USER} 的主目录。" >&2
		exit 1
	fi
	echo "${HOME}"
}

REAL_HOME="$(resolve_real_home)"

# 桌面路径：优先手动指定；否则用「真实主目录」下的 Desktop（不存在则创建）。
resolve_desktop() {
	if [[ -n "${OUTPUT_DESKTOP:-}" ]]; then
		echo "${OUTPUT_DESKTOP}"
		return
	fi
	local d="${REAL_HOME}/Desktop"
	/bin/mkdir -p "$d"
	echo "$d"
}

echo "==> 当前用户: $(id -un)  uid=$(id -u)  REAL_HOME=${REAL_HOME}"

ICON_SRC="${ROOT}/Assets/AppIconSource.png"
ICON_OUT="${ROOT}/Scripts/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
	chmod +x "${ROOT}/Scripts/build-app-icon.sh"
	"${ROOT}/Scripts/build-app-icon.sh" "$ICON_SRC" "$ICON_OUT"
else
	echo "（未找到 ${ICON_SRC}，跳过自定义图标；可将 PNG 放到 Assets/AppIconSource.png）" >&2
fi

echo "==> swift build -c release (DEVELOPER_DIR=${DEVELOPER_DIR:-默认})"
if ! swift build -c release --product Wordbook; then
	echo "" >&2
	echo "编译失败：请安装 Xcode，并在终端执行：" >&2
	echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
	echo "然后重新运行本脚本（不要对脚本本身再加 sudo）。" >&2
	exit 1
fi

BIN_DIR="$(swift build -c release --show-bin-path)"
EXE="${BIN_DIR}/Wordbook"
if [[ ! -f "$EXE" ]]; then
	echo "找不到可执行文件: $EXE" >&2
	exit 1
fi

APP_NAME="单词本.app"
STAGE="${ROOT}/dist/${APP_NAME}"
rm -rf "${ROOT}/dist"
mkdir -p "${STAGE}/Contents/MacOS"
mkdir -p "${STAGE}/Contents/Resources"

cp "$EXE" "${STAGE}/Contents/MacOS/Wordbook"
chmod +x "${STAGE}/Contents/MacOS/Wordbook"
cp "${ROOT}/Scripts/Info.plist" "${STAGE}/Contents/Info.plist"
if [[ -f "$ICON_OUT" ]]; then
	cp "$ICON_OUT" "${STAGE}/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc codesign"
codesign --force --deep -s - "${STAGE}" 2>/dev/null || {
	echo "（codesign 跳过或失败，若无法打开请在 系统设置 → 隐私与安全性 中允许）"
}

DESKTOP="$(resolve_desktop)"
if [[ ! -d "$DESKTOP" || ! -w "$DESKTOP" ]]; then
	echo "错误：桌面目录不可写: ${DESKTOP:-空}" >&2
	echo "可手动指定：OUTPUT_DESKTOP=\"/完整/路径/到/桌面\" \"$0\"" >&2
	exit 1
fi

DEST="${DESKTOP%/}/${APP_NAME}"
echo "==> 桌面目录: ${DESKTOP}"
echo "==> 正在复制到: ${DEST}"
rm -rf "${DEST}"
/usr/bin/ditto "${STAGE}" "${DEST}"

if [[ ! -d "${DEST}" ]]; then
	echo "复制失败：目标不存在 ${DEST}" >&2
	exit 1
fi

# 在访达中定位到应用（避免「其实已复制但不知道在哪」）
if /usr/bin/open -R "${DEST}" 2>/dev/null; then
	echo "==> 已在访达中显示该应用。"
else
	echo "（无法自动打开访达；请手动打开桌面文件夹查找「单词本」）"
fi

if [[ "${LAUNCH_APP:-1}" != "0" ]]; then
	if /usr/bin/open "$DEST" 2>/dev/null; then
		echo "==> 已尝试启动「单词本」。"
	else
		echo "（无法自动启动应用；请双击图标运行。设置 LAUNCH_APP=0 可跳过启动。）"
	fi
fi

echo ""
echo "完成。"
echo "  应用路径: ${DEST}"
echo "  项目内副本: ${STAGE}"
echo ""
echo "若仍看不到：在访达按 ⌘⇧D；或检查「访达 → 设置 → 边栏」是否显示桌面。"
