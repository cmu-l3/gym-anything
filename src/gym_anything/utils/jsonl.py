from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict


class JSONLWriter:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._fh = self.path.open("a", encoding="utf-8")

    def write(self, obj: Dict[str, Any]) -> None:
        self._fh.write(json.dumps(obj) + "\n")
        self._fh.flush()

    def close(self) -> None:
        try:
            self._fh.close()
        except Exception:
            pass

