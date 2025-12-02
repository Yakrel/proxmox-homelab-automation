# Development Stack Configuration
# 
# This stack provides a development environment with:
# - Debian Linux base (required for code-server)
# - Node.js and npm (latest)
# - code-server (VS Code in browser) on port 8680
# - AI CLI tools (claude-code, gemini-cli)
# - Development packages (git, python3, vim, nano, htop)
# 
# No Docker Compose needed - managed directly by LXC manager
# See scripts/lxc-manager.sh for specific development setup
#
# Access code-server at: http://192.168.1.107:8680