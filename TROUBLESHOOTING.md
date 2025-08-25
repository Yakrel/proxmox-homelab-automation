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
   # Check if the API user exists (look for exact match)
   pveum user list | grep "^ansible-bot@pve"
   
   # Check user permissions (should show Administrator role)
   pveum acl list / | grep ansible-bot@pve
   ```

3. **Manually recreate API user** (if needed):
   ```bash
   # Remove existing user (if exists)
   pveum user delete ansible-bot@pve 2>/dev/null || true
   
   # Create new user with Administrator role
   pveum user add ansible-bot@pve --comment "Ansible Automation User"
   pveum acl modify / --user ansible-bot@pve --role Administrator
   
   # Verify the user was created correctly
   pveum user list | grep ansible-bot@pve
   pveum acl list / | grep ansible-bot@pve
   ```

4. **Test token operations manually**:
   ```bash
   # List existing tokens
   pveum user token list ansible-bot@pve
   
   # Delete any problematic tokens
   pveum user token delete ansible-bot@pve ansible-token 2>/dev/null || true
   
   # Test token creation and extraction
   pveum user token add ansible-bot@pve test-token --comment "Manual test"
   
   # Verify token secret extraction (should show UUID format)
   pveum user token add ansible-bot@pve test-token2 --comment "Test" 2>&1 | grep -oE '[0-9a-f-]{36}'
   
   # Clean up test tokens
   pveum user token delete ansible-bot@pve test-token
   pveum user token delete ansible-bot@pve test-token2
   ```

5. **Advanced diagnostics** (if above steps don't work):
   ```bash
   # Check Proxmox VE version compatibility
   pveversion
   
   # Verify pveum command works properly
   pveum user list | head -5
   
   # Check for permission issues
   id
   groups
   
   # Test raw token creation with full output
   pveum user token add ansible-bot@pve diagnostic-token --comment "Full diagnostic" 2>&1
   pveum user token delete ansible-bot@pve diagnostic-token 2>/dev/null
   ```

**If manual token operations work but the installer still fails:**

This usually indicates an issue with the installer's user detection or token extraction logic. Try:

1. **Force debug mode and check the exact error**:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/Yakrel/proxmox-homelab-automation/main/installer.sh) --debug 2>&1 | tee debug.log
   ```

2. **Check if the issue is with user detection**:
   ```bash
   # Test the exact command the installer uses
   API_USER="ansible-bot@pve"
   pveum user list 2>/dev/null | awk -v u="$API_USER" '$1==u { found=1 } END { exit !found }' && echo "User found" || echo "User not found"
   ```

3. **Check if the issue is with token extraction**:
   ```bash
   # Create a token and test extraction methods
   TOKEN_OUTPUT=$(pveum user token add ansible-bot@pve extract-test --comment "Extraction test" 2>&1)
   echo "=== Raw output ==="
   echo "$TOKEN_OUTPUT"
   echo "=== Primary extraction ==="
   echo "$TOKEN_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1
   echo "=== Alternative extraction ==="
   echo "$TOKEN_OUTPUT" | grep -i "value" | grep -oE '[0-9a-f-]{36}' | head -1
   # Clean up
   pveum user token delete ansible-bot@pve extract-test 2>/dev/null
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
# Test token creation manually (basic test)
pveum user token add ansible-bot@pve test-token --comment "Manual test"

# Test token creation with full output analysis
TOKEN_OUTPUT=$(pveum user token add ansible-bot@pve test-token2 --comment "Test" 2>&1)
echo "=== Full token creation output ==="
echo "$TOKEN_OUTPUT"
echo "=== UUID extraction test ==="
echo "$TOKEN_OUTPUT" | grep -oE '[0-9a-f-]{36}'
echo "=== Primary regex test ==="
echo "$TOKEN_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

# Test user detection logic (same as installer uses)
API_USER="ansible-bot@pve"
pveum user list 2>/dev/null | awk -v u="$API_USER" '$1==u { found=1 } END { exit !found }' && echo "User detection: SUCCESS" || echo "User detection: FAILED"

# Clean up test tokens
pveum user token delete ansible-bot@pve test-token 2>/dev/null
pveum user token delete ansible-bot@pve test-token2 2>/dev/null
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