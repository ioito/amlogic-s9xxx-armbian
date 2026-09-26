# 魔云腾 Q1 (RK3588) Armbian 构建定制说明

> 本目录（仓库根 `q1/`）是为 **魔云腾 Q1** 在 `ioito/amlogic-s9xxx-armbian` fork 上准备的一整套构建定制。
> 目标：GitHub Actions 只打 Q1 一个镜像，满足「不锁频 / KVM / k3s / PWM 风扇 / SSD1306 OLED / 干净命名 eth0 / 无幽灵 wlan / 不碰 eFuse」。

---

## 0. 一句话结论

- **内核**：用 ophub **主线 stable 6.18.y 预编译内核**（无需自行编译）。已核对其真实 .config：内置 `CONFIG_KVM=y`、`CONFIG_SENSORS_PWM_FAN=m`、`CONFIG_DRM_SSD130X_I2C=m`（SSD1306 OLED）、`CONFIG_MEMCG/BLK_CGROUP/OVERLAY_FS` 全开。
- **DTB**：从原厂 `fdt_main.dtb` 二进制补丁出 `rk3588-q1.dtb`，保留完整 opp 表（含 2.4GHz 档）+ pwm-fan，并修正网卡别名、禁用幽灵 WiFi/BT、清除 cgroup v1 bootargs、给风扇补 thermal cooling-map。
- **Actions**：两个打镜像 workflow 已锁定 `armbian_board=q1`、单内核 `6.18.y`、`kernel_repo=ioito/kernel`，action 引用切到你的 fork。

---

## 1. 改了哪些文件（全部在本仓库，不要 push 前先 review）

| # | 文件 | 改动 |
|---|------|------|
| 1 | `build-armbian/armbian-files/common-files/etc/model_database.conf` | 在 r127 后追加 **r128** 行：`Moyunteng-Q1 … rk3588-q1.dtb … stable/6.18.y … board=q1`（15 列） |
| 2 | `build-armbian/armbian-files/platform-files/rockchip/bootfs/dtb/rockchip/rk3588-q1.dtb` | 新建。从 `fdt_main.dtb` 补丁而来（见 §2） |
| 3 | `.github/workflows/build-armbian-arm64-server-image.yml` | `armbian_board` 默认=`q1` 并加 `- q1` 选项；`armbian_kernel` 默认=`6.18.y`；`kernel_repo` 默认=`ioito/kernel`；action 改 `ioito/amlogic-s9xxx-armbian@main` |
| 4 | `.github/workflows/build-armbian-using-releases-files.yml` | 同上（复用 trunk rootfs 的快路径） |
| 5 | `q1/overlay/q1-ssd1306.dts` | SSD1306 OLED 用户态 overlay 源 |
| 6 | `q1/scripts/q1-i2c-oled-probe.sh` | i2cdetect 扫描脚本，定位 OLED 总线/地址 |
| 7 | `q1/scripts/q1-fan-control.sh` | 用户态温控兜底脚本 + systemd 安装说明 |
| 8 | `q1/kernel-config-fragment.md` | 内核 config 核对结论（备查，**无需执行**） |
| 9 | `q1/README-Q1.md` | 本文件 |

> 没有动任何其它既有设备行、没有删除任何文件、`compile-kernel/tools/config/` 保持空（**不触发自定义内核编译**）。

---

## 2. rk3588-q1.dtb 改了什么（用 fdtput 二进制补丁，未整树反编译）

源文件：原厂 `/Users/quxuan/Downloads/armbian/fdt_main.dtb`（即 `rockchip,rk3588-evb7-v11`）。补丁项：

1. **网卡别名修正**
   - `/aliases/ethernet0` 由 `/ethernet@fe1b0000`(gmac0, disabled) 改为 `/ethernet@fe1c0000`(gmac1, okay)。
   - **删除** `/aliases/ethernet1`。
   - 结果：唯一启用的 1G 口 gmac1 干净命名为 `eth0`，不再有 eth1 残留。
