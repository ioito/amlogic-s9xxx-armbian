#!/bin/sh
# ============================================================================
# 魔云腾 Q1 - 探测 SSD1306 OLED 所在的 I2C 总线与地址
# 用法:  sh q1-i2c-oled-probe.sh
# 说明:  扫描 i2c0..i2c8, 在每条总线上跑 i2cdetect -y -r <bus>,
#        报告出现 0x3c / 0x3d 的总线。魔云腾 Q1 的 OLED 多为 0x3c。
# 注意:  i2c0 (fd880000) 是 PMIC 总线, 上面会看到 rk8602@0x42 等属正常,
#        不要把 PMIC 地址当成 OLED。OLED 只认 0x3c / 0x3d。
# ============================================================================
set -u

if ! command -v i2cdetect >/dev/null 2>&1; then
    echo "[!] 未安装 i2c-tools, 正在安装..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y i2c-tools >/dev/null 2>&1
fi

echo "==================================================================="
echo "扫描魔云腾 Q1 全部 I2C 总线, 寻找 SSD1306 OLED (0x3c / 0x3d) ..."
echo "==================================================================="

found=0
# RK3588 在我们的 DTB 里使能的总线: i2c0(PMIC) i2c1 i2c4 i2c6 i2c7
for bus in 0 1 2 3 4 5 6 7 8; do
    dev="/dev/i2c-${bus}"
    [ -e "$dev" ] || continue
    echo "-------------------------------------------------------------------"
    echo "[bus ${bus}] 扫描中 (i2cdetect -y -r ${bus}) ..."
    out="$(i2cdetect -y -r "${bus}" 2>/dev/null)"
    # 高亮 0x3c / 0x3d 行
    echo "$out" | grep -E "^\\s*00:|\\b3c\\b|\\b3d\\b" || true
    if echo "$out" | grep -qE "\\b3c\\b"; then
        echo ">>> [命中] 在 i2c-${bus} 上发现 0x3c (SSD1306 标准地址)"
        found=1
        echo ">>> 把 q1-ssd1306.dts 里的 &i2c6 改成 &i2c${bus} 后重新编译即可。"
    fi
    if echo "$out" | grep -qE "\\b3d\\b"; then
        echo ">>> [命中] 在 i2c-${bus} 上发现 0x3d (ADDR 拉高地址)"
        found=1
        echo ">>> 把 q1-ssd1306.dts 里 reg = <0x3c> 改成 <0x3d>, &i2c6 改成 &i2c${bus}。"
    fi
done

echo "==================================================================="
if [ "$found" -eq 0 ]; then
    echo "[结果] 未发现 0x3c/0x3d。请检查: "
    echo "  1) OLED 排线/供电是否接好; "
    echo "  2) 用 sudo i2cdetect -y -r <bus> 手动逐条看; "
    echo "  3) 部分屏地址是 0x78 (8位) / 0x3c (7位), 内核 DT 用 7 位 0x3c。"
else
    echo "[结果] 已定位 OLED, 按上面提示修改 overlay 后编译安装。"
fi
echo "==================================================================="
