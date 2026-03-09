"""Compatibility wrapper for config validation helpers."""

from .config.validators import validate_env_spec, validate_task_spec

__all__ = ["validate_env_spec", "validate_task_spec"]
