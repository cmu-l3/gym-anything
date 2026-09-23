#!/usr/bin/env python3
"""Maintainer tool: package Gym's provisioned Ubuntu base for Sandweave workers.

Workers download the resulting image; they never run this builder or QEMU.
Requires Linux, KVM, Apptainer, fakeroot, tar, sfdisk and e2fsprogs to build.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile


GIB = 1024**3
RUNNERS = Path(__file__).parent


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while chunk := stream.read(1024**2):
            digest.update(chunk)
    return digest.hexdigest()


def require_space(path, growth=64 * GIB):
    usage = shutil.disk_usage(path)
    if usage.free - growth < max(usage.total * .15, 5 * GIB):
        raise RuntimeError(f'Insufficient build space at {path}; reserve 64 GiB and keep 15% free')


def prepare(source, work):
    import paramiko
    from .build_base_qcow2_nodocker import check_kvm
    from .qemu_apptainer import QemuApptainerRunner
    from ...specs import EnvSpec

    if not check_kvm():
        raise RuntimeError('Maintainer image builds require KVM; workers use the published image')
    if not source.is_file():
        source.parent.mkdir(parents=True, exist_ok=True)
        require_space(source.parent)
        subprocess.run([
            sys.executable, '-m', 'gym_anything.runtime.runners.build_base_qcow2_nodocker',
            '--output', str(source),
        ], check=True)

    # VM filesystem walks over a network-backed QCOW2 can be extremely slow.
    # Stage an immutable copy and hash the source in the same sequential pass.
    print('Staging source Ubuntu image on the build disk', flush=True)
    staged = work / 'source.qcow2'
    digest = hashlib.sha256()
    with source.open('rb') as incoming, staged.open('xb') as output:
        while chunk := incoming.read(1024**2):
            digest.update(chunk)
            output.write(chunk)

    class BuilderRunner(QemuApptainerRunner):
        def _get_cpu_model(self):
            return 'host'

        def _get_work_base(self):
            return work

        def _wait_for_desktop(self, timeout=120):
            # This VM only prepares files; no GUI interaction is required.
            return True

    runner = BuilderRunner(EnvSpec.from_dict({
        'id': 'sandweave-image-build@1', 'base': 'ubuntu-gnome-systemd_highres',
        'resources': {'cpu': 4, 'mem_gb': 8, 'gpu': 0, 'net': True},
        'vnc': {'password': 'password'},
    }))
    runner.base_qcow2 = staged
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        runner.start()
        client.connect('127.0.0.1', port=runner.ssh_port, username='ga', password='password123',
                       look_for_keys=False, allow_agent=False, timeout=30)

        def run(command, timeout=120):
            _, stdout, stderr = client.exec_command(command, timeout=timeout)
            output, error = stdout.read().decode(), stderr.read().decode()
            if stdout.channel.recv_exit_status():
                raise RuntimeError(error + output)
            return output

        query = "dpkg-query -W -f='${Package} ${Version} ${Status}\\n'"
        before = dict(line.split(' ', 1) for line in run(query).splitlines())
        run('sudo systemctl stop gdm3')
        with client.open_sftp() as sftp:
            sftp.put(str(RUNNERS / 'sandweave_ubuntu_setup.py'), '/tmp/gym-ubuntu-setup.py')
        (work / 'setup.log').write_text(run('sudo python3 /tmp/gym-ubuntu-setup.py', timeout=3600))
        after_text = run(query)
        after = dict(line.split(' ', 1) for line in after_text.splitlines())
        changes = {name: {'before': before.get(name), 'after': after.get(name)}
                   for name in before.keys() | after.keys() if before.get(name) != after.get(name)}
        if set(changes) - {'firefox', 'snapd'} or 'snapd' in after:
            raise RuntimeError('Unexpected package changes: ' + repr(changes))
        run('test -x /usr/lib/firefox/firefox && test ! -e /usr/bin/snap && '
            'test ! -e /var/lib/snapd && test -z "$(sudo dpkg --audit)"')
        (work / 'packages.txt').write_text(after_text)
        # Export through SSH instead of publishing the VM disk: freed blocks can
        # contain deleted machine credentials. The new disk contains only files.
        command = ('sudo tar --numeric-owner --xattrs --acls --one-file-system '
                   '--exclude=./proc --exclude=./sys --exclude=./dev --exclude=./run '
                   '--exclude=./tmp --exclude=./var/tmp --exclude=./var/log/* '
                   '--exclude=./home/ga/.cache --exclude=./root/.cache -cpf - -C / .')
        _, stdout, stderr = client.exec_command(command, timeout=3600)
        archive = work / 'prepared.tar'
        with archive.open('xb') as output:
            shutil.copyfileobj(stdout, output, 1024**2)
        errors = stderr.read().decode()
        if stdout.channel.recv_exit_status():
            raise RuntimeError('Filesystem export failed: ' + errors)
        return archive, {'source_qcow2_sha256': digest.hexdigest(), 'package_changes': changes}
    finally:
        client.close()
        runner.stop()


def sanitized_archive(source, destination):
    # Retain desktop configuration and installed packages. Remove build-machine
    # identities, credentials, caches and runtime state before public release.
    remove = (
        'dev', 'proc', 'sys', 'run', 'tmp', 'var/tmp', 'var/log', 'var/lib/cloud',
        'var/lib/sandweave', '.sandweave-runtime', 'var/lib/systemd/random-seed',
        'var/lib/NetworkManager', 'var/lib/dhcp', 'root/.cache', 'root/.launchpadlib',
        'root/.ssh', 'root/snap', 'home/ga/snap', 'home/ga/.ssh', 'home/ga/.cache',
        'home/ga/.local/share/keyrings', 'home/ga/.Xauthority', 'home/ga/.ICEauthority',
        'root/.bash_history', 'home/ga/.bash_history', 'etc/machine-id',
        'etc/ssl/private/ssl-cert-snakeoil.key', 'etc/ssl/certs/ssl-cert-snakeoil.pem',
    )
    empty_directories = {name: None for name in ('dev', 'proc', 'sys', 'run', 'tmp', 'var/tmp', 'var/log')}
    removed = []
    with tarfile.open(source, 'r|') as incoming, tarfile.open(destination, 'w', format=tarfile.PAX_FORMAT) as output:
        for member in incoming:
            name = member.name.removeprefix('./').rstrip('/')
            if name.startswith('/') or '..' in Path(name).parts:
                raise ValueError('Unsafe archive path: ' + name)
            if name in empty_directories and member.isdir():
                empty_directories[name] = member
                continue
            if (name.startswith('var/log/') and member.isdir()
                    and not name.startswith('var/log/journal/')):
                output.addfile(member)
                continue
            if (any(name == prefix or name.startswith(prefix + '/') for prefix in remove)
                    or name.startswith('etc/ssh/ssh_host_')
                    or (name.startswith('home/ga/.vnc/') and name.endswith(('.log', '.pid')))):
                removed.append(name)
                continue
            output.addfile(member, incoming.extractfile(member) if member.isfile() else None)
        for name, mode in [('dev', 0o755), ('proc', 0o555), ('sys', 0o555), ('run', 0o755),
                           ('tmp', 0o1777), ('var/tmp', 0o1777), ('var/log', 0o755)]:
            entry = empty_directories[name]
            if entry is None:
                entry = tarfile.TarInfo(name)
                entry.type, entry.mode = tarfile.DIRTYPE, mode
            output.addfile(entry)
        files = {
            'etc/machine-id': '',
            'etc/systemd/system/gym-image-identity.service': (
                '[Unit]\nDescription=Generate per-sandbox host keys\n'
                'Before=ssh.service apache2.service\nAfter=local-fs.target\n'
                '[Service]\nType=oneshot\nRemainAfterExit=yes\n'
                'ExecStart=/usr/bin/ssh-keygen -A\n'
                'ExecStart=/bin/sh -ec "test -f /etc/ssl/private/ssl-cert-snakeoil.key || '
                'make-ssl-cert generate-default-snakeoil"\n'
                '[Install]\nWantedBy=multi-user.target\n'),
        }
        for name, content in files.items():
            data = content.encode()
            entry = tarfile.TarInfo(name)
            entry.mode, entry.size = 0o644, len(data)
            output.addfile(entry, io.BytesIO(data))
        entry = tarfile.TarInfo('etc/systemd/system/multi-user.target.wants/gym-image-identity.service')
        entry.type, entry.linkname, entry.mode = tarfile.SYMTYPE, '../gym-image-identity.service', 0o777
        output.addfile(entry)
    return removed


def package(source, work, output):
    clean = work / 'rootfs.tar'
    removed = sanitized_archive(source, clean)
    rootfs = work / 'rootfs'
    rootfs.mkdir()
    raw = work / 'ubuntu.raw'
    with raw.open('xb') as disk:
        disk.truncate(12 * GIB)
    subprocess.run(['sfdisk', str(raw)], input='label: dos\nstart=2048, type=83\n', text=True, check=True)
    # fakeroot retains numeric owners, modes, device nodes and xattrs through
    # tar extraction and mke2fs without requiring host root or loop mounts.
    subprocess.run(['fakeroot', '--', 'sh', '-ec',
                    'tar --numeric-owner --same-owner --xattrs --xattrs-include="*" -xpf "$1" -C "$2"\n'
                    'mkfs.ext4 -q -F -b 4096 -m 0 -E offset=1048576,lazy_itable_init=0,lazy_journal_init=0 '
                    '-d "$2" "$3" 3145472', 'build', str(clean), str(rootfs), str(raw)], check=True)
    from .qemu_apptainer import QEMU_CACHE, QEMU_CONTAINER
    container = QEMU_CACHE / 'windows_dockur.sif'
    if not container.is_file():
        subprocess.run(['apptainer', 'pull', str(container), QEMU_CONTAINER], check=True)
    image = output / 'gym-ubuntu-22.04-amd64.qcow2'
    subprocess.run(['apptainer', 'exec', '--bind', str(work), '--bind', str(output),
                    str(container), 'qemu-img', 'convert', '-f', 'raw', '-O', 'qcow2',
                    str(raw), str(image)], check=True)
    archive = image.with_suffix('.qcow2.zip')
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        zipped.write(image, image.name)
    if archive.stat().st_size >= 2 * GIB:
        raise RuntimeError('Image exceeds the GitHub release asset limit (2 GiB)')
    return {'format': 'qcow2.zip', 'member': image.name, 'partition': 1,
            'sha256': sha256(archive), 'image_sha256': sha256(image)}, removed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New release artifact directory')
    parser.add_argument('--source-qcow2', type=Path,
                        default=Path('~/.cache/gym-anything/qemu/base_ubuntu_gnome.qcow2').expanduser())
    parser.add_argument('--prepared-rootfs', type=Path, help='Repackage a previous maintainer export')
    parser.add_argument('--provenance', type=Path, help='Required provenance for --prepared-rootfs')
    args = parser.parse_args()
    if args.prepared_rootfs and not args.provenance:
        parser.error('--prepared-rootfs requires --provenance')
    output = args.output.resolve()
    require_space(output.parent)
    output.mkdir()
    with tempfile.TemporaryDirectory(prefix='gym-image-', dir=output) as directory:
        work = Path(directory)
        if args.prepared_rootfs:
            source = args.prepared_rootfs.resolve()
            provenance = json.loads(args.provenance.read_text())
            if sha256(source) != provenance['rootfs_sha256']:
                raise ValueError('Prepared filesystem checksum differs from its provenance')
            if provenance['setup_sha256'] != sha256(RUNNERS / 'sandweave_ubuntu_setup.py'):
                raise ValueError('Prepared filesystem used a different Ubuntu setup recipe')
        else:
            source, provenance = prepare(args.source_qcow2.resolve(), work)
        provenance.update(
            rootfs_sha256=sha256(source),
            setup_sha256=sha256(RUNNERS / 'sandweave_ubuntu_setup.py'),
            provisioning_sha256=sha256(RUNNERS / 'build_base_qcow2_nodocker.py'),
            builder_sha256=sha256(Path(__file__)),
        )
        require_space(work)
        image, removed = package(source, work, output)
        (output / 'image.json').write_text(json.dumps({'image': image, 'provenance': provenance}, indent=2) + '\n')
        (output / 'removed-paths.json').write_text(json.dumps(removed, indent=2) + '\n')
        for name in ('setup.log', 'packages.txt'):
            if (work / name).exists():
                shutil.copyfile(work / name, output / name)
        (output / 'SHA256SUMS').write_text(''.join(
            f'{sha256(path)}  {path.name}\n' for path in sorted(output.iterdir()) if path.is_file()))
    print('Release artifacts:', output)


if __name__ == '__main__':
    main()
