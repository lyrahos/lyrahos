#!/bin/bash
# GPU auto-detection and driver installation
# Runs during installation or first boot
#
# FIX #14: Use lspci -d ::0300 for VGA class devices only
# FIX #43: Handle dnf failures gracefully instead of aborting on set -e

echo "=== Lyrah OS GPU Configuration ==="

# Use PCI class 0300 (VGA) for accurate GPU detection
GPU_LINE=$(lspci -d ::0300 2>/dev/null | head -1)
echo "Detected VGA device: $GPU_LINE"

if echo "$GPU_LINE" | grep -qi 'nvidia'; then
    GPU_VENDOR="nvidia"
elif echo "$GPU_LINE" | grep -qi 'amd\|radeon'; then
    GPU_VENDOR="amd"
elif echo "$GPU_LINE" | grep -qi 'intel'; then
    GPU_VENDOR="intel"
else
    GPU_VENDOR="unknown"
fi

echo "GPU vendor: $GPU_VENDOR"

case $GPU_VENDOR in
  nvidia)
    echo "Installing NVIDIA proprietary drivers from RPM Fusion..."
    dnf install -y \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
      2>/dev/null || echo "RPM Fusion may already be enabled"
    dnf install -y akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs xorg-x11-drv-nvidia-libs.i686 \
      || echo "WARNING: NVIDIA driver installation failed. Falling back to nouveau."
    ;;
  amd)
    echo "AMD GPU detected - open-source drivers already in kernel"
    dnf install -y mesa-vulkan-drivers mesa-vulkan-drivers.i686 \
      || echo "WARNING: Could not install AMD Vulkan drivers"
    ;;
  intel)
    echo "Intel GPU detected - open-source drivers already in kernel"
    dnf install -y intel-media-driver mesa-vulkan-drivers \
      || echo "WARNING: Could not install Intel media/Vulkan drivers"
    ;;
  *)
    echo "WARNING: Could not detect GPU vendor. Installing Mesa fallback."
    dnf install -y mesa-dri-drivers mesa-vulkan-drivers \
      || echo "WARNING: Could not install fallback drivers"
    ;;
esac

# Hybrid graphics detection (laptops with dual GPUs)
DUAL_GPU=$(lspci -d ::0300 | wc -l)
if [ "$DUAL_GPU" -gt 1 ]; then
    echo "Hybrid graphics detected. Installing switcheroo-control..."
    dnf install -y switcheroo-control || true
    systemctl enable switcheroo-control || true
    # If NVIDIA is one of the GPUs, add supergfxctl
    if lspci -d ::0300 | grep -qi nvidia; then
        dnf copr enable -y asus-linux/supergfxctl 2>/dev/null || true
        dnf install -y supergfxctl || true
        systemctl enable supergfxd || true

        # Blacklist nouveau on hybrid GPU systems. The integrated GPU
        # (AMD/Intel) handles compositing; nouveau on modern NVIDIA GPUs
        # causes DRM hangs that freeze the entire display (including VTs).
        # Proprietary NVIDIA drivers (installed above) replace nouveau
        # for gaming via PRIME offloading.
        echo "Blacklisting nouveau (hybrid GPU: iGPU handles display)..."
        cat > /etc/modprobe.d/lyrah-nouveau-blacklist.conf << 'MODEOF'
# Lyrah OS: Blacklist nouveau on hybrid GPU systems.
# The integrated GPU handles compositing; nouveau on modern NVIDIA GPUs
# can cause DRM hangs. Use proprietary NVIDIA drivers for gaming.
blacklist nouveau
options nouveau modeset=0
MODEOF
    fi
fi

echo "GPU configuration complete."
