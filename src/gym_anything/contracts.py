from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict, Literal, Optional, Tuple


PlatformFamily = Literal["linux", "windows", "android", "unknown"]


@dataclass(frozen=True)
class RunnerRuntimeInfo:
    """Stable runtime metadata exposed by runners to higher layers."""

    platform_family: PlatformFamily
    container_name: Optional[str] = None
    instance_name: Optional[str] = None
    vnc_port: Optional[int] = None
    vnc_password: Optional[str] = None
    ssh_port: Optional[int] = None
    ssh_user: Optional[str] = None
    ssh_password: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class SessionInfo:
    """Stable session metadata available after reset()."""

    env_id: str
    task_id: Optional[str]
    runner_name: str
    platform_family: PlatformFamily
    artifacts_dir: Optional[str] = None
    resolution: Optional[Tuple[int, int]] = None
    fps: Optional[int] = None
    network_enabled: Optional[bool] = None
    systemd_enabled: bool = False
    container_name: Optional[str] = None
    instance_name: Optional[str] = None
    vnc_port: Optional[int] = None
    vnc_url: Optional[str] = None
    vnc_password: Optional[str] = None
    ssh_port: Optional[int] = None
    ssh_user: Optional[str] = None
    ssh_password: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        data = asdict(self)
        if self.resolution is not None:
            data["resolution"] = list(self.resolution)
        return data

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "SessionInfo":
        resolution = data.get("resolution")
        resolved_resolution: Optional[Tuple[int, int]] = None
        if isinstance(resolution, (list, tuple)) and len(resolution) == 2:
            try:
                resolved_resolution = (int(resolution[0]), int(resolution[1]))
            except (TypeError, ValueError):
                resolved_resolution = None

        platform_family = data.get("platform_family")
        if platform_family not in {"linux", "windows", "android", "unknown"}:
            platform_family = "unknown"

        return cls(
            env_id=str(data.get("env_id", "")),
            task_id=data.get("task_id"),
            runner_name=str(data.get("runner_name", "")),
            platform_family=platform_family,
            artifacts_dir=data.get("artifacts_dir"),
            resolution=resolved_resolution,
            fps=data.get("fps"),
            network_enabled=data.get("network_enabled"),
            systemd_enabled=bool(data.get("systemd_enabled", False)),
            container_name=data.get("container_name"),
            instance_name=data.get("instance_name"),
            vnc_port=data.get("vnc_port"),
            vnc_url=data.get("vnc_url"),
            vnc_password=data.get("vnc_password"),
            ssh_port=data.get("ssh_port"),
            ssh_user=data.get("ssh_user"),
            ssh_password=data.get("ssh_password"),
        )


__all__ = ["PlatformFamily", "RunnerRuntimeInfo", "SessionInfo"]
