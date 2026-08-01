# TODO

## PVE storage and backup verification

- [ ] Collect the following read-only state and review any failures:

  ```bash
  date --iso-8601=seconds
  pveversion
  pct status 102

  pct exec 102 -- docker inspect backrest \
    --format 'status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} restarts={{.RestartCount}} started={{.State.StartedAt}}'
  pct exec 102 -- docker logs --since 168h backrest 2>&1 \
    | grep -Ei 'config-backup|snapshot|success|error|failed|prune|check' \
    | tail -n 160

  systemctl is-active sanoid.timer
  systemctl list-timers sanoid.timer --no-pager
  zfs list -H -t snapshot -o name,creation -s creation -r fastpool | tail -n 20
  ```

## Safety

- Do not paste or record raw `.env` data, `docker inspect .Config.Env`, or the repository encryption key.