2. **消除幽灵网卡 wlan0/wlan1**
   - `/wireless-wlan`（`wlan-platdata`, `wifi_chip_type="ap6398s"`）`status` → `disabled`。
   - `/wireless-bluetooth`（`bluetooth-platdata`）`status` → `disabled`。
   - 原因：魔云腾 Q1 板上**没有** SDIO WiFi/BT 模块，原厂 DTB 却启用了这两个节点，内核枚举出无硬件的 wlan0/wlan1（MAC 02:00:…）。
3. **风扇自动调速（关键修复）**
   - 原厂 `soc-thermal/cooling-maps` 只关联了 CPU/GPU DVFS，**没把 pwm-fan 关联进去**；主线内核 pwm-fan 又不认 BSP 的 `rockchip,temp-trips`，所以风扇从不转。
   - 新增 `map4`（75°C → fan state 0~2）和 `map5`（85°C → fan state 0~5），把 `/pwm-fan`（phandle 0x4a4）挂为 cooling device。
   - pwm-fan 节点本身（`pwms=<&pwm3 0 50000>` 20kHz、`cooling-levels=0,50,100,150,200,255`）原样保留。
4. **清除 cgroup v1 bootargs**
   - `/chosen/bootargs` 去掉 `cgroup_enable=memory swapaccount=0 systemd.unified_cgroup_hierarchy=0`（原厂强制 cgroup v1，与 k3s 冲突），保留 console/root。Armbian 自己的 boot.scr 会再覆盖，这里只是兜底。
5. **model** 改为 `Moyunteng Q1 (Rockchip RK3588)` 便于识别。
6. **完整保留**：`/cpus` 全部 opp 档（含最高 `opp-2400000000` 2.4GHz）、大核供电 rk8602/rk806 regulators、gmac1(phy@1)、pwm3、i2c 总线。**绝未砍高频档**——换上无锁 CPU 后即可跑满 2.4GHz。

> 补丁命令（备查，已执行）：
> ```
> fdtput -t s rk3588-q1.dtb /aliases ethernet0 "/ethernet@fe1c0000"
> fdtput -d rk3588-q1.dtb /aliases ethernet1
> fdtput -t s rk3588-q1.dtb /wireless-wlan status "disabled"
> fdtput -t s rk3588-q1.dtb /wireless-bluetooth status "disabled"
> fdtput -t s rk3588-q1.dtb /chosen bootargs "earlycon=... console=ttyFIQ0 ... rootwait rcu_nocbs=all"
> fdtput -c .../cooling-maps/map4 && fdtput -t i .../map4 trip 0x250 && fdtput -t i .../map4 cooling-device 0x4a4 0 2
> fdtput -c .../cooling-maps/map5 && fdtput -t i .../map5 trip 0x54  && fdtput -t i .../map5 cooling-device 0x4a4 0 5
> ```

---

## 3. ⚠️ 熔丝 / 安全启动（eFuse）注意事项——务必读完

- 你已把 CPU 换成**未烧 secure-boot 熔丝的新 CPU**（干净 eFuse）。我们刷的 Armbian 用 **ophub 自己的 U-Boot** 引导，**不校验 FIT 签名、不读/写 eFuse**，与原厂那套 `key-name-hint="dev" sha256,rsa2048` 签名体系完全无关。
- **刷机全程禁止**：
  1. 不要用魔云腾官方"安全/锁机"固件、不要走官方安全烧录流程（那可能覆盖新 CPU 的 eFuse，把它锁死）。
  2. RKDevTool 里**不要勾选/触发任何烧写 bootloader 签名、烧录 fuses、secure boot、otp 相关选项或工具**。只按下面 §5 的标准 MaskROM 刷 .img。
- 刷入后新 CPU 保持无锁，可自由引导未签名固件。日后若想刷回原厂，也**避开官方锁机流程**。

---

## 4. 推送到你的 fork 并触发 Actions

