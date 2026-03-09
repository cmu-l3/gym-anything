from __future__ import annotations

import shlex
from pathlib import Path
from typing import Dict, Optional

from .utils.yaml import load_structured_file


def _parse_env_file(path: Path) -> Dict[str, str]:
    env: Dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        if "=" not in line:
            raise ValueError(f"Invalid env line in {path}: {raw_line!r}")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            raise ValueError(f"Invalid env key in {path}: {raw_line!r}")
        if value and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        env[key] = value
    return env


def load_secret_env(ref: str, base_dir: Optional[Path] = None) -> Dict[str, str]:
    path = Path(ref)
    if not path.is_absolute():
        base = base_dir or Path.cwd()
        path = (base / path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"secrets_ref path not found: {path}")

    if path.suffix.lower() in {".json", ".yaml", ".yml"}:
        data = load_structured_file(path)
        if not isinstance(data, dict):
            raise ValueError(f"Secrets file must be a mapping: {path}")
        return {str(key): str(value) for key, value in data.items()}
    return _parse_env_file(path)


def render_posix_env_prefix(env: Dict[str, str]) -> str:
    if not env:
        return ""
    parts = [f"{key}={shlex.quote(str(value))}" for key, value in env.items()]
    return " ".join(parts)


def wrap_posix_command_with_env(cmd: str, env: Dict[str, str], *, export: bool = False) -> str:
    if not env:
        return cmd
    if export:
        exports = "; ".join(f"export {key}={shlex.quote(str(value))}" for key, value in env.items())
        return f"{exports}; {cmd}"
    prefix = render_posix_env_prefix(env)
    return f"env {prefix} {cmd}"


def wrap_powershell_command_with_env(cmd: str, env: Dict[str, str]) -> str:
    if not env:
        return cmd
    assignments = []
    for key, value in env.items():
        escaped = str(value).replace("'", "''")
        assignments.append(f"$env:{key}='{escaped}'")
    return "; ".join(assignments + [cmd])


__all__ = [
    "load_secret_env",
    "render_posix_env_prefix",
    "wrap_posix_command_with_env",
    "wrap_powershell_command_with_env",
]
