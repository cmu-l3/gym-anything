"""Compile a self-contained static visualizer into website/explore/.

Layout produced:

    website/explore/
      index.html              (from web_static/)
      app.js                  (from web/)            — same code, dual-mode
      style.css               (from web/)
      static_index.js         (from web_static/)
      api_static.js           (from web_static/)
      embed_loader.js         (from web_static/)
      data/
        index.json
        favorites.json
        embeddings_bge.f16.bin
        embedding_ids_bge.json

The compiled site has zero runtime dependencies. transformers.js is lazy-loaded
from a CDN on the first user search; everything else is local.
"""

from __future__ import annotations

import gzip
import json
import logging
import shutil
from pathlib import Path
from typing import Optional

from .embed_browser import EMBEDDINGS_BGE, EMBEDDING_IDS_BGE
from .paths import (
    DATA_DIR,
    FAVORITES,
    INDEX_JSON,
    REPO_ROOT,
    VISUALIZER_ROOT,
    WEB_DIR,
)

logger = logging.getLogger(__name__)


WEB_STATIC_DIR = VISUALIZER_ROOT / "web_static"
DEFAULT_DEST = REPO_ROOT / "website" / "explore"


def _copy(src: Path, dst: Path) -> None:
    if not src.is_file():
        raise RuntimeError(f"missing source: {src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


def run(dest: Optional[Path] = None) -> dict:
    if dest is None:
        dest = DEFAULT_DEST
    dest = Path(dest).resolve()
    if dest.exists():
        logger.info("Removing existing dest tree: %s", dest)
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    (dest / "data").mkdir()

    # Required source files.
    sources = [
        (WEB_STATIC_DIR / "index.html", dest / "index.html"),
        (WEB_DIR / "style.css", dest / "style.css"),
        (WEB_DIR / "app.js", dest / "app.js"),
        (WEB_STATIC_DIR / "static_index.js", dest / "static_index.js"),
        (WEB_STATIC_DIR / "api_static.js", dest / "api_static.js"),
        (WEB_STATIC_DIR / "embed_loader.js", dest / "embed_loader.js"),
    ]
    for s, d in sources:
        _copy(s, d)

    # Data files.
    data_sources = [
        (INDEX_JSON, dest / "data" / "index.json"),
        (FAVORITES, dest / "data" / "favorites.json"),
        (EMBEDDINGS_BGE, dest / "data" / "embeddings_bge.f16.bin"),
        (EMBEDDING_IDS_BGE, dest / "data" / "embedding_ids_bge.json"),
    ]
    for s, d in data_sources:
        _copy(s, d)

    # Pre-gzip the heavy data files so static hosts that honor `.gz`
    # accept-encoding negotiation (GitHub Pages does, when paired with the
    # right Content-Encoding header) can serve compressed payloads. Browsers
    # can also fall back to the uncompressed file. Servers that don't honor
    # .gz will simply ignore these.
    gz_targets = [
        dest / "data" / "index.json",
        dest / "data" / "embeddings_bge.f16.bin",
    ]
    for t in gz_targets:
        gz_path = t.with_suffix(t.suffix + ".gz")
        with t.open("rb") as fin, gzip.open(gz_path, "wb", compresslevel=9) as fout:
            shutil.copyfileobj(fin, fout)

    # Manifest with sizes for sanity.
    manifest = []
    total_bytes = 0
    for f in sorted(dest.rglob("*")):
        if f.is_file():
            size = f.stat().st_size
            total_bytes += size
            manifest.append({
                "path": str(f.relative_to(dest)),
                "bytes": size,
            })
    (dest / "manifest.json").write_text(
        json.dumps({"total_bytes": total_bytes, "files": manifest}, indent=2),
        encoding="utf-8",
    )

    logger.info("Compiled static site → %s (%.1f MB across %d files)",
                dest, total_bytes / 1024 / 1024, len(manifest))
    return {"dest": str(dest), "total_bytes": total_bytes, "n_files": len(manifest)}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    print(json.dumps(run(), indent=2))
