#!/usr/bin/env bash
set -e

echo "=================================================="
echo " rclone basics installer  /  rclone 基础安装脚本"
echo " Tested on Debian / Ubuntu. 其他发行版请自行确认。"
echo "=================================================="
echo

# 更新软件源（可按需注释掉）
apt update -y || sudo apt update -y

# 安装基础依赖
apt install -y curl unzip || sudo apt install -y curl unzip

echo
echo ">> 使用 rclone 官方安装脚本安装 / 升级 rclone ..."
curl -fsSL https://rclone.org/install.sh | bash || \
curl -fsSL https://rclone.org/install.sh | sudo bash

echo
echo "当前 rclone 版本 / rclone version:"
rclone version || sudo rclone version || true

echo
echo "=================================================="
echo " 安装完成（Install finished）"
echo " 接下来建议手动执行："
echo "   rclone config"
echo " 按提示新增 OneDrive 等网盘的 remote。"
echo "=================================================="
