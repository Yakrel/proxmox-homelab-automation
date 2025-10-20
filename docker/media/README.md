# Media Stack - Jellyfin with NVIDIA GPU Hardware Transcoding

## Overview

This media stack runs Jellyfin with NVIDIA GPU (GTX 970) hardware acceleration for video transcoding in an unprivileged LXC container on Proxmox VE.

**⚠️ PREREQUISITE: Host GPU Setup Required**

Before deploying this stack, you must configure the Proxmox host for GPU passthrough:
1. Run Helper Menu option **7) Setup GPU Passthrough (NVIDIA)**
2. Complete both phases (nouveau blacklist + driver installation)
3. Reboot after each phase as instructed
4. Verify drivers are loaded: `lsmod | grep nvidia` and `nvidia-smi`

Then proceed with media stack deployment - it will automatically configure GPU in the LXC container.

**✅ TESTED & VERIFIED CONFIGURATION (October 2025)**
- Full GPU pipeline working: CUDA decode → scale → encode
- Performance: 447 fps (18.64x real-time transcoding)
- FFmpeg using: `-hwaccel cuda -hwaccel_output_format cuda -c:v h264_nvenc`
- All configurations below are required - tested and confirmed working

## Hardware Transcoding Pipeline

Jellyfin uses full GPU pipeline for video transcoding:
- **Decode:** NVIDIA CUVID (h264_cuvid, hevc_cuvid)
- **Scale:** CUDA (scale_cuda)
- **Encode:** NVIDIA NVENC (h264_nvenc, hevc_nvenc)

## Special Configuration for Unprivileged LXC

### Problem

NVIDIA container runtime (`runtime: nvidia`) doesn't work properly in unprivileged LXC containers due to:
1. cgroup device control restrictions
2. CUDA library mounting failures
3. nvidia-uvm device permission issues

### Solution (TESTED & VERIFIED)

We bypass the NVIDIA runtime and use direct device + library mounting.

**⚠️ CRITICAL: All configurations below are required - DO NOT remove any device or library mount:**

#### 1. Device Mounting (docker-compose.yml)

**All 5 devices are required - tested and confirmed working. DO NOT remove any:**

```yaml
devices:
  - /dev/nvidia0:/dev/nvidia0              # GPU device
  - /dev/nvidiactl:/dev/nvidiactl          # GPU control device
  - /dev/nvidia-modeset:/dev/nvidia-modeset      # Mode setting
  - /dev/nvidia-uvm:/dev/nvidia-uvm        # CRITICAL for CUDA initialization
  - /dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools  # CUDA tools
```

#### 2. CUDA Library Mounting (docker-compose.yml)

**All 3 library mounts + LD_LIBRARY_PATH are required - tested and confirmed working. DO NOT remove any:**

```yaml
volumes:
  - /usr/lib/x86_64-linux-gnu/nvidia/current:/usr/lib/x86_64-linux-gnu/nvidia/current:ro
  - /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1:/usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1:ro
  - /usr/lib/x86_64-linux-gnu/libnvcuvid.so.1:/usr/lib/x86_64-linux-gnu/libnvcuvid.so.1:ro

environment:
  - NVIDIA_VISIBLE_DEVICES=all
  - NVIDIA_DRIVER_CAPABILITIES=all
  - LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/nvidia/current:/usr/lib/x86_64-linux-gnu
```

#### 3. LXC Configuration (lxc-manager.sh)

The script automatically:
- Creates systemd service (`nvidia-persistenced.service`) for persistent NVIDIA device setup
- Loads `nvidia-uvm` kernel module on Proxmox host (survives reboots)
- Sets proper permissions (666) on nvidia-uvm devices
- Configures cgroup device permissions (c 195, 510, 511)
- Mounts NVIDIA devices into LXC container
- Sets `no-cgroups = true` in nvidia-container-runtime config

**The systemd service ensures nvidia-uvm devices are available after Proxmox host restarts.**

## Jellyfin Configuration

**Dashboard → Playback → Transcoding:**

1. **Hardware acceleration:** NVIDIA NVENC
2. **Enable hardware encoding:** ✅
3. **Enable hardware decoding for:**
   - ✅ H264
   - ✅ HEVC
   - ✅ MPEG2
   - ✅ VC1
   - ✅ VP8

4. **Encoding format options:**
   - ❌ Allow encoding in HEVC format (GTX 970 H.265 encoding is slow)
   - ❌ Allow encoding in AV1 format (not supported on GTX 970)
   - ❌ Enable Tone mapping (slow on GTX 970)

## Performance (Tested Results)

### Before (CPU only):
- **Transcoding:** 5-9 CPU cores (%500-900)
- **Speed:** ~0.5-1x real-time
- **Power:** High CPU usage, heat, fan noise

### After (GPU accelerated) - VERIFIED October 2025:
- **Transcoding:** 1.3 CPU cores (%134) + GPU
- **GPU Usage:** Active (163MB VRAM, 73W power)
- **Speed:** 447 fps (18.64x real-time)
- **Power:** Low CPU usage, efficient
- **FFmpeg Command:** `-hwaccel cuda -hwaccel_output_format cuda -c:v h264_nvenc`

## Tested Scenarios (October 2025)

| Scenario | Method | Performance | Result |
|----------|--------|-------------|--------|
| Direct Play (Auto quality) | No transcoding | CPU %0-5, GPU idle | ✅ Optimal |
| 720p Transcode | GPU HW accel | 447 fps (18.64x real-time) | ✅ Perfect |
| 1080p Direct Stream | Direct | H264 direct passthrough | ✅ Works |
| Subtitle Burning | GPU HW accel | CPU %150 (1.5 core) | ✅ Works |

## Troubleshooting

### CUDA_ERROR_UNKNOWN
**Problem:** ffmpeg can't load libcuda.so.1

**Solution:**
1. Ensure nvidia-uvm module is loaded: `modprobe nvidia-uvm`
2. Check device permissions in LXC: `ls -la /dev/nvidia-uvm*` (should be crw-rw-rw-)
3. Verify CUDA libraries are mounted: `docker exec jellyfin ldconfig -p | grep cuda`

### Hardware Transcoding Not Working
**Problem:** Jellyfin still uses CPU for transcoding

**Solution:**
1. Check Jellyfin logs: `docker logs jellyfin | grep -i "hwaccel\|cuda\|nvenc"`
2. Verify ffmpeg during transcoding: `docker exec jellyfin ps aux | grep ffmpeg`
3. Should see: `-hwaccel cuda -hwaccel_output_format cuda -codec:v:0 h264_nvenc`

## References

- [Jellyfin Hardware Acceleration](https://jellyfin.org/docs/general/administration/hardware-acceleration/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
- [Proxmox LXC GPU Passthrough](https://pve.proxmox.com/wiki/LXC#_bind_mount_points)