```bash
cd amlogic-s9xxx-armbian
git add build-armbian/armbian-files/common-files/etc/model_database.conf \
        build-armbian/armbian-files/platform-files/rockchip/bootfs/dtb/rockchip/rk3588-q1.dtb \
        .github/workflows/build-armbian-arm64-server-image.yml \
        .github/workflows/build-armbian-using-releases-files.yml \
        q1/
git commit -m "Q1: add Moyunteng-Q1 (rk3588) board, lock build to q1, ioito forks"
git push origin main
```

### 用哪个 workflow

- **首次/没有 trunk rootfs 时**：用 **`Build Armbian arm64 server image`**（`build-armbian-arm64-server-image.yml`）。它从 armbian/build 源码编 rootfs，再用 ophub action 按 `armbian_board=q1` 重构出 Q1 镜像。跑在 x86 runner，约 1~2 小时。
- **之后重打 Q1**：用 **`Build Armbian using releases files`**（`...using-releases-files.yml`）。它直接复用仓库 Releases 里已有的 trunk rootfs 重构为 Q1，跑在 ARM runner，快很多。

触发：GitHub → 仓库 **Actions** → 选对应 workflow → **Run workflow**。参数已默认好（`armbian_board=q1`, `armbian_kernel=6.18.y`, `kernel_repo=ioito/kernel`），直接点 Run 即可，不要改选其它 board。

> 仓库依赖 fork（你已 fork）：
> - 内核包：`ioito/kernel`（对应 ophub/kernel，含 kernel_stable）→ 已配为 `kernel_repo` 默认。
> - U-Boot / loader：`ioito/u-boot`、`ioito/firmware`（对应 ophub/u-boot、ophub/firmware）。
> - `armbian/build` **未 fork**，workflow 直接 clone 官方大仓库（git 协议不受 API 限流）。
> - `ioito/k3s` 与本镜像构建无强耦合，仅日后装 k3s 时可用。

产物在仓库 **Releases** 里下载，文件名形如 `Armbian_<release>_edge_rockchip_q1_*.img.gz`。

---

## 5. 用 RKDevTool 刷入 Q1（MaskROM 模式，标准流程）

1. 安装 Rockchip **RKDevTool**，装齐 RK3588 驱动。
2. Q1 **断电**，用 USB-C 双公线接 MaskROM 口，按住 MaskROM 按键上电（或短接 MaskROM 触点），RKDevTool 显示"发现一个 MASKROM 设备"。
3. 加载我们构建出的 `.img`（**整盘镜像**，不是分区散件）。
4. **只勾选"写入整盘镜像"对应那一项**，地址按默认，点执行。
5. ⚠️ 全程**不要碰**任何 `bootloader signature / burn fuses / secure boot / OTP` 相关页签或选项（见 §3）。
6. 写完拔电、换网线、接显示器/串口，上电。

默认账号 `root / 1234`。

---

## 6. 刷机后验证（逐项）

```bash
# (1) 不锁频：看 CPU 是否能上 2.4GHz
cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq      # 期望 ~2400000
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq      # 跑负载时应接近上限
# 跑满后测: stress-ng --cpu 8 --timeout 30 同时观察上面数值

# (2) KVM
ls -l /dev/kvm            # 存在即 OK
egrep -o 'vmx|svm' /proc/cpuinfo   # ARM 上无此项, 看 /dev/kvm 即可

# (3) k3s 环境: 纯 cgroup v2
stat -fc %T /sys/fs/cgroup          # 期望 cgroup2fs
cat /sys/fs/cgroup/cgroup.controllers | tr ' ' '\n' | grep -E 'memory|pids'   # 应有 memory
mount | grep overlay                # overlayfs 在
# 装 k3s: curl -sfL https://get.k3s.io | sh -

# (4) 网卡: 只有一个 eth0, 无 wlan0/wlan1
ip -br link                         # 应只见 eth0 (eth1/wlan0/wlan1 不应出现)

# (5) 风扇: 升温应自动转
cat /sys/class/thermal/thermal_zone*/temp
# 找 pwm-fan cooling_device:
grep -l pwm-fan /sys/class/thermal/cooling_device*/type
N=$(grep -l pwm-fan /sys/class/thermal/cooling_device*/type | head -1 | grep -o '[0-9]*')
cat /sys/class/thermal/cooling_device$N/cur_state        # 高温时应 >0
# 手动测试(全速): echo 5 > /sys/class/thermal/cooling_device$N/cur_state   ; 停: echo 0 > ...
```

