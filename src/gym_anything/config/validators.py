from __future__ import annotations

from typing import Optional

from ..specs import EnvSpec, TaskSpec
from dataclasses import asdict
from ..verification.contracts import SUPPORTED_SUCCESS_MODES

SUPPORTED_RUNNERS = {"docker", "qemu", "qemu_native", "avd", "avd_native", "avf", "local", "apptainer"}

# Minimal JSON Schemas embedded for optional validation
ENV_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["id", "observation", "action"],
    "properties": {
        "id": {"type": "string"},
        "observation": {
            "type": "array",
            "minItems": 1,
            "items": {"type": "object", "required": ["type"], "properties": {"type": {"type": "string"}}},
        },
        "action": {
            "type": "array",
            "minItems": 1,
            "items": {"type": "object", "required": ["type"], "properties": {"type": {"type": "string"}}},
        },
        "vnc": {"type": "object"},
        "security": {"type": "object"},
        "recording": {"type": "object"},
    },
}

TASK_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "required": ["id", "success"],
    "properties": {
        "id": {"type": "string"},
        "init": {"type": "object"},
        "hooks": {"type": "object"},
        "success": {"type": "object", "required": ["mode"], "properties": {"mode": {"type": "string"}}},
    },
}


def validate_env_spec(spec: EnvSpec) -> None:
    # Minimal structural checks to avoid external dependencies
    if not spec.id:
        raise ValueError("EnvSpec.id is required")
    if not (spec.image or spec.dockerfile):
        # LocalRunner fallback allowed, but we warn via exception only when runner is Docker-required
        pass
    # At least one observation and action is recommended
    if not spec.observation:
        raise ValueError("EnvSpec.observation must specify at least one modality")
    if not spec.action:
        raise ValueError("EnvSpec.action must specify at least one modality")
    if spec.runner and spec.runner not in SUPPORTED_RUNNERS:
        supported = ", ".join(sorted(SUPPORTED_RUNNERS))
        raise ValueError(f"EnvSpec.runner '{spec.runner}' is not supported; supported runners: {supported}")
    # Optional JSON Schema validation if 'jsonschema' is installed
    try:
        import jsonschema  # type: ignore

        jsonschema.validate(instance=asdict(spec), schema=ENV_SCHEMA)
    except ImportError:
        pass


def validate_task_spec(spec: TaskSpec) -> None:
    if not spec.id:
        raise ValueError("TaskSpec.id is required")
    if spec.success.mode not in SUPPORTED_SUCCESS_MODES:
        supported = ", ".join(SUPPORTED_SUCCESS_MODES)
        raise ValueError(
            f"TaskSpec.success.mode '{spec.success.mode}' is not supported; supported modes: {supported}"
        )
    try:
        import jsonschema  # type: ignore

        jsonschema.validate(instance=asdict(spec), schema=TASK_SCHEMA)
    except ImportError:
        pass
