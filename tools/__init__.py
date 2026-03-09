"""Repository tooling."""

from pathlib import Path
import sys

_src_dir = Path(__file__).resolve().parent.parent / "src"
if _src_dir.is_dir():
    _src = str(_src_dir)
    if _src not in sys.path:
        sys.path.insert(0, _src)
