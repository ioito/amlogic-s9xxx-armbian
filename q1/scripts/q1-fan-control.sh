#!/bin/sh
# ============================================================================
# 魔云腾 Q1 - pwm-fan 用户态温控兜底脚本
# ----------------------------------------------------------------------------
# 背景: 主线内核的 pwm-fan 驱动不支持 rockchip,temp-trips, 依赖 thermal
#       cooling-maps 自动调速。我们已在 DTB 的 soc-thermal/cooling-maps
#       里把 pwm-fan 关联为冷却设备(75C->state2, 85C->state5), 正常情况下
#       内核会自动调速。本脚本作为【兜底】: 万一 thermal 自动控制不生效,
#       用它按温度直接写 cooling_device 的 cur_state。
#
# pwm-fan cooling-levels = <0 50 100 150 200 255>, 对应 state 0..5:
#   state 0 = 停转, 1 = 20%, 2 = 40%, 3 = 60%, 4 = 80%, 5 = 100%
#
# 安装为 systemd 服务 (见文件末尾注释) 后随开机运行。
# ============================================================================
set -u

# 找 pwm-fan 对应的 cooling_device 序号
find_fan_cdev() {
    for d in /sys/class/thermal/cooling_device*; do
        [ -e "$d/type" ] || continue
        if grep -q "pwm-fan" "$d/type" 2>/dev/null; then
            basename "$d" | sed 's/cooling_device//'
            return 0
        fi
    done
    return 1
}

# 找 SoC 温度(毫摄氏度)。优先 thermal zone "soc-thermal", 否则取第一个可读 sensor。
read_temp_mc() {
    for z in /sys/class/thermal/thermal_zone*; do
        [ -e "$z/type" ] || continue
        if grep -q "soc-thermal\|soc" "$z/type" 2>/dev/null; then
            cat "$z/temp" 2>/dev/null && return 0
        fi
    done
    # 兜底: 取第一个能读到的 temp
    cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null
}

FAN="$(find_fan_cdev)"
if [ -z "$FAN" ]; then
    echo "[!] 未找到 pwm-fan cooling_device, 检查 DTB 是否生效: cat /sys/class/thermal/cooling_device*/type"
    exit 1
fi
CDEV="/sys/class/thermal/cooling_device${FAN}/cur_state"
echo "[*] pwm-fan cooling_device = cooling_device${FAN}"

# 温度 -> state 映射 (摄氏度):
#   <50C -> 0(停)   50-60 -> 1(20%)   60-65 -> 2(40%)
#   65-70 -> 3(60%) 70-80 -> 4(80%)   >=80 -> 5(100%)
state_for_temp_c() {
    t="$1"
    if   [ "$t" -lt 50 ]; then echo 0
    elif [ "$t" -lt 60 ]; then echo 1
    elif [ "$t" -lt 65 ]; then echo 2
    elif [ "$t" -lt 70 ]; then echo 3
    elif [ "$t" -lt 80 ]; then echo 4
    else echo 5
    fi
}

last=-1
while true; do
    mc="$(read_temp_mc 2>/dev/null || echo 0)"
    c=$(( mc / 1000 ))
    st="$(state_for_temp_c "$c")"
    if [ "$st" != "$last" ]; then
        echo "$st" > "$CDEV" 2>/dev/null && \
            echo "$(date '+%H:%M:%S')  temp=${c}C  fan_state=${st}"
        last="$st"
    fi
    sleep 5
done

# ============================================================================
# 安装为 systemd 服务:
#   sudo cp q1-fan-control.sh /usr/local/bin/
#   sudo chmod +x /usr/local/bin/q1-fan-control.sh
#   cat | sudo tee /etc/systemd/system/q1-fan.service <<'EOF'
# [Unit]
# Description=Moyunteng Q1 pwm-fan userspace controller
# After=multi-user.target
#
# [Service]
# ExecStart=/usr/local/bin/q1-fan-control.sh
# Restart=always
#
# [Install]
# WantedBy=multi-user.target
# EOF
#   sudo systemctl daemon-reload
#   sudo systemctl enable --now q1-fan.service
#
# 手动测试风扇:
#   echo 5 > /sys/class/thermal/cooling_device<N>/cur_state   # 全速
#   echo 0 > /sys/class/thermal/cooling_device<N>/cur_state   # 停转
# ============================================================================
