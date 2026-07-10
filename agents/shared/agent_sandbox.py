"""Isolated sandbox for running external CLI coding agents.

The coding CLI (Claude Code, Codex, ...) must run in a lightweight, isolated
container that has no filesystem or process access to the task env VM, and can
only reach the host action gateway plus the model provider API. This module
provides one backend-agnostic protocol (``AgentSandbox``) so the agent code
never names a container technology, exactly like the env code talks to
``BaseRunner``.

Backends are auto-selected the way env runners are (an explicit
``GYM_ANYTHING_AGENT_SANDBOX`` override, then detect what the machine has):

- ``ApptainerSandbox`` — rootless, no daemon. Primary on clusters (Babel).
- ``DockerSandbox`` — daemon machines; also gets bridge network isolation.

There is deliberately no no-isolation fallback: running a coding CLI with
permission-bypass flags outside a sandbox is never acceptable, so if neither
backend is available we raise.

Isolation, stated honestly:
- File isolation: always. The backend gives the container its own root fs, and
  the env is a separate VM, so the agent has no filesystem path into the env.
- Process isolation: always (PID namespace: apptainer instances, docker).
- Network: docker's bridge additionally blocks any route to the env's ports.
  Rootless apptainer shares the host network namespace (unavoidable rootless,
  and outbound is needed for the API + gateway), so the env-port guarantee
  there softens to "the agent is given only the gateway and never the env's
  SSH/VNC host, port, or password."
"""

from __future__ import annotations

import hashlib
import logging
import os
import shutil
import subprocess
import tempfile
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class SandboxSpec:
    """Backend-agnostic description of the scratch image to run the CLI in."""

    name: str          # cache key, e.g. "claude" / "codex"
    base_image: str    # docker ref, e.g. "node:22-slim"
    install: str       # shell that installs the CLI on top of the common base
    act_script: str    # the `act` gateway-wrapper script, copied to /usr/local/bin

    def digest(self) -> str:
        raw = f"{self.base_image}\n{self.install}\n{self.act_script}".encode()
        return hashlib.sha256(raw).hexdigest()[:12]


# Common packages layered on top of the base image, shared by all backends.
_COMMON_INSTALL = (
    "apt-get update && apt-get install -y --no-install-recommends "
    "curl ca-certificates python3 procps && rm -rf /var/lib/apt/lists/*"
)


def _run(args: list[str], timeout: int | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)


class AgentSandbox(ABC):
    """One isolated container run: build the image, start it, exec the CLI, stop.

    The CLI's writable scratch (config, ``obs/`` screenshots) lives under the
    bind-mounted ``/logs`` so it is host-visible and sidesteps rootless
    permission issues on the container's own root fs.
    """

    #: Address the gateway should bind to for this backend.
    gateway_bind_host: str = "127.0.0.1"

    def __init__(self, spec: SandboxSpec, logs_dir: Path):
        self.spec = spec
        self.logs_dir = Path(logs_dir)

    def gateway_url(self, port: int) -> str:
        """URL the container uses to reach the host gateway."""
        return f"http://{self.gateway_bind_host}:{port}/act"

    @abstractmethod
    def build(self) -> None:
        """Build/cache the scratch image (idempotent)."""

    @abstractmethod
    def start(self, gateway_port: int, gateway_token: str, container_env: dict[str, str]) -> None:
        """Start the container with the gateway coordinates and API-key env."""

    @abstractmethod
    def exec(self, command: str, timeout_sec: int) -> subprocess.CompletedProcess:
        """Run the CLI invocation inside the container, teeing stdout to /logs."""

    @abstractmethod
    def stop(self) -> None:
        """Tear the container down (best effort)."""

    # Shared helpers -------------------------------------------------------

    def _prepare_logs(self) -> None:
        (self.logs_dir / "work").mkdir(parents=True, exist_ok=True)
        (self.logs_dir / "home").mkdir(parents=True, exist_ok=True)

    def _full_env(self, gateway_port: int, gateway_token: str, container_env: dict[str, str]) -> dict[str, str]:
        env = {
            "HOME": "/logs/home",
            "GATEWAY_URL": self.gateway_url(gateway_port),
            "GATEWAY_TOKEN": gateway_token,
        }
        env.update({k: v for k, v in container_env.items() if v})
        return env


