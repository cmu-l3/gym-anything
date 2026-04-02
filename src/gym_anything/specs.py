from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Literal, Optional, Tuple, Union


ObservationType = Literal[
    "rgb_screen",
    "ui_tree",
    "audio_waveform",
    "cli_stdout",
]

ActionType = Literal[
    "mouse",
    "keyboard",
    "voice",
    "api_call",
]


@dataclass
class ObservationSpec:
    type: ObservationType
    fps: Optional[int] = None
    resolution: Optional[Tuple[int, int]] = None
    sample_rate: Optional[int] = None
    channels: Optional[int] = None
    inline: bool = False
    chunk_duration_ms: Optional[int] = None  # for audio waveform capture per step


@dataclass
class ActionSpec:
    type: ActionType
    events: Optional[List[str]] = None
    encoding: Optional[str] = None


@dataclass
class RuntimeResources:
    cpu: Optional[float] = None  # logical cores
    mem_gb: Optional[int] = None
    gpu: Optional[int] = None
    net: Optional[bool] = None


@dataclass
class MountSpec:
    target: str
    source: str
    mode: Literal["ro", "rw"] = "ro"


@dataclass
class ApptainerSpec:
    """Configuration for Apptainer-backed environments."""

    sif: Optional[str] = None  # Path to pre-built SIF
    definition: Optional[str] = None  # apptainer definition file
    image: Optional[str] = None  # remote image reference (e.g., docker://)
    cache_dir: Optional[str] = None  # location to store built SIFs
    binds: List[str] = field(default_factory=list)  # additional bind mounts (host:container[:opts])
    overlays: List[str] = field(default_factory=list)
    fakeroot: bool = False
    contain: bool = True
    contain_all: bool = False
    writable_tmpfs: bool = True
    enable_gpu: bool = False
    env: Dict[str, str] = field(default_factory=dict)
    workdir: Optional[str] = None
    extra_start_args: List[str] = field(default_factory=list)
    extra_exec_args: List[str] = field(default_factory=list)


@dataclass
class UserPermissions:
    """Detailed user permissions and access controls."""
    # Basic access
    sudo: bool = False  # Can use sudo
    sudo_nopasswd: bool = False  # Sudo without password
    shell: str = "/bin/bash"  # Default shell
    
    # Group memberships
    groups: List[str] = field(default_factory=list)  # Additional groups (e.g., ["docker", "audio", "video"])
    primary_group: Optional[str] = None  # Primary group (defaults to username)
    
    # File system permissions
    home_dir: Optional[str] = None  # Custom home directory path (defaults to /home/{username})
    home_permissions: str = "755"  # Home directory permissions
    create_home: bool = True  # Whether to create home directory
    
    # System access
    login_shell: bool = True  # Whether user can login
    system_user: bool = False  # Whether this is a system user (uid < 1000)
    
    # Network and resource limits
    network_access: bool = True  # Whether user can access network
    max_processes: Optional[int] = None  # Maximum number of processes
    max_memory: Optional[str] = None  # Memory limit (e.g., "1G")
    
    # Environment variables
    env_vars: Dict[str, str] = field(default_factory=dict)  # Custom environment variables


@dataclass 
class UserAccount:
    name: str
    password: Optional[str] = None
    uid: Optional[int] = None  # User ID (auto-assigned if None)
    gid: Optional[int] = None  # Group ID (defaults to uid if None)
    role: Optional[str] = None  # High-level role description (e.g., "admin", "developer", "guest")
    permissions: UserPermissions = field(default_factory=UserPermissions)
    
    # Convenience methods for common permission patterns
    @classmethod
    def admin_user(cls, name: str, password: Optional[str] = None) -> "UserAccount":
        """Create an admin user with full sudo access."""
        return cls(
            name=name,
            password=password,
            role="admin",
            permissions=UserPermissions(
                sudo=True,
                sudo_nopasswd=True,
                groups=["sudo", "docker", "audio", "video", "input"],
                shell="/bin/bash"
            )
        )
    
    @classmethod
    def developer_user(cls, name: str, password: Optional[str] = None) -> "UserAccount":
        """Create a developer user with common development permissions."""
        return cls(
            name=name,
            password=password,
            role="developer", 
            permissions=UserPermissions(
                sudo=True,
                sudo_nopasswd=False,
                groups=["docker", "audio", "video", "input"],
                shell="/bin/bash"
            )
        )
    
    @classmethod
    def guest_user(cls, name: str, password: Optional[str] = None) -> "UserAccount":
        """Create a guest user with limited permissions."""
        return cls(
            name=name,
            password=password,
            role="guest",
            permissions=UserPermissions(
                sudo=False,
                groups=["audio", "video"],
                shell="/bin/bash",
                max_processes=50
            )
        )
    
    @classmethod
    def service_user(cls, name: str) -> "UserAccount":
        """Create a system service user."""
        return cls(
            name=name,
            password=None,
            role="service",
            permissions=UserPermissions(
                sudo=False,
                system_user=True,
                login_shell=False,
                create_home=False,
                shell="/bin/false"
            )
        )


