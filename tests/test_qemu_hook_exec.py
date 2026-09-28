from __future__ import annotations

import threading
import time
import unittest
from unittest import mock

from gym_anything.runtime.runners.qemu_apptainer import QemuApptainerRunner


def _runner(family: str = "linux") -> QemuApptainerRunner:
    runner = QemuApptainerRunner.__new__(QemuApptainerRunner)
    runner.get_platform_family = lambda: family
    runner._ssh_user, runner._ssh_password, runner.ssh_port = "ga", "pw", 2222
    runner.is_windows = runner.is_android = False
    return runner


class QemuHookWrapperTests(unittest.TestCase):
    def _run(self, family="linux", command="/workspace/scripts/install.sh", **kwargs):
        runner = _runner(family)
        sent = []
        runner.exec = lambda cmd, **kw: sent.append((cmd, kw)) or 0
        runner.run_hook(command, **kwargs)
        return sent[0]

    def test_linux_hooks_read_dev_null_and_have_a_backstop(self) -> None:
        # composer run as root on a terminal asks "Continue as root?" and
        # waits forever; /dev/null gives it EOF.
        cmd, kwargs = self._run(stage="pre_start", timeout=1800)
        self.assertEqual(
            cmd,
            "timeout -k 30 3600 bash -lc /workspace/scripts/install.sh"
            " < /dev/null > /home/ga/env_setup_pre_start.log 2>&1",
        )
        self.assertEqual(kwargs, {"timeout": 3660, "deadline": 3720})

    def test_a_longer_timeout_wins_and_pre_task_keeps_its_pty_choice(self) -> None:
        cmd, kwargs = self._run(stage="pre_task", timeout=5400, use_pty=False)
        self.assertTrue(cmd.startswith("timeout -k 30 5400 bash -lc "))
        self.assertTrue(cmd.endswith("< /dev/null > /home/ga/task_pre_task.log 2>&1"))
        self.assertIs(kwargs["use_pty"], False)

    def test_hook_timeout_setting_applies_to_install_hooks(self) -> None:
        for value in ("7200", "600"):
            with mock.patch.dict("os.environ", {"GYM_ANYTHING_HOOK_TIMEOUT": value}):
                cmd, _ = self._run(stage="post_start")
            self.assertTrue(cmd.startswith(f"timeout -k 30 {value} bash -lc "), cmd)

    def test_a_non_positive_hook_timeout_setting_is_ignored(self) -> None:
        for value in ("0", "-5", ""):
            with mock.patch.dict("os.environ", {"GYM_ANYTHING_HOOK_TIMEOUT": value}):
                cmd, _ = self._run(stage="pre_start")
            self.assertTrue(cmd.startswith("timeout -k 30 3600 bash -lc "), cmd)

    def test_task_hooks_get_the_shorter_backstop(self) -> None:
        cmd, kwargs = self._run(stage="pre_task", timeout=600)
        self.assertTrue(cmd.startswith("timeout -k 30 1200 bash -lc "), cmd)
        self.assertEqual(kwargs["deadline"], 1320)
        cmd, _ = self._run(stage="post_task")
        self.assertTrue(cmd.startswith("timeout -k 30 1200 bash -lc "), cmd)

    def test_windows_hooks_are_untouched(self) -> None:
        cmd, _ = self._run("windows", command="powershell -File C:\\x.ps1", stage="pre_start")
        self.assertEqual(cmd, "powershell -File C:\\x.ps1")


def _block_until_closed(client):
    """Make `client.close()` release anything waiting on the returned event."""
    closed = threading.Event()
    client.close.side_effect = closed.set
    return lambda *a, **k: closed.wait(5) and (_ for _ in ()).throw(EOFError("closed"))


class _Channel:
    """A remote command that exits only once its output is read."""

    def __init__(self, chunks, exit_code=0, hung=False):
        self.status_event = threading.Event()
        self._chunks = list(chunks)
        self._exit_code = exit_code
        self._hung = hung

    def recv_ready(self):
        return self._hung == "hot" or bool(self._chunks)

    def recv(self, n):
        if self._hung == "hot":
            return b"y"
        chunk = self._chunks.pop(0)
        if not self._chunks and not self._hung:
            self.status_event.set()
        return chunk

    def recv_stderr_ready(self):
        return False

    def recv_exit_status(self):
        # paramiko blocks here until the exit status arrives.
        if not self.status_event.wait(2):
            raise AssertionError("recv_exit_status() before the output was read")
        return self._exit_code


def _paramiko_client(channel, tail=b""):
    stdout = mock.Mock(channel=channel)
    stdout.read.return_value = tail
    stderr = mock.Mock()
    stderr.read.return_value = b""
    client = mock.Mock()
    client.exec_command.return_value = (mock.Mock(), stdout, stderr)
    return client


class QemuParamikoExecTests(unittest.TestCase):
    def test_output_past_the_ssh_window_is_read_while_waiting(self) -> None:
        channel = _Channel([b"x" * 65536] * 50, exit_code=3)  # ~3 MB, past the 2 MB window
        client = _paramiko_client(channel, tail=b"tail")
        with mock.patch("paramiko.SSHClient", return_value=client):
            result = _runner()._ssh_with_paramiko("cat big.log", True, 600)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, b"x" * (50 * 65536) + b"tail")

    def test_a_frozen_guest_hits_the_host_deadline(self) -> None:
        client = _paramiko_client(_Channel([], hung=True))
        with mock.patch("paramiko.SSHClient", return_value=client):
            result = _runner()._ssh_with_paramiko("bash -lc /workspace/setup.sh", True, 3660, deadline=1)
        self.assertEqual(result.returncode, 124)
        client.close.assert_called()

    def _frozen(self, client) -> None:
        with mock.patch("paramiko.SSHClient", return_value=client):
            start = time.monotonic()
            result = _runner()._ssh_with_paramiko("bash -lc /workspace/setup.sh", True, 3660, deadline=0.3)
        self.assertEqual(result.returncode, 124)
        self.assertLess(time.monotonic() - start, 3)

    def test_a_blocked_exec_request_hits_the_host_deadline(self) -> None:
        client = _paramiko_client(_Channel([]))
        client.exec_command.side_effect = _block_until_closed(client)
        self._frozen(client)

    def test_a_blocked_eof_read_hits_the_host_deadline(self) -> None:
        channel = _Channel([b"x"])  # exit status arrives, EOF never does
        client = _paramiko_client(channel)
        client.exec_command.return_value[1].read.side_effect = _block_until_closed(client)
        self._frozen(client)

    def test_endless_output_hits_the_host_deadline(self) -> None:
        self._frozen(_paramiko_client(_Channel([], hung="hot")))

    def test_exec_passes_the_deadline_to_ssh(self) -> None:
        runner = _runner()
        runner.merge_exec_env = lambda env: {}
        runner._ssh_command = mock.Mock(return_value=mock.Mock(returncode=0))
        runner.exec("true", timeout=70, deadline=130)
        runner._ssh_command.assert_called_once_with("sudo -E true", use_pty=True, timeout=70, deadline=130)


if __name__ == "__main__":
    unittest.main()
