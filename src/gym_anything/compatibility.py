from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Dict, Iterable, List, Literal, Optional


UserAccountsMode = Literal[
    "provision_from_spec",
    "preprovisioned_accounts",
    "metadata_only",
    "unsupported",
]


@dataclass(frozen=True)
class RunnerCompatibility:
    runner: str
    display_name: str
    live_recording: bool
    screenshot_video_assembly: bool
    checkpoint_caching: bool
    savevm: bool
    user_accounts_mode: UserAccountsMode
    notes: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, object]:
        return asdict(self)


_RUNNER_COMPATIBILITY: Dict[str, RunnerCompatibility] = {
    "docker": RunnerCompatibility(
        runner="docker",
        display_name="DockerRunner",
        live_recording=True,
        screenshot_video_assembly=True,
        checkpoint_caching=True,
        savevm=False,
        user_accounts_mode="provision_from_spec",
        notes=[
            "Creates and configures user accounts from EnvSpec.user_accounts.",
            "This is the only runner with live FFmpeg episode recording built into reset().",
        ],
    ),
    "qemu": RunnerCompatibility(
        runner="qemu",
        display_name="QemuApptainerRunner",
        live_recording=False,
        screenshot_video_assembly=True,
        checkpoint_caching=True,
        savevm=True,
        user_accounts_mode="preprovisioned_accounts",
        notes=[
            "Linux guests ship with a prebuilt ga user; Windows guests ship with a prebuilt Docker user.",
            "EnvSpec.user_accounts is treated as declared credential metadata rather than guest-side provisioning.",
        ],
    ),
    "qemu_native": RunnerCompatibility(
        runner="qemu_native",
        display_name="QemuNativeRunner",
        live_recording=False,
        screenshot_video_assembly=True,
        checkpoint_caching=True,
        savevm=True,
        user_accounts_mode="preprovisioned_accounts",
        notes=[
            "Runs QEMU directly without Apptainer; works on macOS and bare-metal Linux.",
            "Uses HVF acceleration on Intel Macs, KVM on Linux, TCG (slow) on Apple Silicon.",
            "Identical VM behavior to QemuApptainerRunner; only the QEMU launch mechanism differs.",
        ],
    ),
    "avd": RunnerCompatibility(
        runner="avd",
        display_name="AVDApptainerRunner",
        live_recording=False,
        screenshot_video_assembly=True,
        checkpoint_caching=True,
        savevm=False,
        user_accounts_mode="metadata_only",
        notes=[
            "Android user_accounts fields describe expected credentials or roles; they are not provisioned by the runner.",
        ],
    ),
    "avd_native": RunnerCompatibility(
        runner="avd_native",
        display_name="AVDNativeRunner",
        live_recording=False,
        screenshot_video_assembly=True,
        checkpoint_caching=True,
        savevm=False,
        user_accounts_mode="metadata_only",
        notes=[
            "Runs Android emulator directly without Apptainer; works on macOS and bare-metal Linux.",
            "Uses HVF acceleration on macOS, KVM on Linux.",
            "Identical behavior to AVDApptainerRunner; only the emulator launch mechanism differs.",
        ],
    ),
    "apptainer": RunnerCompatibility(
        runner="apptainer",
        display_name="ApptainerDirectRunner",
        live_recording=False,
        screenshot_video_assembly=True,
        checkpoint_caching=False,
        savevm=False,
        user_accounts_mode="preprovisioned_accounts",
        notes=[
            "The standard direct-Apptainer preset includes a prebuilt ga user.",
            "EnvSpec.user_accounts is compatible as credential/config metadata, not as general-purpose account provisioning.",
        ],
    ),
    "avf": RunnerCompatibility(
        runner="avf",
        display_name="AVFRunner",
        live_recording=False,
        screenshot_video_assembly=True,
        checkpoint_caching=False,
        savevm=False,
        user_accounts_mode="preprovisioned_accounts",
        notes=[
            "Uses Apple Virtualization Framework with Rosetta for x86_64 binary translation.",
            "Near-native speed (~80% of native) for x86 binaries on Apple Silicon.",
            "Requires macOS 13+ on Apple Silicon, vfkit, and gvproxy.",
        ],
    ),
    "local": RunnerCompatibility(
        runner="local",
        display_name="LocalRunner",
        live_recording=False,
        screenshot_video_assembly=False,
        checkpoint_caching=False,
        savevm=False,
        user_accounts_mode="unsupported",
        notes=[
            "LocalRunner is a smoke-test backend with synthetic observations only.",
        ],
    ),
}


def list_supported_runners() -> List[str]:
    return list(_RUNNER_COMPATIBILITY)


def get_runner_compatibility(runner: str) -> RunnerCompatibility:
    try:
        return _RUNNER_COMPATIBILITY[runner]
    except KeyError as exc:
        supported = ", ".join(sorted(_RUNNER_COMPATIBILITY))
        raise KeyError(f"Unknown runner {runner!r}; supported runners: {supported}") from exc


def get_runner_compatibility_matrix() -> List[RunnerCompatibility]:
    return [get_runner_compatibility(runner) for runner in _RUNNER_COMPATIBILITY]


def infer_runner_key_from_name(name: str) -> Optional[str]:
    normalized = name.lower()
    aliases = {
        "dockerrunner": "docker",
        "qemuapptainerrunner": "qemu",
        "qemunativerunner": "qemu_native",
        "avdapptainerrunner": "avd",
        "avdnativerunner": "avd_native",
        "avfrunner": "avf",
        "apptainerdirectrunner": "apptainer",
        "localrunner": "local",
    }
    return aliases.get(normalized)


def render_compatibility_text(
    compatibilities: Iterable[RunnerCompatibility],
) -> str:
    lines: List[str] = []
    for compatibility in compatibilities:
        lines.append(f"{compatibility.runner}: {compatibility.display_name}")
        lines.append(
            "  "
            + ", ".join(
                [
                    f"live_recording={'yes' if compatibility.live_recording else 'no'}",
                    f"screenshot_video_assembly={'yes' if compatibility.screenshot_video_assembly else 'no'}",
                    f"checkpoint_caching={'yes' if compatibility.checkpoint_caching else 'no'}",
                    f"savevm={'yes' if compatibility.savevm else 'no'}",
                    f"user_accounts={compatibility.user_accounts_mode}",
                ]
            )
        )
        for note in compatibility.notes:
            lines.append(f"  - {note}")
    return "\n".join(lines)


__all__ = [
    "RunnerCompatibility",
    "UserAccountsMode",
    "get_runner_compatibility",
    "get_runner_compatibility_matrix",
    "infer_runner_key_from_name",
    "list_supported_runners",
    "render_compatibility_text",
]
