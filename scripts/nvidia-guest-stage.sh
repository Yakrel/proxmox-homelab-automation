#!/bin/bash
# Offline guest inspection/staging while the menu owns a Proxmox create lock.
set -euo pipefail
ct_id=${1:?LXC ID required}
mode=${2:?check, stage or release required}
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ "$ct_id" =~ ^[0-9]+$ ]] || exit 1
case "$mode" in check|stage|release) ;; *) exit 1 ;; esac
staging=$(mktemp -d /tmp/homelab-nvidia-stage.XXXXXX)
trap 'rm -rf "$staging"' EXIT
chmod 0755 "$staging"
for file in nvidia-guest-files.sh nvidia-guest-runtime.sh nvidia-userspace-sync.sh \
    nvidia-userspace-sync.service nvidia-docker.conf; do
    install -m 0644 "$source_dir/$file" "$staging/$file"
done

# pct mount uses the special 'mounted' lock, which DOES permit starts. Keep
# our create lock instead, including throughout mapped-root file operations.
perl - "$ct_id" "$mode" "$staging" <<'PERL'
use strict;
use warnings;
use PVE::LXC;
use PVE::LXC::Config;
use PVE::Storage;
use PVE::Tools qw(run_command);
my ($vmid, $mode, $source) = @ARGV;
my $result = 0;
PVE::LXC::Config->lock_config($vmid, sub {
    my $conf = PVE::LXC::Config->load_config($vmid);
    die "CT $vmid is not held for NVIDIA maintenance\n" unless ($conf->{lock} // '') eq 'create';
    die "CT $vmid must be stopped\n" if PVE::LXC::check_running($vmid);
    die "CT $vmid must use the default unprivileged mapping\n"
        unless $conf->{unprivileged} && !grep { $_->[0] eq 'lxc.idmap' } @{$conf->{lxc} // []};
    my $storage = PVE::Storage::config();
    my $root = "/var/lib/lxc/$vmid/rootfs";
    my @mapped = ('lxc-usernsexec', '-m', 'u:0:100000:65536', '-m', 'g:0:100000:65536', '--');
    my $error;
    eval {
        PVE::LXC::mount_all($vmid, $storage, $conf);
        if ($mode eq 'stage') {
            run_command([@mapped, 'touch', "$root/etc/homelab-nvidia-maintenance"]);
            run_command([@mapped, 'bash', "$source/nvidia-guest-files.sh", $source, $root, 'apply']);
        } elsif ($mode eq 'release') {
            run_command([@mapped, 'rm', '-f', "$root/etc/homelab-nvidia-maintenance"]);
        } else {
            if (-e "$root/etc/homelab-nvidia-maintenance") {
                die "CT $vmid has unfinished NVIDIA maintenance\n";
            }
            $result = run_command([@mapped, 'bash', "$source/nvidia-guest-files.sh", $source, $root, 'check'], noerr => 1);
            if (!$result) {
                $result = run_command([@mapped, 'chroot', $root, '/bin/bash', '-s', '--', '--check-config'],
                    input => PVE::Tools::file_get_contents("$source/nvidia-guest-runtime.sh"), noerr => 1);
            }
            if (!$result) {
                $result = run_command([@mapped, 'chroot', $root, '/usr/local/bin/nvidia-userspace-sync.sh', '--check-installation'], noerr => 1);
            }
        }
        1;
    } or $error = $@;
    # Unmount even a partially mounted guest; never clear the menu's lock here.
    PVE::LXC::umount_all($vmid, $storage, $conf, 0);
    die $error if $error;
});
exit($result ? 1 : 0);
PERL
