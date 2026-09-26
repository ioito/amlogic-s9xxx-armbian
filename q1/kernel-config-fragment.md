# ============================================================================
# 魔云腾 Q1 - 内核 config 需求核对（参考/备选）
# ----------------------------------------------------------------------------
# 结论：【不需要】自定义编译内核。
# 我们已从 ophub/kernel 仓库拉取真实 config 核对（kernel-config/release/）：
#
#   符号                          BSP 6.1 (rk3588)    主线 stable 6.18 (kernel_stable)
#   ----------------------------  ------------------   --------------------------------
#   CONFIG_KVM=y                  =y                   =y
#   CONFIG_VIRTUALIZATION=y       =y                   =y
#   CONFIG_SENSORS_PWM_FAN=m      =m                   =m
#   CONFIG_MEMCG=y                (主线默认)           =y
#   CONFIG_BLK_CGROUP=y           (主线默认)           =y
#   CONFIG_OVERLAY_FS=y           (主线默认)           =y
#   CONFIG_DRM_SSD130X=m          未开启(!)            =m   <-- OLED 驱动
#   CONFIG_DRM_SSD130X_I2C=m      未开启(!)            =m   <-- I2C OLED
#
# 因此 Q1 选用主线 stable 6.18.y 预编译内核（model_database 里 KERNEL_TAGS=stable/6.18.y），
# 它已内置 SSD1306 OLED 驱动 + KVM + pwm-fan + cgroup v2，开箱即用。
#
# 本文件仅作为【备查】：万一未来 ophub 把 SSD130X 从 6.18 移除，或你想自己重编内核，
# 把下列 fragment 合入 base config 即可（mk KERNEL_CONFIG_FRAGMENT 或 .config）。
# ============================================================================

# --- 虚拟化 (KVM on RK3588) ---
CONFIG_VIRTUALIZATION=y
CONFIG_KVM=y
CONFIG_KVM_ARM_HOST=y
CONFIG_KVM_GENERIC_DIRTYLOG_READ_PROTECT=y
CONFIG_KVM_MMIO=y
CONFIG_KVM_VFIO=y

# --- PWM 风扇 (pwm-fan hwmon) ---
CONFIG_SENSORS_PWM_FAN=m

# --- SSD1306 OLED on I2C (DRM 框架, 6.x) ---
CONFIG_DRM=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_DRM_SSD130X=m
CONFIG_DRM_SSD130X_I2C=m
# 旧 fbdev 驱动不需要（主线用上面 DRM 驱动）：
# CONFIG_FB_SSD1307 is not set

# --- k3s / cgroup v2 / overlayfs ---
CONFIG_CGROUPS=y
CONFIG_MEMCG=y
CONFIG_MEMCG_KMEM=y
CONFIG_BLK_CGROUP=y
CONFIG_CGROUP_SCHED=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_BPF=y
CONFIG_OVERLAY_FS=y
CONFIG_FUSE_FS=y

# --- netfilter / iptables (k3s 要求) ---
CONFIG_NETFILTER=y
CONFIG_NETFILTER_ADVANCED=y
CONFIG_NF_CONNTRACK=m
CONFIG_NETFILTER_XTABLES=m
CONFIG_IP_NF_IPTABLES=m
CONFIG_IP_NF_FILTER=m
CONFIG_IP_NF_NAT=m
CONFIG_NF_NAT=m
CONFIG_BRIDGE_NETFILTER=m
