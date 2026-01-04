# Version: v2.2.2
# Build: 2026-01-05
#!/bin/bash
set -e

FILE="modules/wp/install-ols-wp-standard.sh"

echo "=== 开始修复 install-ols-wp-standard.sh ==="

# 1. 检查文件是否存在
if [ ! -f "$FILE" ]; then
    echo "错误：找不到文件 $FILE"
    echo "请确保你在 hz-oneclick 仓库根目录下运行此命令。"
    exit 1
fi

# 2. 修复 PHP 参数 (64M -> 128M)
echo "-> 修正 PHP post_max_size..."
sed -i 's/echo "post_max_size = 64M"/echo "post_max_size = 128M"/' "$FILE"

# 3. 移除 Lite 档位的降级逻辑
#    逻辑：找到包含 TIER_LITE 的if块，并删除它及接下来的 3 行
echo "-> 移除 Lite 档位降级代码..."
sed -i '/if \[ "\$tier" = "\$TIER_LITE" \]; then/,+3d' "$FILE"

# 4. 插入权限加固 (chmod 600)
#    逻辑：在 'find ... chmod 644' 这一行后面插入安全代码块
echo "-> 插入 wp-config.php 权限加固代码..."

# 定义要插入的代码块 (使用临时文件避免转义地狱)
cat > /tmp/security_patch.txt <<EOF

    # [Security] Hardening wp-config.php
    if [ -f "\${doc_root}/wp-config.php" ]; then
        chown nobody:nogroup "\${doc_root}/wp-config.php"
        chmod 600 "\${doc_root}/wp-config.php"
        log_info "已加固 wp-config.php (chmod 600)。"
    fi
EOF

# 使用 sed 读取临时文件内容并在目标行后插入
sed -i '/find "\$base" -type f -exec chmod 644 {} +/r /tmp/security_patch.txt' "$FILE"
rm /tmp/security_patch.txt

echo "=== 修复完成！ ==="
echo "请执行 git diff 查看变更，然后提交代码。"
