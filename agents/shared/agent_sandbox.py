"""Isolated sandbox for running external CLI coding agents.

The coding CLI (Claude Code, Codex, ...) must run in a lightweight, isolated
container that has no filesystem or process access to the task env VM, and can
only reach the host action gateway plus the model provider API. This module
provides one backend-agnostic protocol (``AgentSandbox``) so the agent code
never names a container technology, exactly like the env code talks to
``BaseRunner``.

Backends are auto-selected the way env runners are (an explicit
``GYM_ANYTHING_AGENT_SANDBOX`` override, then detect what the machine has):

- ``ApptainerSandbox`` — rootless, no daemon. Primary on HPC clusters.
- ``DockerSandbox`` — daemon machines; uses a bridge network.

There is deliberately no no-isolation fallback: running a coding CLI with
permission-bypass flags outside a sandbox is never acceptable, so if neither
backend is available we raise.

Isolation, stated honestly:
- File isolation: always. The backend gives the container its own root fs, and
  the env is a separate VM, so the agent has no filesystem path into the env.
- Process isolation: always (PID namespace: apptainer instances, docker).
- Network: not an egress security boundary. Docker uses a bridge plus a route
  to the host gateway; rootless apptainer shares the host network namespace.
  Both need the action gateway and model-provider API. The harness withholds
  task-environment addresses and credentials, but does not enforce a network
  destination allowlist.
"""

from __future__ import annotations

import hashlib
import logging
import os
import shlex
import shutil
import subprocess
import tempfile
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)

_IMAGE_RECIPE_VERSION = "2"


@dataclass(frozen=True)
class SandboxSpec:
    """Backend-agnostic description of the scratch image to run the CLI in."""

    name: str          # cache key, e.g. "claude" / "codex"
    base_image: str    # docker ref, e.g. "node:22-slim"
    install: str       # shell that installs the CLI on top of the common base
    act_script: str    # the `act` gateway-wrapper script, copied to /usr/local/bin

    def digest(self) -> str:
        raw = (
            f"{_IMAGE_RECIPE_VERSION}\n{self.base_image}\n"
            f"{self.install}\n{self.act_script}"
        ).encode()
        return hashlib.sha256(raw).hexdigest()[:12]


# Common packages layered on top of the base image, shared by all backends.
_COMMON_INSTALL = (
    "apt-get update && apt-get install -y --no-install-recommends "
    "curl ca-certificates python3 procps && rm -rf /var/lib/apt/lists/*"
)


def _run(args: list[str], timeout: int | None = None, cwd: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False, cwd=cwd)


