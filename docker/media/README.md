# Media Stack - GPU-Accelerated Media Services

## Overview

This media stack runs multiple media services with NVIDIA GPU (GTX 970) hardware acceleration in an unprivileged LXC container on Proxmox VE:

- **Jellyfin**: Video streaming with GPU-accelerated transcoding
- **Immich**: Self-hosted Google Photos with GPU-accelerated AI/ML features
- **Media Management**: Sonarr, Radarr, Bazarr, Prowlarr, Jellyseerr
- **Download Tools**: qBittorrent, FlareSolverr, Recyclarr, Cleanuperr

## Services and Ports

| Service | Port | Description |
|---------|------|-------------|
| Jellyfin | 8096 | Media streaming server |
| Immich | 2283 | Photo/video management (AI-powered) |
| Sonarr | 8989 | TV show management |
| Radarr | 7878 | Movie management |
| Bazarr | 6767 | Subtitle management |
| Jellyseerr | 5055 | Media requests |
| qBittorrent | 8080 | Torrent client |
| Prowlarr | 9696 | Indexer manager |
| FlareSolverr | 8191 | Cloudflare bypass |
| Cleanuperr | 11011 | Automated cleanup |
| Promtail | 9080 | Log aggregation |

## GPU Acceleration Features

### Jellyfin - Hardware Video Transcoding
Full GPU pipeline for video transcoding:
- **Decode:** NVIDIA CUVID (h264_cuvid, hevc_cuvid)
- **Scale:** CUDA (scale_cuda)
- **Encode:** NVIDIA NVENC (h264_nvenc, hevc_nvenc)

### Immich - AI/ML Hardware Acceleration
CUDA-accelerated machine learning for:
- **Face Detection & Recognition:** Automatic face detection and grouping
- **Object Recognition:** Smart object detection in photos
- **Smart Search:** Semantic search (e.g., "beach sunset", "dog playing")
- **Image Classification:** Automatic photo categorization
- **CLIP Embeddings:** Advanced AI-powered search capabilities

**GTX 970 Compatibility:**
- Compute Capability: 5.2 ✅ (Required: 5.2+)
- CUDA Support: Full CUDA 12.3+ support
- Performance: 5-10x faster than CPU-only ML processing

## Special Configuration for Unprivileged LXC

### Problem

NVIDIA container runtime (`runtime: nvidia`) doesn't work properly in unprivileged LXC containers due to:
1. cgroup device control restrictions
2. CUDA library mounting failures
3. nvidia-uvm device permission issues

### Solution

We bypass the NVIDIA runtime and use direct device + library mounting:

#### 1. Device Mounting (docker-compose.yml)

**For Video Transcoding (Jellyfin, Immich):**
```yaml
devices:
  - /dev/nvidia0:/dev/nvidia0
  - /dev/nvidiactl:/dev/nvidiactl
  - /dev/nvidia-modeset:/dev/nvidia-modeset
```

**For ML/CUDA Operations (Immich ML):**
```yaml
devices:
  - /dev/nvidia0:/dev/nvidia0
  - /dev/nvidiactl:/dev/nvidiactl
  - /dev/nvidia-uvm:/dev/nvidia-uvm           # CRITICAL for CUDA unified memory
  - /dev/nvidia-modeset:/dev/nvidia-modeset
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

## Immich Setup & Configuration

### Initial Setup

1. **Access Immich:** `http://<lxc-ip>:2283`
2. **Create Admin Account:** First user becomes admin
3. **Configure ML Settings:**
   - Go to Administration → Settings → Machine Learning
   - Verify "Hardware Acceleration: CUDA" is active
   - Check logs for `CUDAExecutionProvider` confirmation

### Mobile App Setup

**Official apps available:**
- iOS: [App Store](https://apps.apple.com/app/immich/id1613945652)
- Android: [Play Store](https://play.google.com/store/apps/details?id=app.alextran.immich)

**Auto-Upload Configuration:**
1. Install mobile app
2. Enter server URL: `http://<lxc-ip>:2283`
3. Login with credentials
4. Enable background upload
5. Select albums to backup

### Storage Structure

```
/datapool/
├── config/
│   └── immich/
│       ├── postgres/      # PostgreSQL database (metadata)
│       └── ml-cache/      # ML models (~5-10GB)
└── media/
    └── immich/            # Uploaded photos/videos
```

### Verifying GPU Acceleration

**Check ML service logs:**
```bash
docker logs immich-machine-learning
```

Look for:
- ✅ `Available ORT providers: ['CUDAExecutionProvider', ...]`
- ✅ `Loaded ANN model` (without errors)

**Monitor GPU usage during ML jobs:**
```bash
nvidia-smi -l 1
```

You should see GPU utilization during:
- Face detection jobs
- Smart search indexing
- Object recognition tasks

### Performance Expectations

**CPU-only ML processing:**
- Face detection: ~2-5 photos/sec
- Smart search: ~1-3 photos/sec

**GPU-accelerated (GTX 970):**
- Face detection: ~10-25 photos/sec (5-10x faster)
- Smart search: ~5-15 photos/sec (5-10x faster)
- Lower CPU usage and power consumption

### Backup Recommendations

**Critical data to backup:**
1. **PostgreSQL database:** `/datapool/config/immich/postgres/` (metadata)
2. **Photo library:** `/datapool/media/immich/` (originals)
3. **Optional:** `/datapool/config/immich/ml-cache/` (can be redownloaded)

**Backup strategy:**
- Use Proxmox Backup Server for LXC snapshots
- Consider separate photo library backup (e.g., rclone to cloud)

## References

- [Jellyfin Hardware Acceleration](https://jellyfin.org/docs/general/administration/hardware-acceleration/)
- [Immich Documentation](https://docs.immich.app/)
- [Immich ML Hardware Acceleration](https://docs.immich.app/features/ml-hardware-acceleration)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
- [Proxmox LXC GPU Passthrough](https://pve.proxmox.com/wiki/LXC#_bind_mount_points)