@dataclass
class RecordingSpec:
    enable: bool = True
    output_dir: str = "./artifacts"
    video_fps: int = 10
    video_resolution: Optional[Tuple[int, int]] = None
    video_codec: str = "libx264"
    video_crf: int = 23
    audio_rate: int = 16000
    audio_channels: int = 1
    audio_codec: str = "aac"
    force_audio_track: bool = False


@dataclass
class VNCSpec:
    enable: bool = False
    host_port: int = 5901
    container_port: int = 5901  # Port inside container (5901 for Linux/VNC, 8006 for dockurr/windows)
    password: Optional[str] = None
    view_only: bool = False
    fallback_only: bool = False  # If True, VNC is only used as fallback (e.g., Android uses ADB primarily)
    note: Optional[str] = None  # Optional note about VNC usage


@dataclass
class ADBSpec:
    """ADB configuration for Android environments."""
    host_port: int = -1  # -1 means auto-assign
    guest_port: int = 5555
    timeout: int = 180
    note: Optional[str] = None


@dataclass
class AVDSpec:
    """AVD configuration for Android emulator environments."""
    api_level: int = 35  # Android API level (35 = Android 15)
    variant: str = "google_apis_playstore"  # System image variant
    arch: str = "x86_64"  # Architecture
    device: str = "pixel_6"  # Device profile


@dataclass
class SSHSpec:
    """SSH configuration for remote command execution."""
    user: str = "root"
    password: Optional[str] = None
    key_file: Optional[str] = None
    port: int = 22
    shell: str = "bash"  # Default shell (bash for Linux, powershell for Windows)
    note: Optional[str] = None


@dataclass
class SecuritySpec:
    user: str = "1000:1000"  # uid:gid in container
    cap_drop: List[str] = field(default_factory=lambda: ["ALL"])
    cap_add: List[str] = field(default_factory=list)  # Capabilities to add (e.g., ["NET_ADMIN"])
    devices: List[str] = field(default_factory=list)  # Device mappings (e.g., ["/dev/kvm", "/dev/net/tun"])
    seccomp_profile: Optional[str] = None
    network_allowlist: Optional[List[str]] = None
    secrets_ref: Optional[str] = None
    privileged: bool = False
    use_systemd: bool = False
    mount_cgroups: bool = False
    cgroupns_host: bool = False
    tmpfs_run: bool = False
    stop_timeout: Optional[int] = None  # Container stop timeout in seconds
    runtime: Optional[str] = None  # Runtime to use for the container (e.g., "sysbox-runc")
    resolved_env: Dict[str, str] = field(default_factory=dict, repr=False)
    ignored_fields: Dict[str, Any] = field(default_factory=dict, repr=False)