class AgentSandbox(ABC):
    """One isolated container run: build the image, start it, exec the CLI, stop.

    Episode artifacts live under the bind-mounted ``/logs``. Private runtime
    state, including copied credentials, lives in a mode-0700 host scratch
    directory mounted at ``/gym-agent-private``. The scratch directory is
    removed when the container stops and is never part of the episode logs.
    """

    #: Address the gateway should bind to for this backend.
    gateway_bind_host: str = "127.0.0.1"

    def __init__(self, spec: SandboxSpec, logs_dir: Path):
        self.spec = spec
        self.logs_dir = Path(logs_dir)
        self._private_dir: Path | None = None

    def gateway_url(self, port: int) -> str:
        """URL the container uses to reach the host gateway."""
        return f"http://{self.gateway_bind_host}:{port}/act"

    @abstractmethod
    def build(self) -> None:
        """Build/cache the scratch image (idempotent)."""

    @abstractmethod
    def start(self, gateway_port: int, gateway_token: str, container_env: dict[str, str]) -> None:
        """Start the container with the gateway coordinates and runtime env."""

    @abstractmethod
    def exec(self, command: str, timeout_sec: int) -> subprocess.CompletedProcess:
        """Run the CLI invocation inside the container, teeing stdout to /logs."""

    @abstractmethod
    def copy_file(self, source: Path, destination: str, mode: int = 0o600) -> None:
        """Copy one host file into the running container's private filesystem."""

    @abstractmethod
    def copy_directory_from(self, source: str, destination: Path) -> None:
        """Copy one container directory into the episode artifact directory."""

    @abstractmethod
    def stop(self) -> None:
        """Tear the container down (best effort)."""

    # Shared helpers -------------------------------------------------------

    def _prepare_logs(self) -> None:
        (self.logs_dir / "work").mkdir(parents=True, exist_ok=True)
        (self.logs_dir / "home").mkdir(parents=True, exist_ok=True)

    def _prepare_private_dir(self) -> Path:
        if self._private_dir is None:
            self._private_dir = Path(
                tempfile.mkdtemp(prefix=f"gym-agent-{self.spec.name}-private-")
            )
            self._private_dir.chmod(0o700)
        return self._private_dir

    def _cleanup_private_dir(self) -> None:
        private_dir = self._private_dir
        self._private_dir = None
        if private_dir is None:
            return
        try:
            shutil.rmtree(private_dir)
        except OSError:
            logger.warning("Failed to remove private sandbox directory %s", private_dir)

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
            "RUN mkdir -p /logs/work /logs/home /gym-agent-private "
            "&& chmod 1777 /gym-agent-private\n"
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
        private_dir = self._prepare_private_dir()
        self._env = self._full_env(gateway_port, gateway_token, container_env)
        env_args: list[str] = []
        for key, value in self._env.items():
            env_args += ["-e", f"{key}={value}"]
        args = [
            "docker", "run", "-d", "--rm", "--name", self.container_name,
            "--add-host", "host.docker.internal:host-gateway",
            "-v", f"{self.logs_dir}:/logs",
            "-v", f"{private_dir}:/gym-agent-private",
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

    def copy_file(self, source: Path, destination: str, mode: int = 0o600) -> None:
        parent = str(Path(destination).parent)
        prepare = _run(
            [
                "docker", "exec", self.container_name, "sh", "-c",
                f"umask 077; mkdir -p {shlex.quote(parent)}",
            ],
            timeout=60,
        )
        if prepare.returncode != 0:
            raise RuntimeError(f"docker destination setup failed:\n{prepare.stderr}")
        copied = _run(
            ["docker", "cp", str(source), f"{self.container_name}:{destination}"],
            timeout=60,
        )
        if copied.returncode != 0:
            raise RuntimeError(f"docker copy failed:\n{copied.stderr}")
        secured = _run(
            ["docker", "exec", self.container_name, "chmod", f"{mode:o}", destination],
            timeout=60,
        )
        if secured.returncode != 0:
            raise RuntimeError(f"docker chmod failed:\n{secured.stderr}")

    def copy_directory_from(self, source: str, destination: Path) -> None:
        destination.mkdir(parents=True, exist_ok=True)
        copied = _run(
            [
                "docker", "cp", f"{self.container_name}:{source.rstrip('/')}/.",
                str(destination),
            ],
            timeout=60,
        )
        if copied.returncode != 0:
            raise RuntimeError(f"docker artifact copy failed:\n{copied.stderr}")

    def stop(self) -> None:
        try:
            _run(["docker", "rm", "-f", self.container_name], timeout=60)
        finally:
            self._cleanup_private_dir()


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
            "    mkdir -p /logs/work /logs/home /gym-agent-private\n"
            "    chmod 1777 /gym-agent-private\n"
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
            # the env ApptainerDirectRunner build path). Run from the build dir
            # so the def's %files source (`act`) resolves relative to it.
            result = _run(
                ["apptainer", "build", "--fakeroot", str(self.sif_path), "sandbox.def"],
                timeout=1800,
                cwd=str(path),
            )
            if result.returncode != 0:
                raise RuntimeError(f"apptainer build failed:\n{result.stderr}")

    def start(self, gateway_port: int, gateway_token: str, container_env: dict[str, str]) -> None:
        self._prepare_logs()
        private_dir = self._prepare_private_dir()
        env = self._full_env(gateway_port, gateway_token, container_env)
        self._env_file = self.logs_dir / "sandbox.env"
        self._env_file.write_text("".join(f"{k}={v}\n" for k, v in env.items()))
        args = [
            "apptainer", "instance", "start",
            "--contain", "--cleanenv", "--writable-tmpfs",
            "--bind", f"{self.logs_dir}:/logs",
            "--bind", f"{private_dir}:/gym-agent-private",
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

    def copy_file(self, source: Path, destination: str, mode: int = 0o600) -> None:
        parent = str(Path(destination).parent)
        command = (
            f"umask 077; mkdir -p {shlex.quote(parent)}; "
            f"cat > {shlex.quote(destination)}; chmod {mode:o} {shlex.quote(destination)}"
        )
        result = subprocess.run(
            [
                "apptainer", "exec", f"instance://{self.instance_name}",
                "sh", "-c", command,
            ],
            input=source.read_bytes(),
            capture_output=True,
            timeout=60,
            check=False,
        )
        if result.returncode != 0:
            stderr = result.stderr.decode(errors="replace")
            raise RuntimeError(f"apptainer copy failed:\n{stderr}")

    def copy_directory_from(self, source: str, destination: Path) -> None:
        logs_root = self.logs_dir.resolve()
        destination = destination.resolve()
        try:
            relative = destination.relative_to(logs_root)
        except ValueError as exc:
            raise ValueError("sandbox artifacts must stay under the logs directory") from exc
        destination.mkdir(parents=True, exist_ok=True)
        container_destination = f"/logs/{relative.as_posix()}"
        command = (
            f"cp -a {shlex.quote(source.rstrip('/') + '/.')} "
            f"{shlex.quote(container_destination + '/')}"
        )
        result = _run(
            [
                "apptainer", "exec", f"instance://{self.instance_name}",
                "sh", "-c", command,
            ],
            timeout=60,
        )
        if result.returncode != 0:
            raise RuntimeError(f"apptainer artifact copy failed:\n{result.stderr}")

    def stop(self) -> None:
        try:
            _run(["apptainer", "instance", "stop", self.instance_name], timeout=60)
        finally:
            self._cleanup_private_dir()


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
