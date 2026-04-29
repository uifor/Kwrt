#!/bin/bash
# devices/common/diy.sh
# 修改说明：
#   - 移除 "by Kiddin'" 版本追加
#   - 移除全局 OpenWrt → Kwrt 品牌替换
#   - 移除默认 IP 从 192.168.1.x 改为 10.0.0.x（恢复为 192.168.1.1）
#   - 保留所有功能性修改（feeds、补丁、包列表、构建优化等）

# ===================== Feeds 配置 =====================
# 添加 kiddin9 自定义包源
sed -i '1i src-git kiddin9 https://github.com/kiddin9/kwrt-packages.git;main' feeds.conf.default
# 移除不需要的 telephony feed
sed -i '/telephony/d' feeds.conf.default
# 修改包路径为按内核版本区分
sed -i 's|targets/%S/packages|targets/%S/$(LINUX_VERSION)|g' include/feeds.mk
# 禁用 feed 安装后的自动 config 刷新
sed -i '/refresh_config/d' scripts/feeds
# 安装 feeds
./scripts/feeds update -a
./scripts/feeds install -a -p kiddin9 -f
./scripts/feeds install -a

# ===================== 版本信息（去除品牌，保留原始 OpenWrt 标识）=====================
# 原始行：sed -i 's/%C"/\%C by Kiddin'"'"'"/g' package/base-files/files/etc/openwrt_release
# ↑ 已删除，不再追加 "by Kiddin'" 字样

# 保留 bench.log、移除 profile 相关 conffiles
echo "/etc/bench.log" >> package/base-files/files/etc/sysupgrade.conf
sed -i '/\/etc\/profile/d' package/base-files/CONTROL/conffiles 2>/dev/null || true
sed -i '/\/etc\/shinit/d' package/base-files/CONTROL/conffiles 2>/dev/null || true
sed -i '/conffiles.*profile/d' package/base-files/Makefile
sed -i '/conffiles.*shinit/d' package/base-files/Makefile

# 默认 LAN IP 保持 192.168.1.x（不修改）
# 原始行：sed -i 's/192.168.1/10.0.0/g' package/base-files/files/bin/config_generate
# ↑ 已删除，保留 OpenWrt 默认 192.168.1.1

# ===================== 记录构建版本时间戳 =====================
date +%s > package/base-files/files/etc/version.date

# ===================== 构建系统优化 =====================
# 确保 opkg host 优先编译
sed -i 's|^include \$(INCLUDE_DIR)/package.mk|include $(INCLUDE_DIR)/package.mk\ndefine Build/Prepare\n\t$(call Build/Prepare/Default)\nendef|' package/Makefile 2>/dev/null || true
sed -i 's|compile: $(if $(CONFIG_PACKAGE_opkg),,package/opkg/host/compile)|compile: package/opkg/host/compile|g' package/Makefile 2>/dev/null || true

# 移除 procd-ujail（提升兼容性）
sed -i '/procd-ujail/d' include/target.mk

# 强制 vermagic 为固定值（允许跨版本加载内核模块）
sed -i 's/$(shell.*vermagic.*)/1/g' include/kernel-defaults.mk 2>/dev/null || true

# ===================== 从 immortalwrt 拉取增强组件 =====================
# video.mk
wget -qO include/video.mk \
  https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-24.10/include/video.mk

# nftables fullcone NAT 补丁
mkdir -p package/network/utils/nftables/patches
wget -qO package/network/utils/nftables/patches/002-fullcone.patch \
  https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-24.10/package/network/utils/nftables/patches/002-fullcone-nat-support.patch
wget -qO package/network/utils/nftables/patches/001-deps.patch \
  https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-24.10/package/network/utils/nftables/patches/001-nftables-remove-static-lib-deps.patch

# libnftnl fullcone 表达式支持
mkdir -p package/libs/libnftnl/patches
wget -qO package/libs/libnftnl/patches/001-fullcone.patch \
  https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-24.10/package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch

