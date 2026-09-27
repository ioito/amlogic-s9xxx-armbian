# 魔云腾 Q1 定制 U-Boot 构建方案（官方 ddrbin 注入）

## 1. 目标

为魔云腾 Q1（RK3588，已换无锁 CPU，DDR4 32GB）生成**完整可引导的非安全引导链**：

```
MaskROM → idbloader.img(ddrbin + spl) → u-boot.itb(BL31 + u-boot) → Armbian 内核
```

核心诉求：用**官方 Q1 的 ddrbin**（DDR4 32GB 专用）替换 ophub 通用 loader 里的 rock5b ddrbin，同时**绝不带入官方 u-boot / 锁机逻辑**（避免 eFuse 熔丝锁死新 CPU）。

---

## 2. 关键原理（已实证）

### 2.1 idbloader 的结构

ophub 完整镜像的引导区布局（已从 `our_armbian_q1.img` 实测确认）：

| 偏移 | 内容 | 说明 |
|---|---|---|
| `0x8000` | idbloader（RKNS + ddrbin 段 + spl） | RK3588 new_idb 格式 |
| `0x800000` | u-boot.itb（FIT，内置 BL31/ATF） | 完整引导链，无需独立 security 分区 |

### 2.2 官方 ddrbin 可直接作为 u-boot 的 `ROCKCHIP_TPL`

对比实证（字节级）：

| 文件 | 开头 16 字节 | 类型 |
|---|---|---|
| rkbin `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin` | `01000014e013bfa9fd7bbfa964010058` | 纯内容（无 header） |
| **官方 Q1 解出 `rk3588_ddr_lp4_2112.bin`（76KB）** | `01000014e013bfa9fd7bbfa964010058` | 纯内容（无 header） |

**两者开头完全一致** —— 官方 Q1 ddrbin 就是标准 Rockchip rkbin ddrbin 格式，**可直接作为 mainline u-boot 的 `ROCKCHIP_TPL`**。这是本方案可行的关键。

> 已用 boot_merger 从官方 MiniLoaderAll.bin 精确解出：`rk3588_ddr_lp4_2112.bin`（76KB，DDR4 2112MHz，Q1 32GB 专用），存放在本机 `/tmp/out_official/`。

### 2.3 安全性（红线）

- ✅ **只用官方 ddrbin（DDR 初始化组件）** —— 无锁机字符串（已验证）。
- ❌ **绝不用官方 u-boot / MiniLoaderAll 的 FlashBoot/FlashData** —— 那是官方 u-boot（含 `cpu or emmc was replaced!` / `disable oem otp write` 等锁机逻辑），会熔丝锁死新 CPU。
- ✅ 用 **mainline u-boot（开源）+ rkbin 标准 BL31** —— 非安全链，社区广泛使用，无锁机逻辑。

---

## 3. 构建流程（GitHub Actions，Linux 环境）

### 3.1 前置产物

官方 Q1 ddrbin 文件：`rk3588_ddr_lp4_2112.bin`（76KB）。需上传为 workflow artifact 或放入仓库。

### 3.2 核心构建命令（U-Boot 官方文档已确认）

```bash
# 工具链
sudo apt-get install -y gcc-aarch64-linux-gnu bc bison flex libssl-dev make

# 源码
git clone --depth 1 https://source.denx.de/u-boot/u-boot.git u-boot
git clone --depth 1 https://github.com/rockchip-linux/rkbin.git rkbin

# 用官方 Q1 ddrbin 作为 TPL（DDR 初始化）
export ROCKCHIP_TPL=/path/to/rk3588_ddr_lp4_2112.bin

# 编译 RK3588
cd u-boot
make evb-rk3588_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# 产物
ls -la idbloader.img u-boot.itb
```

`idbloader.img`（ddrbin+spl）与 `u-boot.itb`（BL31+u-boot）即完整非安全引导链。

### 3.3 替换进完整镜像

```bash
# 下载当前 ophub 完整镜像（6.18.54）
curl -L -o base.img.gz <release-url>
gunzip base.img.gz

# 替换 idbloader（0x8000 = seek 64 扇区）
dd if=idbloader.img of=base.img bs=512 seek=64 conv=notrunc

# 替换 u-boot.itb（0x800000 = seek 16384 扇区）
dd if=u-boot.itb of=base.img bs=512 seek=16384 conv=notrunc

# 重新打包
gzip -9 -c base.img > Armbian_q1_official_ddrbin_<ver>.img.gz
```

**注意**：新 `idbloader.img` / `u-boot.itb` 长度若超出原预留区（idbloader→0x800000，u-boot.itb→boot 分区），会覆盖后续分区。需校验长度 ≤ 预留空间。

---

## 4. 验证

1. **产物校验**：`idbloader.img` 含官方 ddrbin 特征（`ddr-v1.19` / `LPDDR4X` / 官方 DDR 参数表）；不含官方 u-boot 锁机字符串。
2. **静态检查**：u-boot.itb 含 `ARM Trusted Firmware` / `BL31`（可引导）。
3. **实机（关键）**：板子连 Mac 后用 rkdeveloptool 整盘刷（MaskROM 盲写）：
   ```bash
   rkdeveloptool ld          # 确认 MASKROM 设备
   rkdeveloptool wl 0 <img>  # 整盘刷写
   ```
   - 若引导成功且识别 32GB：方案成功。
   - 若卡 DDR/起不来：MaskROM 可救，重刷原镜像即可。

---

## 5. 风险与降级

| 风险 | 应对 |
|---|---|
| 官方 ddrbin 与 mainline spl 接口不匹配 | 用 rkbin 标准 ddrbin 先编译验证，再换官方 ddrbin 对比引导 |
| mainline u-boot 引导参数与 ophub armbian 不匹配 | 若起不来，改用 ophub/radxa vendor u-boot（stable-5.10-rock5）编译，同样注入官方 ddrbin |
| 新镜像长度覆盖后续分区 | 构建时校验 idbloader/u-boot.itb 长度 |
| 无法实机验证 | 板子到位后用 rkdeveloptool 实测，MaskROM 可救 |

---

## 6. GitHub Actions 一键构建（推荐）

已提供可执行 workflow：`.github/workflows/build-q1-uboot-official-ddrbin.yml`

**触发**：Actions → `Build Q1 U-Boot with Official DDRBin` → Run workflow（可改 base 镜像 URL）。

**流程**（Linux 环境，完整工具链）：
1. 取仓库内 `q1/files/rk3588_ddr_lp4_2112.bin`（官方 Q1 ddrbin）作 `ROCKCHIP_TPL`
2. `make evb-rk3588_defconfig` + 编译 → `idbloader.img` + `u-boot.itb`
3. 自动校验：idbloader 含 DDR 特征、u-boot.itb 含 BL31、**无锁机字符串**
4. 下载 base 完整镜像 → `dd` 替换 idbloader(seek=64) + u-boot.itb(seek=16384) → 重新 gzip
5. 上传 draft Release

**产物**：`Armbian_q1_official_ddrbin_<run>.img.gz`

---

## 7. 备用命令（参考）

**用 radxa vendor u-boot（与 ophub 更接近）**：
```bash
git clone -b stable-5.10-rock5 https://github.com/radxa/u-boot.git
git clone -b master https://github.com/radxa/rkbin.git
# 替换 rkbin 的 rk3588 ddrbin 为官方 Q1 ddrbin
cp rk3588_ddr_lp4_2112.bin rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin
export ROCKCHIP_TPL=rkbin/bin/rk35/rk3588_ddr_lp4_2112.bin
make rock-5b-rk3588_defconfig   # 或 evb-rk3588_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```