### OLED 验证（需先探测+启用 overlay，见 §7）

```bash
ls /dev/fb*                                   # 出现新 fb 即 DRM 帧缓冲就绪
ls /sys/bus/i2c/devices/*/ | grep -i oled     # ssd1306 已挂载
# 亮屏: fbi -d /dev/fb0 some.png  (apt install fbi)
```

---

## 7. SSD1306 OLED 的启用（需探测一次）

原厂 DTB 没写 OLED 挂哪条 I2C，板上走线未知，所以用「探测 + overlay」：

```bash
# 1) 装工具
sudo apt-get install -y device-tree-compiler i2c-tools

# 2) 扫描定位 OLED (找 0x3c / 0x3d 在哪个 bus)
sudo sh q1/scripts/q1-i2c-oled-probe.sh
```

按探测结果改 `q1/overlay/q1-ssd1306.dts` 里的 `&i2cX`（默认 `&i2c6`）和地址（默认 `0x3c`），然后：

```bash
sudo mkdir -p /boot/overlay-user && cd /boot/overlay-user
sudo cp /path/to/q1/overlay/q1-ssd1306.dts .
sudo dtc -O dtb -o q1-ssd1306.dtbo -@ q1-ssd1306.dts
echo 'user_overlays=q1-ssd1306' | sudo tee -a /boot/armbianEnv.txt
sudo reboot
```

> 驱动用主线 DRM panel 绑定 `compatible = "solomon,ssd1306"`（不是旧 fbdev 的 `ssd1307fb-i2c`）。
> 内核 6.18 已内置该驱动，无需重编。

---

## 8. 风扇兜底（如果自动调速不生效）

DTB 已补 thermal cooling-map，主线内核应自动按温度调风扇。若实测仍不转，启用用户态脚本兜底：

```bash
sudo cp q1/scripts/q1-fan-control.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/q1-fan-control.sh
# 脚本末尾注释里有现成的 systemd unit, 复制后:
sudo systemctl daemon-reload && sudo systemctl enable --now q1-fan.service
```

---

## 9. 需要你确认的点

1. **WiFi 版本**：本配置默认魔云腾 Q1 **无** SDIO WiFi/BT（已禁用 wlan/bt 节点）。若你手上这台 Q1 实际带 WiFi 模块，**不要禁用**——需按真实芯片（如 ap6256/ap6398s）正确配 `wifi_chip_type` 与固件，而不是 disabled。请确认板子确实无 WiFi。
2. **gmac1 PHY 地址**：DTB 用的是 `mdio/phy@1`（reg=1）。你实测 eth0 已正常工作即说明 PHY 地址对；若换板后网口不通，用 `sudo ethtool -i eth0` / mdio 扫描核对 PHY 地址。
3. **OLED 总线/地址**：默认 overlay 挂 `i2c6 @0x3c`，必须按 §7 用 i2cdetect 实测结果调整。
4. **风扇 trip 点**：现设 75°C 起转、85°C 满速。想更安静/更激进可改 `cooling-maps/map4,map5` 的 trip phandle 或 state 范围。
5. **内核版本**：现用单内核 `6.18.y`。若与某外设驱动不兼容，可在 Run workflow 时改选 `6.12.y`（model_database 里把 Q1 的 KERNEL_TAGS 同步改成 `stable/6.12.y`）。

---

## 10. 一致性自检（三处必须对上）

- `model_database.conf` 的 FDTFILE = **`rk3588-q1.dtb`**，BOARD = **`q1`**，BUILD = yes；
- dtb 文件名 = **`rk3588-q1.dtb`**（已放对目录）；
- workflow `armbian_board` 默认 = **`q1`**。

三者一致，Actions 才会只打 Q1。