# wireless-regdb：自定义发射功率 / DFS 设置
mkdir -p package/firmware/wireless-regdb/patches
wget -qO package/firmware/wireless-regdb/patches/600-custom.patch \
  https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-24.10/package/firmware/wireless-regdb/patches/600-custom-regulatory.patch

# 扩展内核配置选项
wget -qO Config-kernel-extra.in \
  https://raw.githubusercontent.com/immortalwrt/immortalwrt/openwrt-24.10/config/Config-kernel.in
cat Config-kernel-extra.in >> config/Config-kernel.in && rm Config-kernel-extra.in

# 更新版本的 OpenSSL
git_clone_path https://github.com/immortalwrt/immortalwrt openwrt-24.10 package/libs/openssl package/libs/openssl

# 增强版 PPP
git_clone_path https://github.com/immortalwrt/immortalwrt openwrt-24.10 package/network/services/ppp package/network/services/ppp

# ===================== kwrt-packages 同步等待 =====================
# 等待上游 kwrt-packages 仓库的最新 Actions 运行完成，确保包版本一致
if [ -n "$REPO_TOKEN" ]; then
  while true; do
    status=$(curl -H "Authorization: token $REPO_TOKEN" -s \
      "https://api.github.com/repos/kiddin9/kwrt-packages/actions/runs" \
      | jq -r '.workflow_runs[0].status')
    [ "$status" == "completed" ] && break
    [ "$status" == "in_progress" ] || [ "$status" == "queued" ] || break
    echo "等待 kwrt-packages 更新完成 (status: $status)，5秒后重试..."
    sleep 5
  done
fi

# ===================== 从 coolsnowwolf/lede 拉取优化补丁 =====================
# 内核优化 hack 补丁（6.6）
git_clone_path https://github.com/coolsnowwolf/lede master target/linux/generic/hack-6.6 target/linux/generic/hack-6.6-lede
mv target/linux/generic/hack-6.6-lede/* target/linux/generic/hack-6.6/ 2>/dev/null || true
rm -rf target/linux/generic/hack-6.6-lede

# 增强版 fstools（替换上游版本）
git_clone_path https://github.com/coolsnowwolf/lede master package/system/fstools package/system/fstools

# TCP window 检查绕过补丁
mkdir -p target/linux/generic/hack-6.6
wget -qO target/linux/generic/hack-6.6/613-netfilter_optional_tcp_window_check.patch \
  https://raw.githubusercontent.com/coolsnowwolf/lede/master/target/linux/generic/hack-6.6/613-netfilter_optional_tcp_window_check.patch

# 移除 Realtek LED 冲突补丁
find target/linux/generic -name '767-net-phy-realtek-add-led*' -delete 2>/dev/null || true

# ===================== 默认软件包扩展 =====================
# 在 DEFAULT_PACKAGES 基础上追加常用包
sed -i 's|^DEFAULT_PACKAGES:=|DEFAULT_PACKAGES:= \
  luci-base luci-compat luci-lib-ipkg luci-lib-fs \
  luci-app-advancedplus luci-app-firewall luci-app-package-manager \
  luci-app-upnp luci-app-syscontrol luci-proto-wireguard \
  luci-app-wizard luci-app-log-viewer luci-app-fan luci-app-filemanager \
  coremark wget-ssl curl autocore htop nano bash openssh-sftp-server \
  block-mount resolveip ds-lite swconfig \
  zram-swap kmod-lib-zstd kmod-tcp-bbr \
|' include/target.mk

# ===================== 全局品牌替换（已禁用）=====================
# 原始行（已删除，不再将 OpenWrt 替换为 Kwrt）：
# sed -i 's/OpenWrt/Kwrt/g' \
#   package/base-files/files/bin/config_generate \
#   package/base-files/image-config.in \
#   package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc \
#   config/Config-images.in \
#   Config.in \
#   include/u-boot.mk \
#   include/version.mk
