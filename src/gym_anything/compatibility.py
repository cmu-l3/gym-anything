from __future__ import annotations

from dataclasses import asdict, dataclass, field, replace
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


def _resolve_class(runner: str):
    from .runtime.runners import registry as runner_registry

    cls = runner_registry.resolve_runner_class(runner)
    if cls is None:
        supported = ", ".join(runner_registry.list_runner_keys())
        raise KeyError(f"Unknown runner {runner!r}; supported runners: {supported}")
    return cls


def list_supported_runners() -> List[str]:
    from .runtime.runners import registry as runner_registry

    return runner_registry.list_runner_keys()


def get_runner_compatibility(runner: str) -> RunnerCompatibility:
    """The compatibility row a runner key resolves to on THIS host.

    Each runner class declares its own row (law L1: facts live on the
    party); family keys report the class dispatch would actually use, with
    the row re-keyed to the requested key so key-oriented callers stay
    consistent.
    """
    cls = _resolve_class(runner)
    row = cls.compatibility()
    if row is None:
        row = RunnerCompatibility(
            runner=runner,
            display_name=cls.__name__,
            live_recording=False,
            screenshot_video_assembly=True,
            checkpoint_caching=False,
            savevm=False,
            user_accounts_mode="unsupported",
            notes=["This runner did not declare a compatibility profile."],
        )
    if row.runner != runner:
        row = replace(row, runner=runner)
    return row


def get_runner_compatibility_matrix() -> List[RunnerCompatibility]:
    rows: List[RunnerCompatibility] = []
    for runner in list_supported_runners():
        try:
            rows.append(get_runner_compatibility(runner))
        except Exception:
            continue
    return rows


def infer_runner_key_from_name(name: str) -> Optional[str]:
    """Map a runner class name back to the key that resolves to it here."""
    from .runtime.runners import registry as runner_registry

    normalized = name.lower()
    for key in runner_registry.list_runner_keys():
        try:
            cls = runner_registry.resolve_runner_class(key)
        except Exception:
            continue
        if cls is not None and cls.__name__.lower() == normalized:
            return key
    return None


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