@dataclass
class EnvSpec:
    # Metadata
    id: str
    version: str = "1.0"
    description: Optional[str] = None
    category: Optional[List[str]] = None
    authors: Optional[List[str]] = None
    licence: Optional[str] = None
    upstream_url: Optional[str] = None
    tags: Optional[List[str]] = None

    # Runtime
    base: Optional[str] = None  # preset base id (e.g., "x11-lite", "ubuntu-gnome")
    image: Optional[str] = None
    dockerfile: Optional[str] = None
    entrypoint: Optional[str] = None
    apptainer: Optional[ApptainerSpec] = None
    resources: RuntimeResources = field(default_factory=RuntimeResources)
    mounts: List[MountSpec] = field(default_factory=list)
    apks: List[str] = field(default_factory=list)  # APK paths to install (Android only)
    user_accounts: List[UserAccount] = field(default_factory=list)

    # Interfaces
    observation: List[ObservationSpec] = field(default_factory=list)
    action: List[ActionSpec] = field(default_factory=list)
    synchronous: bool = True
    step_cycle_ms: Optional[int] = 100

    # Reset / Seeding
    reset_script: Optional[str] = None
    deterministic: Optional[bool] = None
    supports_save_restore: Optional[str] = None  # snapshot | none | custom
    save_paths: Optional[List[str]] = None  # paths inside container to include in snapshot

    # Security & Recording
    security: SecuritySpec = field(default_factory=SecuritySpec)
    recording: RecordingSpec = field(default_factory=RecordingSpec)
    vnc: VNCSpec = field(default_factory=VNCSpec)
    ssh: Optional[SSHSpec] = None  # SSH configuration for remote command execution
    adb: Optional[ADBSpec] = None  # ADB configuration for Android environments
    avd: Optional[AVDSpec] = None  # AVD configuration for Android emulator
    diagnostics: bool = False

    # OS type and runner (for platform-specific handling)
    os_type: Optional[str] = None  # "linux", "windows", "android"
    runner: Optional[str] = None  # "docker", "qemu", "qemu_native", "avd", "avd_native", "local"

    # Backends (optional hints)
    display_backend: Optional[str] = None
    input_backend: Optional[str] = None
    audio_backend: Optional[str] = None
    skip_display_audio_bootstrap: bool = False  # Skip X11/PulseAudio setup (for Windows, native displays)

    # Hooks
    hooks: Dict[str, str] = field(default_factory=dict)  # keys: pre_start, post_start, reset

    # Multi-agent (optional)
    multi_agent: Optional[Dict[str, Any]] = None  # {"roles": ["player","adversary"], "turn_based": bool}

    @staticmethod
    def from_dict(d: Dict[str, Any]) -> "EnvSpec":
        # Shallow, robust constructor from a dictionary without external deps
        def _obs(item: Dict[str, Any]) -> ObservationSpec:
            return ObservationSpec(
                type=item["type"],
                fps=item.get("fps"),
                resolution=tuple(item["resolution"]) if item.get("resolution") else None,
                sample_rate=item.get("sample_rate"),
                channels=item.get("channels"),
                inline=item.get("inline", False),
                chunk_duration_ms=item.get("chunk_duration_ms"),
            )

        def _act(item: Dict[str, Any]) -> ActionSpec:
            return ActionSpec(
                type=item["type"],
                events=item.get("events"),
                encoding=item.get("encoding"),
            )

        mounts = [MountSpec(**m) for m in d.get("mounts", [])]
        
        # Handle user accounts with permissions
        users = []
        for u in d.get("user_accounts", []):
            permissions_data = u.get("permissions", {})
            if isinstance(permissions_data, UserPermissions):
                permissions = permissions_data
            else:
                permissions = UserPermissions(**permissions_data)
            user = UserAccount(
                name=u["name"],
                password=u.get("password"),
                uid=u.get("uid"),
                gid=u.get("gid"),
                role=u.get("role"),
                permissions=permissions
            )
            users.append(user)
        obs = [_obs(o) for o in d.get("observation", [])]
        acts = [_act(a) for a in d.get("action", [])]

        resources = RuntimeResources(**d.get("resources", {}))
        security_data = dict(d.get("security", {}))
        ignored_security_fields: Dict[str, Any] = {}
        if "network_allowlist" in security_data:
            ignored_security_fields["network_allowlist"] = security_data.pop("network_allowlist")
        security = SecuritySpec(**security_data)
        if ignored_security_fields:
            security.ignored_fields.update(ignored_security_fields)
        recording = RecordingSpec(**d.get("recording", {}))
        vnc = VNCSpec(**d.get("vnc", {}))
        ssh_cfg = d.get("ssh")
        ssh = SSHSpec(**ssh_cfg) if ssh_cfg else None
        adb_cfg = d.get("adb")
        adb = ADBSpec(**adb_cfg) if adb_cfg else None
        avd_cfg = d.get("avd")
        avd = AVDSpec(**avd_cfg) if avd_cfg else None
        apptainer_cfg = d.get("apptainer")
        apptainer = ApptainerSpec(**apptainer_cfg) if apptainer_cfg else None

        return EnvSpec(
            id=d["id"],
            version=d.get("version", "1.0"),
            description=d.get("description"),
            category=d.get("category"),
            authors=d.get("authors"),
            licence=d.get("licence"),
            upstream_url=d.get("upstream_url"),
            tags=d.get("tags"),
            base=d.get("base"),
            image=d.get("image"),
            dockerfile=d.get("dockerfile"),
            entrypoint=d.get("entrypoint"),
            apptainer=apptainer,
            resources=resources,
            mounts=mounts,
            apks=d.get("apks", []),
            user_accounts=users,
            observation=obs,
            action=acts,
            synchronous=d.get("synchronous", True),
            step_cycle_ms=d.get("step_cycle_ms", 100),
            reset_script=d.get("reset_script"),
            deterministic=d.get("deterministic"),
            supports_save_restore=d.get("supports_save_restore"),
            save_paths=d.get("save_paths"),
            security=security,
            recording=recording,
            vnc=vnc,
            ssh=ssh,
            adb=adb,
            avd=avd,
            diagnostics=d.get("diagnostics", False),
            os_type=d.get("os_type"),
            runner=d.get("runner"),
            display_backend=d.get("display_backend"),
            input_backend=d.get("input_backend"),
            audio_backend=d.get("audio_backend"),
            skip_display_audio_bootstrap=d.get("skip_display_audio_bootstrap", False),
            hooks=d.get("hooks", {}),
            multi_agent=d.get("multi_agent"),
        )

    def merge_overrides(self, overrides: Dict[str, Any]) -> "EnvSpec":
        # Simple shallow merge for common tweaks
        d = self.__dict__.copy()
        for k, v in overrides.items():
            if k in ("resources", "security", "recording") and isinstance(v, dict):
                nested = d[k].__dict__.copy()
                nested.update(v)
                d[k] = type(d[k])(**nested)
            elif k == "apptainer" and isinstance(v, dict):
                base_appt = d.get("apptainer")
                if isinstance(base_appt, ApptainerSpec):
                    merged = base_appt.__dict__.copy()
                    merged.update(v)
                    d[k] = ApptainerSpec(**merged)
                else:
                    d[k] = ApptainerSpec(**v)
            else:
                d[k] = v
        return EnvSpec.from_dict({**d, "id": self.id, "version": self.version})


