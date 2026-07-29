# TODO

## Agentmemory deployment

- [ ] On the Proxmox host, update the repository and ensure the Dev LXC is running:

  ```bash
  cd /root/proxmox-homelab-automation
  git pull --ff-only
  pct status 105
  # Run only when CT 105 is stopped:
  pct start 105
  ```

- [ ] Redeploy the AI and Dev stacks from the same revision:

  ```bash
  bash scripts/fast-redeploy.sh ai dev
  ```

- [ ] Verify Agentmemory and Pi after redeployment:

  ```bash
  pct exec 104 -- docker inspect agentmemory \
    --format 'status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} restarts={{.RestartCount}} image={{.Config.Image}} started={{.State.StartedAt}}'

  pct exec 104 -- docker inspect agentmemory \
    --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -E '^(AGENT_ID|AGENTMEMORY_AUTO_COMPRESS|AGENTMEMORY_INJECT_CONTEXT|CONSOLIDATION_ENABLED|GRAPH_EXTRACTION_ENABLED|AGENTMEMORY_GRAPH_WEIGHT|AGENTMEMORY_SLOTS|AGENTMEMORY_REFLECT|AUTO_FORGET_ENABLED)='

  pct exec 105 -- pi --version
  pct exec 105 -- test -r /root/.pi/agent/extensions/agentmemory/client.ts
  ```

- [ ] Start Pi interactively and run `/agentmemory-status`.

## PVE storage and backup verification

- [ ] Collect the following read-only state and review any failures:

  ```bash
  date --iso-8601=seconds
  pveversion
  pct status 102
  pct status 104
  pct status 105

  pct config 104 | grep -E '^(hostname|unprivileged|mp[0-9]+):'
  pct exec 104 -- docker inspect agentmemory \
    --format '{{range .Mounts}}{{println .Source "->" .Destination "rw=" .RW}}{{end}}'
  pct exec 104 -- du -sh /data
  pct exec 104 -- sh -lc 'find /data -type f | wc -l'

  stat -c '%U:%G %a %n' /fastpool/config/agentmemory
  find /fastpool/config/agentmemory -maxdepth 3 -type f \
    -printf '%P %s bytes\n' | sort | head -n 100

  pct exec 104 -- docker logs --since 168h agentmemory 2>&1 \
    | grep -Ei 'error|warn|failed|timeout|unauthorized|critical' \
    | tail -n 120

  pct exec 102 -- docker inspect backrest \
    --format 'status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} restarts={{.RestartCount}} started={{.State.StartedAt}}'
  pct exec 102 -- docker logs --since 168h backrest 2>&1 \
    | grep -Ei 'config-backup|snapshot|success|error|failed|prune|check' \
    | tail -n 160

  systemctl is-active sanoid.timer
  systemctl list-timers sanoid.timer --no-pager
  zfs list -H -t snapshot -o name,creation -s creation -r fastpool | tail -n 20
  ```

## Legacy memory review

- [ ] Manually review the 26 pre-scope durable memories. They currently have no project, are excluded from Pi recall, and must not be assigned to a project automatically.
- [ ] Re-save only still-relevant items into the correct project and delete obsolete items after review.

## Safety

- Do not paste or record raw `.env` data, `docker inspect .Config.Env`, `/root/.config/agentmemory/secret`, or the repository encryption key.
- Graph extraction remains disabled. The live audit found zero graph nodes and edges, so no graph reset is required.
