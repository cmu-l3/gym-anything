from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict


def load_structured_file(path: Path) -> Dict[str, Any]:
    """Load YAML or JSON file.

    Uses PyYAML if installed for .yaml/.yml; always supports .json via stdlib.
    """
    suffix = path.suffix.lower()
    if suffix == ".json":
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    if suffix in (".yaml", ".yml"):
        try:
            import yaml  # type: ignore
        except Exception as e:
            raise RuntimeError(
                "PyYAML is required to load YAML files. Install 'pyyaml' or provide JSON."
            ) from e
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
        if not isinstance(data, dict):
            raise ValueError("Top-level YAML must be a mapping/dict")
        return data
    raise ValueError(f"Unsupported file type: {suffix}")

