# Desktop Workspace

Lightweight containerized desktop environment with Google Chrome, Obsidian, and file management. Web-based access via Selkies-GStreamer.

## Features

- **Google Chrome** - Latest stable version
- **Obsidian** - Latest version from official releases
- **PCManFM** - Lightweight file manager
- **Web Access** - Use from any browser via HTTPS
- **Auto-updates** - Weekly builds with latest packages

## Quick Start

```bash
# Setup environment
cp .env.example .env
nano .env  # Set your credentials

# Deploy
docker compose up -d
```

Access at `https://your-server-ip:5800`

**Note:** This project is designed to be deployed as part of the webtools stack in the main homelab automation repository.

## Usage

- Chrome auto-launches on start
- Right-click desktop for app menu
- Alt+Tab to switch between apps

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `CUSTOM_USER` | Web interface username |
| `PASSWORD` | Web interface password |
| `TZ` | Timezone (default: Europe/Istanbul) |

### Security Options

```yaml
security_opt:
  - seccomp:unconfined  # Required for Chrome
shm_size: "1gb"         # Required for Electron apps
```

Chrome and Obsidian require these settings for proper sandboxing and rendering.

## Updates

### Automatic (Watchtower)

Image is rebuilt weekly via GitHub Actions. Watchtower will auto-update if configured.

### Manual

```bash
docker compose pull
docker compose up -d
```

## Development

### Local Build

```bash
docker compose -f docker-compose.build.yml build
docker compose -f docker-compose.build.yml up -d
```

### Adding Applications

Edit `Dockerfile` and add packages:

```dockerfile
RUN apt-get update && \
    apt-get install -y your-package && \
    rm -rf /var/lib/apt/lists/*
```

Customize menu in `root/defaults/menu.xml` and autostart in `root/defaults/autostart`.

## Troubleshooting

### Black screen or crashes

- Ensure `shm_size: "1gb"` is set
- Verify `security_opt: seccomp:unconfined` is present

### Check logs

```bash
docker compose logs -f
```

## Technical Stack

- **Base**: LinuxServer baseimage-selkies (Debian)
- **Desktop**: Openbox window manager
- **Streaming**: Selkies-GStreamer (WebRTC)
- **Web Server**: NGINX with HTTPS

## License

MIT License - Personal homelab project.

Component licenses:
- Chrome: Proprietary (Google)
- Obsidian: Proprietary (Obsidian.md)
- PCManFM: GPL-2.0