class DockerSandbox(AgentSandbox):
    gateway_bind_host = "0.0.0.0"  # bridge network reaches the host via host-gateway

    def __init__(self, spec: SandboxSpec, logs_dir: Path):
        super().__init__(spec, logs_dir)
        self.image_tag = f"gym-anything-agent-sandbox-{spec.name}:{spec.digest()}"
        self.container_name = f"gym-agent-{spec.name}-{os.urandom(4).hex()}"
        self._env: dict[str, str] = {}

    def gateway_url(self, port: int) -> str:
        return f"http://host.docker.internal:{port}/act"

    def dockerfile(self) -> str:
        return (
            f"FROM {self.spec.base_image}\n"
            f"RUN {_COMMON_INSTALL}\n"
            f"RUN {self.spec.install}\n"
            "COPY act /usr/local/bin/act\n"
            "RUN chmod +x /usr/local/bin/act\n"
            "RUN mkdir -p /logs/work /logs/home\n"
            "WORKDIR /logs/work\n"
        )

    def build(self) -> None:
        if _run(["docker", "image", "inspect", self.image_tag]).returncode == 0:
            return
        with tempfile.TemporaryDirectory() as build_dir:
            path = Path(build_dir)
            (path / "act").write_text(self.spec.act_script)
            (path / "Dockerfile").write_text(self.dockerfile())
            logger.info("Building docker agent sandbox %s", self.image_tag)
            result = _run(["docker", "build", "-t", self.image_tag, str(path)], timeout=1800)
            if result.returncode != 0:
                raise RuntimeError(f"docker build failed:\n{result.stderr}")

    def start(self, gateway_port: int, gateway_token: str, container_env: dict[str, str]) -> None:
        self._prepare_logs()
        self._env = self._full_env(gateway_port, gateway_token, container_env)
        env_args: list[str] = []
        for key, value in self._env.items():
            env_args += ["-e", f"{key}={value}"]
        args = [
            "docker", "run", "-d", "--rm", "--name", self.container_name,
            "--add-host", "host.docker.internal:host-gateway",
            "-v", f"{self.logs_dir}:/logs",
            *env_args,
            self.image_tag, "sleep", "infinity",
        ]
        result = _run(args, timeout=120)
        if result.returncode != 0:
            raise RuntimeError(f"docker run failed:\n{result.stderr}")

    def exec(self, command: str, timeout_sec: int) -> subprocess.CompletedProcess:
        wrapped = f"set -o pipefail; ({command}) 2>&1 | tee /logs/cli_stdout.txt"
        return _run(
            ["docker", "exec", "-w", "/logs/work", self.container_name, "bash", "-lc", wrapped],
            timeout=timeout_sec,
        )

    def stop(self) -> None:
        _run(["docker", "rm", "-f", self.container_name], timeout=60)


class ApptainerSandbox(AgentSandbox):
    gateway_bind_host = "127.0.0.1"  # shares host net; reaches the host on loopback

    _CACHE_DIR = Path.home() / ".cache" / "gym-anything" / "agent-sandbox"

    def __init__(self, spec: SandboxSpec, logs_dir: Path):
        super().__init__(spec, logs_dir)
        self.sif_path = self._CACHE_DIR / f"{spec.name}-{spec.digest()}.sif"
        self.instance_name = f"gym-agent-{spec.name}-{os.urandom(4).hex()}"
        self._env_file: Path | None = None

    def definition(self) -> str:
        return (
            "Bootstrap: docker\n"
            f"From: {self.spec.base_image}\n"
            "\n%files\n"
            "    act /usr/local/bin/act\n"
            "\n%post\n"
            f"    {_COMMON_INSTALL}\n"
            f"    {self.spec.install}\n"
            "    chmod +x /usr/local/bin/act\n"
            "    mkdir -p /logs/work /logs/home\n"
        )

    def build(self) -> None:
        if self.sif_path.exists():
            return
        self.sif_path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as build_dir:
            path = Path(build_dir)
            (path / "act").write_text(self.spec.act_script)
            def_path = path / "sandbox.def"
            def_path.write_text(self.definition())
            logger.info("Building apptainer agent sandbox %s", self.sif_path)
            # --fakeroot lets the %post apt/npm installs run rootless (same as
            # the env ApptainerDirectRunner build path).
            result = _run(
                ["apptainer", "build", "--fakeroot", str(self.sif_path), str(def_path)],
                timeout=1800,
            )
            if result.returncode != 0:
                raise RuntimeError(f"apptainer build failed:\n{result.stderr}")

    def start(self, gateway_port: int, gateway_token: str, container_env: dict[str, str]) -> None:
        self._prepare_logs()
        env = self._full_env(gateway_port, gateway_token, container_env)
        self._env_file = self.logs_dir / "sandbox.env"
        self._env_file.write_text("".join(f"{k}={v}\n" for k, v in env.items()))
        args = [
            "apptainer", "instance", "start",
            "--contain", "--cleanenv", "--writable-tmpfs",
            "--bind", f"{self.logs_dir}:/logs",
            str(self.sif_path), self.instance_name,
        ]
        result = _run(args, timeout=120)
        if result.returncode != 0:
            raise RuntimeError(f"apptainer instance start failed:\n{result.stderr}")

    def exec(self, command: str, timeout_sec: int) -> subprocess.CompletedProcess:
        wrapped = f"set -o pipefail; ({command}) 2>&1 | tee /logs/cli_stdout.txt"
        args = [
            "apptainer", "exec", "--pwd", "/logs/work",
            "--env-file", str(self._env_file),
            f"instance://{self.instance_name}", "bash", "-lc", wrapped,
        ]
        return _run(args, timeout=timeout_sec)

    def stop(self) -> None:
        _run(["apptainer", "instance", "stop", self.instance_name], timeout=60)


def _apptainer_available() -> bool:
    return shutil.which("apptainer") is not None


def _docker_available() -> bool:
    return shutil.which("docker") is not None


def select_sandbox(spec: SandboxSpec, logs_dir: Path) -> AgentSandbox:
    """Pick a sandbox backend: explicit override, else detect. No fallback.

    Precedence mirrors env runner selection: ``GYM_ANYTHING_AGENT_SANDBOX``
    wins, then apptainer (rootless), then docker.
    """
    choice = os.environ.get("GYM_ANYTHING_AGENT_SANDBOX", "").strip().lower()
    if choice == "apptainer":
        return ApptainerSandbox(spec, logs_dir)
    if choice == "docker":
        return DockerSandbox(spec, logs_dir)
    if choice:
        raise ValueError(
            f"Unknown GYM_ANYTHING_AGENT_SANDBOX={choice!r}; use 'apptainer' or 'docker'"
        )

    if _apptainer_available():
        return ApptainerSandbox(spec, logs_dir)
    if _docker_available():
        return DockerSandbox(spec, logs_dir)
    raise RuntimeError(
        "No agent sandbox backend available: need apptainer (rootless) or docker. "
        "Refusing to run a coding CLI without isolation."
    )
