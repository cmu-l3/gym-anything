from __future__ import annotations

import contextlib
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from gym_anything.runtime.runners import qemu_apptainer
from gym_anything.runtime.runners.qemu_apptainer import QemuApptainerRunner, _get_env_hash
from gym_anything.specs import EnvSpec


class QemuCheckpointKeepsTmpTests(unittest.TestCase):
    def _runner(self, workdir: Path, exec_rc: int = 0) -> QemuApptainerRunner:
        runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
        runner.spec = EnvSpec.from_dict({"id": "tmp-check@1"})
        runner.is_android = False
        runner.is_windows = False
        runner.is_macos = False
        runner._running = True
        runner._instance_qcow2 = workdir / "instance.qcow2"
        runner._checkpoint_cache_level = "post_start"
        runner._checkpoint_task_id = None
        runner._use_savevm = False
        runner._process = mock.MagicMock()
        runner.commands = []

        def fake_exec(cmd, **kwargs):
            runner.commands.append(cmd)
            return exec_rc if "tmpfiles" in cmd else 0

        runner.exec = fake_exec
        runner._get_checkpoint_path = lambda: workdir / "checkpoint.qcow2"
        runner._checkpoint_lock = lambda **kwargs: contextlib.nullcontext(True)
        runner._run_qemu_img = mock.MagicMock(return_value=mock.Mock(returncode=0, stderr=""))
        runner._start_from_image = mock.MagicMock()
        return runner

    def test_disk_checkpoint_keeps_tmp_across_its_boot(self) -> None:
        # Ubuntu's "D /tmp" empties /tmp at boot, and a disk checkpoint boots
        # afresh, so files the setup hooks left in /tmp vanished on restore.
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(qemu_apptainer.time, "sleep"):
            runner = self._runner(Path(tmp))
            self.assertTrue(runner.create_checkpoint())
        tmpfiles = [cmd for cmd in runner.commands if "/etc/tmpfiles.d/tmp.conf" in cmd]
        self.assertEqual(len(tmpfiles), 1)
        self.assertTrue(tmpfiles[0].startswith("sh -c "))
        self.assertIn("d /tmp 1777 root root -", tmpfiles[0])
        self.assertLess(runner.commands.index(tmpfiles[0]), runner.commands.index("sync"))

    def test_checkpoint_is_not_saved_without_the_tmp_override(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(qemu_apptainer.time, "sleep"):
            runner = self._runner(Path(tmp), exec_rc=1)
            self.assertFalse(runner.create_checkpoint())
        runner._run_qemu_img.assert_not_called()
        runner._process.stdin.write.assert_not_called()

    def test_savevm_checkpoint_skips_the_tmp_override(self) -> None:
        # loadvm restores RAM state without booting, so /tmp is already kept.
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(qemu_apptainer.time, "sleep"):
            workdir = Path(tmp)
            runner = self._runner(workdir, exec_rc=1)
            runner._use_savevm = True
            runner._work_dir = workdir
            runner._instance_qcow2.write_bytes(b"")
            (workdir / "qemu.log").write_text("")
            runner._run_qemu_img.return_value = mock.Mock(returncode=0, stdout="", stderr="")
            self.assertTrue(runner.create_checkpoint())
        self.assertFalse([cmd for cmd in runner.commands if "tmpfiles" in cmd])
        self.assertIn("sync", runner.commands)

    def test_checkpoint_key_includes_the_checkpoint_format(self) -> None:
        # Checkpoints baked before the /tmp override must not be reused.
        spec = EnvSpec.from_dict({"id": "tmp-check@1", "base": "ubuntu-gnome-systemd_highres"})
        current = _get_env_hash(spec)
        with mock.patch.object(qemu_apptainer, "_CHECKPOINT_FORMAT", "1"):
            self.assertNotEqual(_get_env_hash(spec), current)


if __name__ == "__main__":
    unittest.main()
