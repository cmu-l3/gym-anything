#!/usr/bin/env python3
"""Adapt an imported Gym QEMU Ubuntu filesystem for the Sandweave desktop."""
import os
from pathlib import Path
import subprocess


def main():
    os.environ['DEBIAN_FRONTEND'] = 'noninteractive'
    if ('VERSION_ID="22.04"' not in Path('/etc/os-release').read_text()
            or not Path('/home/ga/.provisioning_complete').is_file()):
        raise RuntimeError('Import the provisioned Gym Anything QEMU Ubuntu base first')
    for kind, section in [('service', 'Service'), ('mount', 'Mount')]:
        directory = Path('/etc/systemd/system') / (kind + '.d')
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'sandweave.conf').write_text(f'[{section}]\nKeyringMode=inherit\n')
    # The imported filesystem is already provisioned, and has no VM block devices.
    Path('/etc/cloud/cloud-init.disabled').touch()
    # Filesystem checkpoints must retain task files under /tmp across boot.
    Path('/etc/tmpfiles.d/tmp.conf').write_text('d /tmp 1777 root root -\n')
    fstab = Path('/etc/fstab')
    fstab.write_text(''.join('# Sandweave root image: ' + line if line.strip() and not line.startswith('#')
                            and line.split()[1] in ('/', '/boot/efi') else line
                            for line in fstab.read_text().splitlines(keepends=True)))
    units = Path('/etc/systemd/system')
    def mask(name):
        path = units / name
        path.unlink(missing_ok=True)
        path.symlink_to('/dev/null')
    # Xvnc owns the display; Sandweave owns the devices, network and scheduler.
    for name in ['gdm.service', 'gdm3.service', 'acpid.service', 'acpid.socket',
                 'systemd-sysctl.service', 'systemd-udevd.service',
                 'systemd-udevd-control.socket', 'systemd-udevd-kernel.socket',
                 'NetworkManager.service', 'NetworkManager-wait-online.service',
                 'systemd-networkd.service', 'systemd-networkd.socket',
                 'systemd-networkd-wait-online.service', 'systemd-resolved.service',
                 'avahi-daemon.service', 'avahi-daemon.socket', 'rtkit-daemon.service']:
        mask(name)
    directory = units / 'e2scrub_reap.service.d'
    directory.mkdir(exist_ok=True)
    (directory / 'sandweave.conf').write_text('[Service]\nPrivateNetwork=no\n')
    # Retain Ubuntu's session, theme, extensions, package versions and user config.
    Path('/home/ga/.vnc/xstartup').unlink(missing_ok=True)
    Path('/etc/tigervnc').mkdir(exist_ok=True)
    Path('/etc/tigervnc/vncserver.users').write_text(':1=ga\n')
    config = Path('/home/ga/.vnc/config')
    config.write_text('session=ubuntu\ngeometry=1920x1080\ndepth=24\nlocalhost=no\nalwaysshared\nsecuritytypes=vncauth\n')
    subprocess.run(['chown', 'ga:ga', str(config)], check=True)
    subprocess.run(['systemctl', '--root=/', 'enable', 'tigervncserver@:1.service'], check=True)
    password = Path('/etc/sandweave-vnc-password')
    password.write_text('password\n')
    password.chmod(0o600)
    # Native Firefox is the accepted replacement for the unsupported Snap browser.
    subprocess.run(['add-apt-repository', '-y', '-n', 'ppa:mozillateam/ppa'], check=True)
    Path('/etc/apt/preferences.d/mozilla-firefox').write_text(
        'Package: firefox firefox-locale-*\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n')
    subprocess.run(['apt-get', 'update'], check=True)
    policy = Path('/usr/sbin/policy-rc.d')
    previous = policy.read_bytes() if policy.exists() else None
    previous_mode = policy.stat().st_mode & 0o777 if policy.exists() else None
    policy.write_text('#!/bin/sh\nexit 101\n')
    policy.chmod(0o755)
    try:
        subprocess.run(['apt-get', 'install', '-y', '--no-install-recommends', '--allow-downgrades', 'firefox'], check=True)
        subprocess.run(['apt-get', 'purge', '-y', 'snapd'], check=True)
    finally:
        if previous is None:
            policy.unlink()
        else:
            policy.write_bytes(previous)
            policy.chmod(previous_mode)
    # Remove imported Snap unit links and user autostart after the package purge.
    for directory in [units, Path('/etc/systemd/user')]:
        for pattern in ['snap-*', 'snap.*', 'snapd.*']:
            for path in directory.rglob(pattern):
                if path.is_symlink() or path.is_file():
                    path.unlink()
    Path('/home/ga/.config/autostart/snap-userd-autostart.desktop').unlink(missing_ok=True)
    subprocess.run(['apt-get', 'clean'], check=True)
    # Preserve the original dock's Firefox entry after replacing the Snap package.
    Path('/usr/share/applications/firefox_firefox.desktop').symlink_to('firefox.desktop')


if __name__ == '__main__':
    main()
