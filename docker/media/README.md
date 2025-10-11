# Media Stack - Jellyfin with NVIDIA GPU Hardware Transcoding

## Overview

This media stack runs Jellyfin with NVIDIA GPU (GTX 970) hardware acceleration for video transcoding in an unprivileged LXC container on Proxmox VE.

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

### Solution

We bypass the NVIDIA runtime and use direct device + library mounting:

#### 1. Device Mounting (docker-compose.yml)
```yaml
devices:
  - /dev/nvidia0:/dev/nvidia0              # GPU device
  - /dev/nvidiactl:/dev/nvidiactl          # GPU control device
  - /dev/nvidia-modeset:/dev/nvidia-modeset      # Mode setting
  - /dev/nvidia-uvm:/dev/nvidia-uvm        # CRITICAL for CUDA
  - /dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools  # CUDA tools
```

#### 2. CUDA Library Mounting (docker-compose.yml)
```yaml
volumes:
  - /usr/lib/x86_64-linux-gnu/nvidia/current:/usr/lib/x86_64-linux-gnu/nvidia/current:ro
  - /usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1:/usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1:ro
  - /usr/lib/x86_64-linux-gnu/libnvcuvid.so.1:/usr/lib/x86_64-linux-gnu/libnvcuvid.so.1:ro

environment:
  - LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/nvidia/current:/usr/lib/x86_64-linux-gnu
```

#### 3. LXC Configuration (lxc-manager.sh)

The script automatically:
- Loads `nvidia-uvm` kernel module on Proxmox host
- Sets proper permissions (666) on nvidia-uvm devices
- Configures cgroup device permissions (c 195, 510, 511)
- Mounts NVIDIA devices into LXC container
- Sets `no-cgroups = true` in nvidia-container-runtime config

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

## Performance

### Before (CPU only):
- **Transcoding:** 5-9 CPU cores (%500-900)
- **Speed:** ~0.5-1x real-time
- **Power:** High CPU usage, heat, fan noise

### After (GPU accelerated):
- **Transcoding:** 1.3 CPU cores (%134) + GPU
- **GPU Usage:** decode %60-97, encode %10-15
- **Speed:** 11-15x real-time
- **Power:** Low CPU usage, efficient

## Tested Scenarios

| Scenario | Method | CPU Usage | GPU Usage | Result |
|----------|--------|-----------|-----------|--------|
| Direct Play (Auto quality) | No transcoding | %0-5 | %0 | ✅ Optimal |
| 720p Transcode | GPU HW accel | %134 (1.3 core) | dec %97, enc %13 | ✅ Perfect |
| Subtitle Burning | GPU HW accel | %150 (1.5 core) | Active | ✅ Works |

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
