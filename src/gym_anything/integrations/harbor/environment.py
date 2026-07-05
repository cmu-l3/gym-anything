"""Gym-anything environments as Harbor environment backends.

Harbor (github.com/laude-institute/harbor) drives each trial's environment
through its ``BaseEnvironment`` interface: ``start``/``stop`` for lifecycle,
``exec`` plus file transfer for the agent and verifier phases. This adapter
implements that interface on top of the gym-anything runtime, so Harbor tasks
compiled from a gym-anything benchmark (see ``compile``) boot the real
guest (QEMU, AVD, ...) through the standard runner stack instead of a Docker
container.

Select it per run with::

    harbor run ... --env gym_anything.integrations.harbor:GymAnythingEnvironment

Contract mapping:

* ``start()`` -> ``from_config(env_dir, task_id).reset(...)`` — the same boot
  path the verifiers adapter uses, including checkpoint caching.
* ``exec()`` -> guest execution through the runner (SSH/ADB). The runner runs
  Linux commands with root privileges; Harbor's per-call ``user`` is accepted
  but not enforced in this first backend.
* ``upload_* / download_*`` -> runner file transfer. Transfers stage through
  ``/tmp`` in the guest and use the runner's privileged exec for the final
  move, because Harbor's contract paths (``/tests``, ``/logs/verifier``) are
  root-owned while the transfer channel runs as the unprivileged guest user.
* Verification: Harbor uploads ``tests/`` and execs ``/tests/test.sh``, then
  reads ``/logs/verifier/reward.json``. The compiled ``test.sh`` is a contract
  marker; this environment intercepts its invocation and runs the task's real
  grading pipeline host-side (the ``post_task`` export hook plus
  ``verifier.py`` via ``env.step(mark_done=True)``), then writes the reward
  file into the guest where Harbor's Verifier collects it. Grading
  deliberately stays outside the agent-controlled guest.
"""

from __future__ import annotations

import asyncio
import json
import shlex
import shutil
import tempfile
import uuid
from functools import cached_property
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Optional

from harbor.environments.base import BaseEnvironment, ExecResult
from harbor.environments.capabilities import EnvironmentCapabilities

GA_ENV_CONFIG_FILENAME = "gym-anything.json"

# Harbor's in-environment path contract (EnvironmentPaths for POSIX guests).
_TESTS_SCRIPT_PATH = "/tests/test.sh"
_VERIFIER_DIR = "/logs/verifier"
_REWARD_JSON_PATH = f"{_VERIFIER_DIR}/reward.json"


