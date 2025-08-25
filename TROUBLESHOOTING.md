# Troubleshooting Guide - Proxmox Homelab Automation

## Common Issues and Solutions

### API Token Errors

**Problem**: `[ERROR] Failed to get API token. Playbook execution aborted.`

This error occurs when the installer cannot create or extract the Proxmox API token needed for Ansible to communicate with Proxmox.

**Solutions**:

1. **Run with debug mode** to get detailed diagnostics:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh) --debug
   ```

2. **Check API user exists and has permissions**:
   ```bash
   # Check if the API user exists
   pveum user list | grep ansible-bot@pve
   
   # Check user permissions
   pveum acl list / | grep ansible-bot@pve
   ```

3. **Manually recreate API user** (if needed):
   ```bash
   # Remove existing user (if exists)
   pveum user delete ansible-bot@pve
   
   # Create new user with Administrator role
   pveum user add ansible-bot@pve --comment "Ansible Automation User"
   pveum acl modify / --user ansible-bot@pve --role Administrator
   ```

4. **Check token operations**:
   ```bash
   # List existing tokens
   pveum user token list ansible-bot@pve
   
   # Delete problematic tokens
   pveum user token delete ansible-bot@pve ansible-token
   ```

### Storage Pool Issues

**Problem**: Storage pool 'datapool' not found

**Solutions**:

1. **Check available storage pools**:
   ```bash
   pvesm status
   ```

2. **Create the datapool storage** (if missing):
   - Use Proxmox web interface: Datacenter → Storage → Add
   - Or modify the `STORAGE_POOL` variable in `installer.sh` to match your existing storage

### Control Node Issues

**Problem**: LXC 151 fails to start or create

**Solutions**:

1. **Check LXC status**:
   ```bash
   pct status 151
   pct start 151
   ```

2. **Check for conflicting containers**:
   ```bash
   pct list | grep 151
   ```

3. **Review container configuration**:
   ```bash
   pct config 151
   ```

### Network Issues

**Problem**: Containers cannot reach Proxmox API or internet

**Solutions**:

1. **Verify network configuration** in `stacks.yaml`:
   - Check `network.ip_base` matches your network
   - Verify `network.gateway` is correct
   - Ensure `network.bridge` exists

2. **Test connectivity from container**:
   ```bash
   pct exec 151 -- ping 192.168.1.1
   pct exec 151 -- curl -k https://192.168.1.10:8006/api2/json/version
   ```

### Ansible Vault Issues

**Problem**: Vault password prompts or vault errors

**Solutions**:

1. **Create vault password file** (optional):
   ```bash
   pct exec 151 -- bash -c "echo 'your-vault-password' > /root/.vault_pass"
   ```

2. **Verify secrets file is encrypted**:
   ```bash
   pct exec 151 -- head -1 /root/proxmox-homelab-automation/secrets.yml
   # Should show: $ANSIBLE_VAULT;1.1;AES256
   ```

## Debug Commands

### Check installer environment:
```bash
# Run installer with help
./installer.sh --help

# Run with debug output
./installer.sh --debug

# Check Proxmox commands are available
which pct pveum
```

### Manual token testing:
```bash
# Test token creation manually
pveum user token add ansible-bot@pve test-token --comment "Manual test"

# Extract token secret (look for UUID format)
pveum user token add ansible-bot@pve test-token2 --comment "Test" 2>&1 | grep -oE '[0-9a-f-]{36}'

# Clean up test tokens
pveum user token delete ansible-bot@pve test-token
pveum user token delete ansible-bot@pve test-token2
```

### Check Control Node status:
```bash
# Container status and configuration
pct status 151
pct config 151

# Test execution inside container
pct exec 151 -- whoami
pct exec 151 -- cd /root/proxmox-homelab-automation && pwd

# Check Ansible installation
pct exec 151 -- which ansible-playbook
pct exec 151 -- ansible --version
```

## Getting Help

If you continue to experience issues:

1. Run the installer with `--debug` flag and capture the output
2. Check the Proxmox VE system log: `/var/log/syslog` or `/var/log/pve/tasks/`
3. Verify your Proxmox VE version compatibility
4. Ensure you have Administrator privileges on the Proxmox host
5. Check that all prerequisites from the README are met

## Recovery Actions

### Complete reset (if needed):
```bash
# Stop and destroy Control Node
pct stop 151
pct destroy 151

# Remove API user
pveum user delete ansible-bot@pve

# Re-run installer (will perform fresh setup)
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```

### Partial reset (keep containers, reset API):
```bash
# Just remove API user and tokens
pveum user token delete ansible-bot@pve ansible-token
pveum user delete ansible-bot@pve

# Re-run installer (will recreate API user only)
bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh)
```