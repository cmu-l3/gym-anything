from __future__ import annotations

import io
from pathlib import Path
import tarfile
import tempfile
import unittest

from gym_anything.runtime.runners.build_sandweave_ubuntu import sanitized_archive


class SandweaveImageBuildTests(unittest.TestCase):
    def test_release_removes_machine_state_and_preserves_file_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            source, destination = (Path(directory) / name for name in ('source.tar', 'clean.tar'))
            with tarfile.open(source, 'w', format=tarfile.PAX_FORMAT) as archive:
                logs = tarfile.TarInfo('var/log')
                logs.type, logs.mode, logs.gid = tarfile.DIRTYPE, 0o775, 111
                archive.addfile(logs)
                for name in ('etc/ssh/ssh_host_ed25519_key', 'etc/machine-id',
                             'var/lib/cloud/instance/user-data.txt', 'root/.ssh/id_ed25519',
                             'home/ga/.Xauthority', 'var/log/auth.log', 'usr/bin/application'):
                    info = tarfile.TarInfo(name)
                    info.size, info.mode, info.uid, info.gid = 7, 0o4755, 1000, 1000
                    info.pax_headers['SCHILY.xattr.user.example'] = 'retained'
                    archive.addfile(info, io.BytesIO(b'content'))
                link = tarfile.TarInfo('usr/bin/application-link')
                link.type, link.linkname = tarfile.LNKTYPE, 'usr/bin/application'
                archive.addfile(link)
            removed = sanitized_archive(source, destination)
            self.assertIn('root/.ssh/id_ed25519', removed)
            with tarfile.open(destination) as archive:
                self.assertNotIn('etc/ssh/ssh_host_ed25519_key', archive.getnames())
                self.assertNotIn('var/lib/cloud/instance/user-data.txt', archive.getnames())
                self.assertEqual(archive.extractfile('etc/machine-id').read(), b'')
                entry = archive.getmember('usr/bin/application')
                self.assertEqual((entry.mode, entry.uid, entry.gid), (0o4755, 1000, 1000))
                self.assertEqual(entry.pax_headers['SCHILY.xattr.user.example'], 'retained')
                self.assertEqual(archive.extractfile(entry).read(), b'content')
                self.assertEqual(archive.getmember('usr/bin/application-link').linkname, 'usr/bin/application')
                self.assertEqual(archive.getmember('tmp').mode, 0o1777)
                self.assertEqual((archive.getmember('var/log').mode, archive.getmember('var/log').gid), (0o775, 111))
                self.assertTrue(archive.getmember(
                    'etc/systemd/system/multi-user.target.wants/gym-image-identity.service').issym())

    def test_rejects_paths_outside_filesystem(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source.tar'
            with tarfile.open(source, 'w') as archive:
                archive.addfile(tarfile.TarInfo('../outside'))
            with self.assertRaisesRegex(ValueError, 'Unsafe archive path'):
                sanitized_archive(source, Path(directory) / 'clean.tar')
