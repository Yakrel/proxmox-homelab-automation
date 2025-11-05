# Webtools Stack - Desktop Workspace with NVIDIA GPU

## Overview

This webtools stack includes a desktop-workspace container (Chrome + Obsidian) with NVIDIA GPU hardware acceleration running in an unprivileged LXC container on Proxmox VE.

**Image:** `yakrel93/desktop-workspace:latest` (custom image based on LinuxServer's [baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies))

**Source:** [`docker-images/desktop-workspace/`](/docker-images/desktop-workspace/)

**⚠️ PREREQUISITE: Host GPU Setup Required**

Before deploying this stack, you must configure the Proxmox host for GPU passthrough:
1. Run `bash installer.sh` on Proxmox host
2. Select **"Run Proxmox Helper Scripts..."** from the main menu
3. Choose option **7) Setup GPU Passthrough (NVIDIA)**
4. Complete both phases (nouveau blacklist + driver installation)
5. Reboot after each phase as instructed
6. Verify drivers are loaded: `lsmod | grep nvidia` and `nvidia-smi`

Then proceed with webtools stack deployment - it will automatically configure GPU in the LXC container.

## GPU Configuration for Desktop Workspace (Chrome)

### LinuxServer docker-chrome Documentation

The [LinuxServer docker-chrome](https://github.com/linuxserver/docker-chrome) documentation recommends using `runtime: nvidia` for standard Docker environments:

```yaml
services:
  chrome:
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
```

### Our Configuration (Unprivileged LXC)

**We use manual device mapping instead of `runtime: nvidia` because:**

1. **Unprivileged LXC Limitation:** The NVIDIA container runtime (`runtime: nvidia`) doesn't work properly in unprivileged LXC containers due to cgroup device control restrictions and CUDA library mounting failures.

2. **Proven Approach:** We use the same tested configuration as the media stack (Jellyfin), which has been verified to work in unprivileged LXC environments. See [Media Stack README](/docker/media/README.md) for detailed testing results showing 18.64x real-time GPU transcoding (447 fps) with full CUDA pipeline.

#### Device Mapping (docker-compose.yml)

```yaml
devices:
  - /dev/nvidia0:/dev/nvidia0              # GPU device
  - /dev/nvidiactl:/dev/nvidiactl          # GPU control device
  - /dev/nvidia-uvm:/dev/nvidia-uvm        # CUDA initialization
  - /dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools  # CUDA tools
  - /dev/nvidia-modeset:/dev/nvidia-modeset      # Mode setting

environment:
  - NVIDIA_VISIBLE_DEVICES=all
  - NVIDIA_DRIVER_CAPABILITIES=all
```

**All 5 device mappings are required for GPU hardware acceleration to work properly.**

#### LXC Configuration (Automated)

The deployment script ([`scripts/lxc-manager.sh`](/scripts/lxc-manager.sh)) automatically configures:
- Creates systemd service (`nvidia-persistenced.service`) for persistent NVIDIA device setup
- Loads `nvidia-uvm` kernel module on Proxmox host (survives reboots)
- Sets proper permissions (666) on nvidia-uvm devices
- Configures cgroup device permissions (c 195, 510, 511)
- Mounts NVIDIA devices into LXC container
- Sets `no-cgroups = true` in nvidia-container-runtime config

**The systemd service ensures nvidia-uvm devices are available after Proxmox host restarts.**

## How GPU Acceleration Works

The LinuxServer baseimage-selkies (used by desktop-workspace) automatically detects NVIDIA hardware when the devices are available and enables hardware acceleration for:

- **Chrome:** WebGL, video decode/encode, canvas acceleration
- **Video streaming:** Hardware-accelerated H.264 encoding via NVENC (h264_nvenc)
- **Graphics rendering:** GPU-accelerated rendering for smooth desktop experience

No additional configuration is needed inside the container - the LinuxServer image handles GPU detection and acceleration automatically when NVIDIA devices are present.

## Verification

After deployment, verify GPU is being used:

```bash
# Check if Chrome container can see GPU
docker exec desktop-workspace nvidia-smi

# Check Chrome processes using GPU
docker exec desktop-workspace nvidia-smi pmon

# View container logs for GPU detection
docker logs desktop-workspace | grep -i "nvidia\|gpu"
```

## Comparison: Standard Docker vs Unprivileged LXC

| Configuration | Standard Docker Host | Unprivileged LXC (Proxmox) |
|--------------|----------------------|----------------------------|
| GPU Runtime | `runtime: nvidia` ✅ | `runtime: nvidia` ❌ |
| Device Mapping | Auto (via runtime) | Manual (required) ✅ |
| CUDA Libraries | Auto-mounted | Pre-installed in LXC via NVIDIA drivers |
| Configuration | Simple | Requires LXC + cgroup setup |

## References

- [LinuxServer docker-chrome](https://github.com/linuxserver/docker-chrome) - Standard Docker setup
- [LinuxServer baseimage-selkies](https://github.com/linuxserver/docker-baseimage-selkies) - GPU acceleration implementation
- [Media Stack README](/docker/media/README.md) - Similar GPU configuration for Jellyfin with detailed testing results
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/) - How `runtime: nvidia` works
- [Proxmox LXC GPU Passthrough](https://pve.proxmox.com/wiki/LXC#_bind_mount_points) - LXC device passthrough