class GymAnythingEnvironment(BaseEnvironment):
    """Harbor environment backend that boots gym-anything guests."""

    def __init__(self, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        self._env = None  # gym_anything.env.GymAnythingEnv
        self._verify_result: Optional[ExecResult] = None

    # -- identity / capabilities -------------------------------------------

    @staticmethod
    def type() -> str:
        return "gym-anything"

    @property
    def capabilities(self) -> EnvironmentCapabilities:
        return EnvironmentCapabilities()

    # -- definition ----------------------------------------------------------

    @cached_property
    def _ga_config(self) -> Dict[str, Any]:
        path = self.environment_dir / GA_ENV_CONFIG_FILENAME
        return json.loads(path.read_text())

    def _validate_definition(self):
        config_path = self.environment_dir / GA_ENV_CONFIG_FILENAME
        if not config_path.is_file():
            raise FileNotFoundError(
                f"gym-anything Harbor tasks need environment/{GA_ENV_CONFIG_FILENAME}; "
                f"not found in {self.environment_dir}"
            )

    # -- lifecycle -----------------------------------------------------------

    async def start(self, force_build: bool) -> None:
        await asyncio.to_thread(self._start_sync, force_build)

    def _start_sync(self, force_build: bool) -> None:
        from .container import boot_env

        env = boot_env(self._ga_config, force_build=force_build)
        # Docker images get these from harbor's mount structure; a guest VM
        # must create them so phase log/artifact transfers have a target.
        env.runner.exec(
            self._root_shell(
                "mkdir -p /logs/agent /logs/verifier /logs/artifacts && chmod -R 777 /logs"
            ),
            use_pty=False,
        )
        self._env = env

    async def stop(self, delete: bool):
        await asyncio.to_thread(self._stop_sync)

    def _stop_sync(self) -> None:
        if self._env is not None:
            self._env.close()
            self._env = None

    # -- gym-anything access -------------------------------------------------

    @property
    def gym_env(self):
        """The live GymAnythingEnv, for gym-anything-aware Harbor agents."""
        if self._env is None:
            raise RuntimeError("gym-anything environment has not been started")
        return self._env

    @property
    def _runner(self):
        return self.gym_env.runner

    # -- exec ------------------------------------------------------------------

    async def exec(
        self,
        command: str,
        cwd: str | None = None,
        env: dict[str, str] | None = None,
        timeout_sec: int | None = None,
        user: str | int | None = None,
    ) -> ExecResult:
        if _is_verifier_invocation(command):
            return await asyncio.to_thread(self._verify_sync, env)
        return await asyncio.to_thread(
            self._exec_sync, command, cwd, env, timeout_sec, user
        )

    def _exec_sync(
        self,
        command: str,
        cwd: str | None,
        env: dict[str, str] | None,
        timeout_sec: int | None,
        user: str | int | None,
    ) -> ExecResult:
        runner = self._runner
        token = uuid.uuid4().hex
        out_path = f"/tmp/.hb-{token}.out"
        err_path = f"/tmp/.hb-{token}.err"
        wrapped = command if cwd is None else f"cd {shlex.quote(cwd)} && {command}"
        redirected = f"sh -c {shlex.quote(wrapped)} > {out_path} 2> {err_path}"
        return_code = runner.exec(
            redirected,
            env=env,
            user=str(user) if user is not None else None,
            use_pty=False,
            timeout=int(timeout_sec or 600),
        )
        stdout = runner.exec_capture(
            self._root_shell(f"cat {out_path} 2>/dev/null; rm -f {out_path}")
        )
        stderr = runner.exec_capture(
            self._root_shell(f"cat {err_path} 2>/dev/null; rm -f {err_path}")
        )
        return ExecResult(stdout=stdout, stderr=stderr, return_code=return_code)

    # -- verification ----------------------------------------------------------

    def _verify_sync(self, verifier_env: dict[str, str] | None = None) -> ExecResult:
        from .container import apply_verifier_config, finalize_episode, rewards_from_verdict

        if self._verify_result is not None:
            return self._verify_result
        # Harbor resolves [verifier.env] (the grader credentials) into the
        # verifier phase; re-apply the task's verifier overrides with it.
        apply_verifier_config(self.gym_env, self._ga_config, verifier_env)
        reward, verifier = finalize_episode(self.gym_env)
        rewards = rewards_from_verdict(reward, verifier)

        self._write_guest_file(_REWARD_JSON_PATH, json.dumps(rewards))
        if isinstance(verifier, dict):
            self._write_guest_file(
                f"{_VERIFIER_DIR}/verifier.json", json.dumps(verifier, default=str)
            )

        feedback = verifier.get("feedback") if isinstance(verifier, dict) else None
        self._verify_result = ExecResult(
            stdout=str(feedback or ""), stderr=None, return_code=0
        )
        return self._verify_result

    def _write_guest_file(self, guest_path: str, content: str) -> None:
        with tempfile.NamedTemporaryFile(
            "w", suffix=Path(guest_path).suffix, delete=False
        ) as handle:
            handle.write(content)
            host_path = handle.name
        try:
            self._upload_file_sync(host_path, guest_path)
        finally:
            Path(host_path).unlink(missing_ok=True)

    # -- file transfer -----------------------------------------------------------
    #
    # The runner's transfer channel runs as the unprivileged guest user, while
    # Harbor's contract paths are root-owned. Every transfer therefore stages
    # through /tmp in the guest and lets the runner's privileged exec do the
    # final move (or the initial copy-out). Compound commands must go through
    # _root_shell: the runner elevates by prefixing ``sudo -E`` onto the
    # command string, so a bare ``a && b`` would run only ``a`` as root.

    @staticmethod
    def _root_shell(command: str) -> str:
        return f"sh -c {shlex.quote(command)}"

    async def upload_file(self, source_path: Path | str, target_path: str):
        await asyncio.to_thread(self._upload_file_sync, str(source_path), str(target_path))

    def _upload_file_sync(self, source_path: str, target_path: str) -> None:
        runner = self._runner
        stage = f"/tmp/.hb-in-{uuid.uuid4().hex}"
        runner.copy_to(source_path, stage)
        parent = str(PurePosixPath(target_path).parent)
        rc = runner.exec(
            self._root_shell(
                f"mkdir -p {shlex.quote(parent)} && mv {stage} {shlex.quote(target_path)} "
                f"&& chmod 644 {shlex.quote(target_path)}"
            ),
            use_pty=False,
        )
        if rc != 0:
            raise RuntimeError(f"Failed to place uploaded file at {target_path} (rc={rc})")

    async def upload_dir(self, source_dir: Path | str, target_dir: str):
        await asyncio.to_thread(self._upload_dir_sync, str(source_dir), str(target_dir))

    def _upload_dir_sync(self, source_dir: str, target_dir: str) -> None:
        runner = self._runner
        stage = f"/tmp/.hb-in-{uuid.uuid4().hex}"
        runner.copy_to(source_dir, stage)
        quoted_target = shlex.quote(target_dir)
        rc = runner.exec(
            self._root_shell(
                f"mkdir -p {quoted_target} && cp -a {stage}/. {quoted_target}/ "
                f"&& rm -rf {stage} && chmod -R 777 {quoted_target}"
            ),
            use_pty=False,
        )
        if rc != 0:
            raise RuntimeError(f"Failed to place uploaded dir at {target_dir} (rc={rc})")

    async def download_file(self, source_path: str, target_path: Path | str):
        await asyncio.to_thread(self._download_file_sync, str(source_path), str(target_path))

    def _download_file_sync(self, source_path: str, target_path: str) -> None:
        runner = self._runner
        stage = f"/tmp/.hb-out-{uuid.uuid4().hex}"
        rc = runner.exec(
            self._root_shell(
                f"cp -a {shlex.quote(source_path)} {stage} && chmod 644 {stage}"
            ),
            use_pty=False,
        )
        if rc != 0:
            raise FileNotFoundError(f"Failed to stage {source_path} for download (rc={rc})")
        try:
            runner.copy_from(stage, target_path)
        finally:
            runner.exec(f"rm -f {stage}", use_pty=False)

    async def download_dir(self, source_dir: str, target_dir: Path | str):
        await asyncio.to_thread(self._download_dir_sync, str(source_dir), str(target_dir))

    def _download_dir_sync(self, source_dir: str, target_dir: str) -> None:
        runner = self._runner
        stage = f"/tmp/.hb-out-{uuid.uuid4().hex}"
        rc = runner.exec(
            self._root_shell(
                f"rm -rf {stage} && cp -a {shlex.quote(source_dir)} {stage} "
                f"&& chmod -R 755 {stage}"
            ),
            use_pty=False,
        )
        if rc != 0:
            raise FileNotFoundError(f"Failed to stage {source_dir} for download (rc={rc})")
        try:
            with tempfile.TemporaryDirectory() as tmp:
                local_stage = Path(tmp) / "stage"
                runner.copy_from(stage, str(local_stage))
                target = Path(target_dir)
                target.mkdir(parents=True, exist_ok=True)
                for item in local_stage.iterdir():
                    dest = target / item.name
                    if item.is_dir():
                        shutil.copytree(item, dest, dirs_exist_ok=True)
                    else:
                        shutil.copy2(item, dest)
        finally:
            runner.exec(f"rm -rf {stage}", use_pty=False)


def _is_verifier_invocation(command: str) -> bool:
    """True for the Verifier's test-script invocation, false for everything else.

    Harbor's Verifier runs ``bash /tests/test.sh > /logs/verifier/... 2>&1``.
    The ``chmod +x /tests/test.sh`` that precedes it references the script but
    never the verifier dir, so requiring both substrings discriminates cleanly.
    """
    return _TESTS_SCRIPT_PATH in command and _VERIFIER_DIR in command


__all__ = ["GymAnythingEnvironment", "GA_ENV_CONFIG_FILENAME"]
