#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from typing import Any, Iterable

try:  # Package import in tests; local import when executed as a script.
    from .catalog import BENCHMARK_ROOT, REPO_ROOT, build_catalog
except ImportError:  # pragma: no cover - exercised by the script entrypoint.
    from catalog import BENCHMARK_ROOT, REPO_ROOT, build_catalog  # type: ignore[no-redef]


DASHBOARD_ROOT = Path(__file__).resolve().parent
STATIC_ROOT = DASHBOARD_ROOT / "static"
DEFAULT_OUTPUT = DASHBOARD_ROOT / "dist" / "captcha-bench-dashboard"


def _media_urls(value: Any) -> Iterable[str]:
    if isinstance(value, dict):
        for item in value.values():
            yield from _media_urls(item)
    elif isinstance(value, list):
        for item in value:
            yield from _media_urls(item)
    elif isinstance(value, str) and value.startswith("/media/"):
        yield value


def _rewrite_media_urls(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _rewrite_media_urls(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_rewrite_media_urls(item) for item in value]
    if isinstance(value, str) and value.startswith("/media/"):
        return f"media/{value.removeprefix('/media/')}"
    return value


def _shared_app_source() -> str:
    source = (STATIC_ROOT / "app.js").read_text(encoding="utf-8")
    if "/api/atlas" in source or "Survey Atlas" in source:
        raise RuntimeError("dashboard app still contains retired Survey Atlas routes")
    return source


def _validate_output_path(output: Path) -> None:
    protected = (Path.home().resolve(), REPO_ROOT.resolve(), BENCHMARK_ROOT.resolve(), DASHBOARD_ROOT.resolve())
    if output.parent == Path(output.anchor) or any(output == path or path.is_relative_to(output) for path in protected):
        raise ValueError(f"refusing to replace a protected or top-level directory: {output}")


def export_dashboard(
    output: Path,
    *,
    companion_url: str = "http://127.0.0.1:8767",
    copy_media: bool = True,
) -> dict[str, Any]:
    output = output.expanduser().resolve()
    _validate_output_path(output)
    shutil.rmtree(output, ignore_errors=True)
    (output / "static").mkdir(parents=True)
    (output / "data").mkdir(parents=True)

    catalog = build_catalog()
    media_urls = sorted(set(_media_urls(catalog)))
    missing: list[str] = []
    copied_files = 0
    copied_bytes = 0
    if copy_media:
        for media_url in media_urls:
            relative = Path(media_url.removeprefix("/media/"))
            source = (BENCHMARK_ROOT / relative).resolve()
            try:
                source.relative_to(BENCHMARK_ROOT.resolve())
            except ValueError as exc:
                raise ValueError(f"catalog media escapes the benchmark root: {media_url}") from exc
            if not source.is_file():
                missing.append(media_url)
                continue
            destination = output / "media" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            copied_files += 1
            copied_bytes += source.stat().st_size
        if missing:
            raise FileNotFoundError(f"{len(missing)} catalog media files are missing; first: {missing[0]}")

        for relative in (Path("README.md"), Path("docs/interaction-puzzle-field-notes.md")):
            source = BENCHMARK_ROOT / relative
            destination = output / "media" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            copied_files += 1
            copied_bytes += source.stat().st_size

    (output / "index.html").write_text((STATIC_ROOT / "index.html").read_text(encoding="utf-8"), encoding="utf-8")
    (output / "static" / "styles.css").write_text((STATIC_ROOT / "styles.css").read_text(encoding="utf-8"), encoding="utf-8")
    (output / "static" / "app.js").write_text(_shared_app_source(), encoding="utf-8")
    shared_config = {
        "mode": "shared",
        "catalogUrl": "data/catalog.json",
        "companionUrl": companion_url.rstrip("/"),
    }
    (output / "static" / "config.js").write_text(
        "window.CAPTCHA_BENCH_CONFIG = Object.freeze(" + json.dumps(shared_config, separators=(",", ":")) + ");\n",
        encoding="utf-8",
    )
    (output / "data" / "catalog.json").write_text(
        json.dumps(_rewrite_media_urls(catalog), ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )

    manifest = {
        "version": 1,
        "survey_included": False,
        "catalog": {
            "total": catalog["stats"]["total"],
            "built": catalog["stats"]["built"],
            "solution_videos": catalog["stats"]["solution_videos"],
        },
        "companion_url": shared_config["companionUrl"],
        "referenced_media_files": len(media_urls),
        "copied_media_files": copied_files,
        "copied_media_bytes": copied_bytes,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export the Survey-free CAPTCHA Bench dashboard as a static website.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--companion-url", default="http://127.0.0.1:8767")
    parser.add_argument("--no-media", action="store_true", help="Skip media copies for a fast structural test export")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = export_dashboard(args.output, companion_url=args.companion_url, copy_media=not args.no_media)
    print(f"Static CAPTCHA Bench dashboard: {args.output.expanduser().resolve()}")
    print(f"Catalog: {manifest['catalog']['built']} built · Survey excluded")
    print(f"Media: {manifest['copied_media_files']} files · {manifest['copied_media_bytes']} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