@dataclass
class TaskSuccessSpec:
    mode: Literal["program", "image_match", "multi"] = "program"
    spec: Dict[str, Any] = field(default_factory=dict)


@dataclass
class TaskInitSpec:
    init_script: Optional[str] = None
    init_pyautogui: Optional[List[Dict[str, Any]]] = None  # PyAutoGUI actions to run after pre_task
    timeout_sec: int = 600
    max_steps: int = 2000
    reward_type: Literal["sparse", "dense", "partial", "rubric", "continuous"] = "sparse"
    reward_shaping: Optional[str] = None


@dataclass
class TaskHooks:
    pre_task: Optional[str] = None
    post_task: Optional[str] = None
    pre_task_timeout: int = 600  # Timeout in seconds for pre_task hook (default 10 min)


@dataclass
class TaskSpec:
    # Metadata
    id: str
    env_id: Optional[str] = None
    version: str = "1.0"
    description: Optional[str] = None
    name: Optional[str] = None
    difficulty: Optional[Literal["easy", "medium", "hard"]] = None
    natural_language: Optional[Union[str, Dict[str, Any]]] = None
    deps: Optional[List[str]] = None
    tags: Optional[List[str]] = None

    # Init
    init: TaskInitSpec = field(default_factory=TaskInitSpec)
    hooks: TaskHooks = field(default_factory=TaskHooks)

    # Success
    success: TaskSuccessSpec = field(default_factory=TaskSuccessSpec)

    metadata: Dict[str, Any] = field(default_factory=dict)
    extras: Dict[str, Any] = field(default_factory=dict)

    @staticmethod
    def from_dict(d: Dict[str, Any]) -> "TaskSpec":
        recognized_keys = {
            "id",
            "env_id",
            "version",
            "description",
            "name",
            "difficulty",
            "natural_language",
            "deps",
            "tags",
            "init",
            "hooks",
            "success",
            "metadata",
        }
        init = TaskInitSpec(**d.get("init", {}))
        hooks = TaskHooks(**d.get("hooks", {}))
        success = TaskSuccessSpec(**d.get("success", {}))
        return TaskSpec(
            id=d["id"],
            env_id=d.get("env_id"),
            version=d.get("version", "1.0"),
            description=d.get("description"),
            name=d.get("name"),
            difficulty=d.get("difficulty"),
            natural_language=d.get("natural_language"),
            deps=d.get("deps"),
            tags=d.get("tags"),
            init=init,
            hooks=hooks,
            success=success,
            metadata=d.get("metadata", dict()),
            extras={k: v for k, v in d.items() if k not in recognized_keys},
        )
