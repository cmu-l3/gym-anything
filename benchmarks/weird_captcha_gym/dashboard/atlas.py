from __future__ import annotations

import csv
import json
import os
import re
import threading
from collections import Counter, defaultdict
from copy import deepcopy
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote

try:  # Package import in tests; local import when the dashboard is executed directly.
    from .catalog import REPO_ROOT, build_catalog
except ImportError:  # pragma: no cover - exercised by the script entrypoint.
    from catalog import REPO_ROOT, build_catalog  # type: ignore[no-redef]


RESEARCH_ROOT = Path(os.environ.get("CAPTCHA_BENCH_RESEARCH_ROOT", REPO_ROOT.parent / "research")).expanduser().resolve()
COLLECTION_ROOT = RESEARCH_ROOT / "collection"
SOURCES_ROOT = COLLECTION_ROOT / "sources"
DEFAULT_CURATION_PATH = COLLECTION_ROOT / "atlas-curation.json"

DECISIONS = ("unreviewed", "shortlisted", "maybe", "rejected")
IMAGE_EXTENSIONS = {".avif", ".gif", ".jpeg", ".jpg", ".png", ".webp"}
VIDEO_EXTENSIONS = {".m4v", ".mov", ".mp4", ".webm"}
AUDIO_EXTENSIONS = {".flac", ".m4a", ".mp3", ".oga", ".ogg", ".wav"}
DOCUMENT_EXTENSIONS = {".pdf"}
TEXT_EXTENSIONS = {".csv", ".json", ".jsonl", ".md", ".rst", ".tsv", ".txt", ".vtt", ".yaml", ".yml"}
CODE_EXTENSIONS = {
    ".c", ".cc", ".cpp", ".css", ".gd", ".go", ".h", ".html", ".java", ".js", ".jsx", ".kt",
    ".php", ".py", ".rb", ".rs", ".sh", ".sql", ".svelte", ".swift", ".toml", ".ts", ".tsx",
    ".vue", ".xml",
}
ARCHIVE_EXTENSIONS = {".7z", ".apk", ".gz", ".jar", ".tar", ".tgz", ".wasm", ".zip"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _read_json_value(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError):
        return None


def _read_json_lines(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                try:
                    value = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(value, dict):
                    rows.append(value)
    except (FileNotFoundError, UnicodeDecodeError):
        pass
    return rows


def _read_text(path: Path, *, limit: int = 60_000) -> str:
    try:
        with path.open(encoding="utf-8", errors="replace") as handle:
            return handle.read(limit).strip()
    except OSError:
        return ""


def _title(value: str) -> str:
    words = value.replace("_", " ").replace("-", " ").split()
    return " ".join(word.upper() if word.lower() in {"3d", "ai", "ui", "vtt"} else word.capitalize() for word in words)


def _compact(value: str, limit: int = 420) -> str:
    text = re.sub(r"\s+", " ", value or "").strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


def _clean_captured_prompt(value: str) -> str:
    parts = [re.sub(r"\s+", " ", part).strip() for part in value.split("|")]
    output: list[str] = []
    for part in parts:
        if part and part not in output and part.lower() != "verify":
            output.append(part)
    return " · ".join(output)


def _artifact_kind(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in IMAGE_EXTENSIONS:
        return "image"
    if suffix in VIDEO_EXTENSIONS:
        return "video"
    if suffix in AUDIO_EXTENSIONS:
        return "audio"
    if suffix in DOCUMENT_EXTENSIONS:
        return "document"
    if suffix in TEXT_EXTENSIONS:
        return "text"
    if suffix in CODE_EXTENSIONS:
        return "code"
    if suffix in ARCHIVE_EXTENSIONS:
        return "archive"
    return "other"


def _artifact_url(slug: str, relative: str) -> str:
    return f"/atlas-media/{quote(slug, safe='')}/{quote(relative, safe='/')}"


def _artifact_score(artifact: dict[str, Any]) -> tuple[int, int, int, str]:
    name = str(artifact["name"]).lower()
    relative = str(artifact["path"]).lower()
    kind_rank = {"image": 0, "video": 1, "document": 2, "audio": 3, "text": 4, "code": 5, "archive": 6, "other": 7}[str(artifact["kind"])]
    if "contact-sheet" in name or "contact_sheet" in name:
        role_rank = 0
    elif name.startswith("page-") or "screenshot" in name:
        role_rank = 1
    elif "cover" in name or "thumbnail" in name or "poster" in name:
        role_rank = 2
    elif "playthrough" in relative or "sample-by-family" in relative:
        role_rank = 3
    elif relative.startswith("media/"):
        role_rank = 4
    elif relative in {"notes.md", "mechanics.md", "microgames.md", "metadata.json"}:
        role_rank = 5
    else:
        role_rank = 8
    size_penalty = 0 if int(artifact["size_bytes"]) >= 20_000 else 1
    return (kind_rank, role_rank, size_penalty, relative)


@lru_cache(maxsize=256)
def source_artifacts(slug: str) -> tuple[dict[str, Any], ...]:
    source_root = (SOURCES_ROOT / slug).resolve()
    try:
        source_root.relative_to(SOURCES_ROOT.resolve())
    except ValueError:
        return ()
    if not source_root.is_dir():
        return ()
    artifacts: list[dict[str, Any]] = []
    for path in source_root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            relative = path.relative_to(source_root).as_posix()
            size = path.stat().st_size
        except OSError:
            continue
        kind = _artifact_kind(path)
        artifacts.append({
            "source_slug": slug,
            "path": relative,
            "name": path.name,
            "kind": kind,
            "bucket": relative.split("/", 1)[0] if "/" in relative else "record",
            "size_bytes": size,
            "url": _artifact_url(slug, relative),
            "previewable": kind in {"image", "video", "audio", "document", "text", "code"},
        })
    artifacts.sort(key=_artifact_score)
    return tuple(artifacts)


def _artifact_excerpt(slug: str, relative: str, kind: str) -> str | None:
    if kind not in {"text", "code"}:
        return None
    source_root = (SOURCES_ROOT / slug).resolve()
    path = (source_root / relative).resolve()
    try:
        path.relative_to(source_root)
    except ValueError:
        return None
    if not path.is_file() or path.stat().st_size > 1_500_000:
        return None
    return _compact(_read_text(path, limit=2_800), 1_200) or None


def artifact_page(slug: str, *, kind: str = "all", offset: int = 0, limit: int = 48) -> dict[str, Any]:
    if not (SOURCES_ROOT / slug).is_dir():
        raise ValueError("unknown Atlas source")
    if kind not in {"all", "image", "video", "audio", "document", "text", "code", "archive", "other"}:
        raise ValueError("unknown artifact kind")
    offset = max(0, int(offset))
    limit = max(1, min(int(limit), 100))
    records = list(source_artifacts(slug))
    if kind != "all":
        records = [record for record in records if record["kind"] == kind]
    page = [dict(record) for record in records[offset: offset + limit]]
    for record in page:
        record["excerpt"] = _artifact_excerpt(slug, str(record["path"]), str(record["kind"]))
    return {
        "slug": slug,
        "kind": kind,
        "offset": offset,
        "limit": limit,
        "total": len(records),
        "has_more": offset + len(page) < len(records),
        "artifacts": page,
    }


def _source_cover(artifacts: Iterable[dict[str, Any]]) -> str | None:
    visual = [record for record in artifacts if record["kind"] == "image"]
    if not visual:
        return None
    preferred = next((record for record in visual if "contact-sheet" in str(record["name"]).lower()), None)
    if preferred is None:
        preferred = next((record for record in visual if int(record["size_bytes"]) >= 20_000), visual[0])
    return str(preferred["url"])


def _normalize_anchor(value: str) -> str:
    slug = value.split("/", 1)[0].strip().lower()
    aliases = {
        "captchaware": "captchaware",
        "nextgen-captchas": "nextgen-captchas-benchmark",
    }
    return aliases.get(slug, slug)


def _related_environments_by_source() -> dict[str, list[dict[str, Any]]]:
    output: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for environment in build_catalog()["environments"]:
        seen: set[str] = set()
        for anchor in environment.get("source_anchors") or []:
            slug = _normalize_anchor(str(anchor))
            if slug in seen or not (SOURCES_ROOT / slug).is_dir():
                continue
            seen.add(slug)
            output[slug].append({
                "id": environment["id"],
                "title": environment["title"],
                "stage": environment["stage"],
                "group": environment["group"],
                "cover": environment["cover"],
                "axes": environment["axes"],
            })
    return output


def _source_status_rank(status: str) -> int:
    return {
        "seed_ready": 0,
        "seed_ready_with_gaps": 1,
        "needs_playthrough": 2,
        "needs_extraction": 3,
        "needs_media": 4,
        "lead_index": 5,
        "reference_only": 6,
        "blocked": 7,
    }.get(status, 8)


@lru_cache(maxsize=1)
def _base_sources() -> tuple[dict[str, Any], ...]:
    catalog_rows = _read_json_lines(COLLECTION_ROOT / "catalog.jsonl")
    mechanics_by_source: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for mechanic in _read_json_lines(COLLECTION_ROOT / "mechanic-index.jsonl"):
        for source_slug in mechanic.get("source_slugs") or []:
            mechanics_by_source[str(source_slug)].append(mechanic)

    sources: list[dict[str, Any]] = []
    for catalog_record in catalog_rows:
        slug = str(catalog_record.get("slug") or "")
        if not slug or not (SOURCES_ROOT / slug).is_dir():
            continue
        record = {**catalog_record, **_read_json(SOURCES_ROOT / slug / "metadata.json")}
        artifacts = source_artifacts(slug)
        counts = Counter(str(artifact["kind"]) for artifact in artifacts)
        media_count = sum(1 for artifact in artifacts if str(artifact["path"]).startswith("media/"))
        indexed_mechanics = mechanics_by_source.get(slug, [])
        sources.append({
            "slug": slug,
            "title": str(record.get("title") or _title(slug)),
            "creator": str(record.get("creator") or "Unknown creator"),
            "source_family": str(record.get("source_family") or "unclassified"),
            "source_family_label": _title(str(record.get("source_family") or "unclassified")),
            "primary_url": str(record.get("primary_url") or ""),
            "status": str(record.get("status") or "reference_only"),
            "status_label": _title(str(record.get("status") or "reference_only")),
            "summary": _compact(str(record.get("notes") or "No collection note recorded."), 620),
            "artifact_policy": str(record.get("artifact_policy") or "not_recorded"),
            "artifact_types": [str(item) for item in record.get("artifact_types") or []],
            "mechanic_count_known": record.get("mechanic_count_known"),
            "collected_at": record.get("collected_at"),
            "artifact_total": len(artifacts),
            "media_total": media_count,
            "artifact_counts": dict(sorted(counts.items())),
            "cover": _source_cover(artifacts),
            "sample_artifacts": [dict(item) for item in artifacts if item["kind"] in {"image", "video", "document"}][:4],
            "indexed_mechanics": [{
                "id": str(item.get("mechanic_id") or ""),
                "title": _title(str(item.get("mechanic_id") or "")),
                "category": str(item.get("category") or ""),
                "action_type": str(item.get("action_type") or ""),
                "seed_strength": str(item.get("seed_strength") or ""),
            } for item in indexed_mechanics],
            "local_path": str(SOURCES_ROOT / slug),
        })
    sources.sort(key=lambda source: (_source_status_rank(str(source["status"])), str(source["title"]).lower()))
    return tuple(sources)


def _artifact_match(slug: str, patterns: Iterable[str]) -> list[dict[str, Any]]:
    compiled = [re.compile(pattern, re.IGNORECASE) for pattern in patterns]
    return [dict(artifact) for artifact in source_artifacts(slug) if any(pattern.search(str(artifact["path"])) for pattern in compiled)]


def _specimen_cover(artifacts: list[dict[str, Any]], fallback: str | None) -> str | None:
    images = [artifact for artifact in artifacts if artifact["kind"] == "image"]
    if images:
        cover = next((artifact for artifact in images if "cover" in str(artifact["name"]).lower()), images[0])
        return str(cover["url"])
    return fallback


def _specimen(
    *,
    specimen_id: str,
    title: str,
    summary: str,
    source_slugs: list[str],
    specimen_type: str,
    category: str,
    action_type: str,
    grading: str,
    seed_strength: str,
    tags: list[str],
    artifacts: list[dict[str, Any]],
    source_index: dict[str, dict[str, Any]],
    ordinal: int | None = None,
) -> dict[str, Any]:
    sources = [source_index[slug] for slug in source_slugs if slug in source_index]
    statuses = [str(source["status"]) for source in sources]
    fallback_cover = next((str(source["cover"]) for source in sources if source.get("cover")), None)
    source_label = sources[0]["title"] if len(sources) == 1 else f"{len(sources)} linked sources"
    return {
        "id": specimen_id,
        "layer": "design" if specimen_type == "indexed_mechanic" else "variant",
        "title": _compact(title, 110),
        "summary": _compact(summary or "No mechanic note recorded.", 950),
        "source_slugs": source_slugs,
        "source_label": source_label,
        "specimen_type": specimen_type,
        "specimen_type_label": _title(specimen_type),
        "category": category,
        "action_type": action_type,
        "grading": grading,
        "seed_strength": seed_strength,
        "tags": list(dict.fromkeys(tag for tag in tags if tag))[:8],
        "status": min(statuses, key=_source_status_rank) if statuses else "reference_only",
        "cover": _specimen_cover(artifacts, fallback_cover),
        "artifact_preview": artifacts[:8],
        "artifact_count": len(artifacts),
        "ordinal": ordinal,
    }


def _family_descriptions(notes: str, families: Iterable[str]) -> dict[str, str]:
    output: dict[str, str] = {}
    family_set = set(families)
    for line in notes.splitlines():
        match = re.match(r"^- `([^`]+)`(?:\s+-\s+(.+))?$", line.strip())
        if match and match.group(1) in family_set:
            output[match.group(1)] = (match.group(2) or "").strip()
    return output


@lru_cache(maxsize=1)
def _base_specimens() -> tuple[dict[str, Any], ...]:
    sources = list(_base_sources())
    source_index = {str(source["slug"]): source for source in sources}
    specimens: list[dict[str, Any]] = []

    for row in _read_json_lines(COLLECTION_ROOT / "mechanic-index.jsonl"):
        mechanic_id = str(row.get("mechanic_id") or "")
        source_slugs = [str(slug) for slug in row.get("source_slugs") or [] if str(slug) in source_index]
        attachments: list[dict[str, Any]] = []
        for slug in source_slugs[:4]:
            attachments.extend([dict(item) for item in source_artifacts(slug) if item["kind"] in {"image", "video", "document"}][:2])
        specimens.append(_specimen(
            specimen_id=f"mechanic--{mechanic_id}",
            title=_title(mechanic_id),
            summary=str(row.get("notes") or ""),
            source_slugs=source_slugs,
            specimen_type="indexed_mechanic",
            category=str(row.get("category") or "cross-source mechanic"),
            action_type=str(row.get("action_type") or "mixed"),
            grading=str(row.get("grading") or "source-specific"),
            seed_strength=str(row.get("seed_strength") or "unrated"),
            tags=[str(row.get("category") or ""), str(row.get("action_type") or ""), str(row.get("seed_strength") or "")],
            artifacts=attachments,
            source_index=source_index,
        ))

    neal_slug = "neal-im-not-a-robot"
    for row in _read_json_lines(SOURCES_ROOT / neal_slug / "mechanics.jsonl"):
        level = int(row.get("level") or 0)
        patterns = [rf"(?:^|/)covers_level-{level}\.", rf"(?:^|/)guide_level-{level}\.", rf"(?:^|/)level-{level}\.(?:txt|html)$"]
        attachments = _artifact_match(neal_slug, patterns)
        raw_title = str(row.get("title") or f"Level {level}")
        title = re.sub(rf"^Level\s+{level}\s*[–—-]\s*", "", raw_title, flags=re.IGNORECASE)
        specimens.append(_specimen(
            specimen_id=f"{neal_slug}--level-{level}",
            title=title,
            summary=str(row.get("mechanic_text") or ""),
            source_slugs=[neal_slug],
            specimen_type="hand_authored_level",
            category="hand-authored CAPTCHA level",
            action_type="mixed computer use",
            grading="game-defined verifier",
            seed_strength="high",
            tags=["hand-authored", "level", "mixed interaction"],
            artifacts=attachments,
            source_index=source_index,
            ordinal=level,
        ))

    captchaware_slug = "captchaware"
    for index, row in enumerate(_read_json_lines(SOURCES_ROOT / captchaware_slug / "microgames.jsonl"), start=1):
        microgame = str(row.get("microgame") or f"microgame-{index}")
        script = str(row.get("primaryScript") or "")
        patterns = [rf"(?:^|/){re.escape(script)}$", rf"{re.escape(microgame)}"] if script else [rf"{re.escape(microgame)}"]
        attachments = _artifact_match(captchaware_slug, patterns)
        title = str(row.get("instructionsBig") or _title(microgame))
        summary = " ".join(str(row.get(key) or "") for key in ("instructionSmall1", "instructionSmall2", "errorMessage"))
        specimens.append(_specimen(
            specimen_id=f"{captchaware_slug}--{microgame}",
            title=title,
            summary=summary,
            source_slugs=[captchaware_slug],
            specimen_type="source_microgame",
            category="rapid CAPTCHA microgame",
            action_type="mixed computer use",
            grading="source-script verifier",
            seed_strength="high",
            tags=["microgame", "timed", microgame],
            artifacts=attachments,
            source_index=source_index,
            ordinal=index,
        ))

    rpg_slug = "captcha-rpg"
    state_index = SOURCES_ROOT / rpg_slug / "raw/live-capture/captcha-rpg-state-index-2026-07-08.tsv"
    try:
        with state_index.open(encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
    except FileNotFoundError:
        rows = []
    for row in rows:
        index = int(row.get("index") or 0)
        prompt = _clean_captured_prompt(str(row.get("prompt_excerpt") or ""))
        title = _compact(prompt.split(" · ", 1)[0] or _title(str(row.get("verify_id") or f"State {index}")), 84)
        screenshot = str(row.get("screenshot") or "")
        attachments = _artifact_match(rpg_slug, [rf"^{re.escape(screenshot)}$"]) if screenshot else []
        specimens.append(_specimen(
            specimen_id=f"{rpg_slug}--state-{index:02d}",
            title=title,
            summary=prompt,
            source_slugs=[rpg_slug],
            specimen_type="captured_challenge_state",
            category="narrative CAPTCHA state",
            action_type="mixed computer use",
            grading="source-script verifier",
            seed_strength="high",
            tags=["captured state", "narrative", "source-guided"],
            artifacts=attachments,
            source_index=source_index,
            ordinal=index,
        ))

    family_sources = (
        ("nextgen-captchas-benchmark", "raw/repos/NextGen-CAPTCHAs/captcha_data", "generator_family"),
        ("opencaptchaworld-benchmark", "raw/repos/OpenCaptchaWorld/captcha_data", "benchmark_family"),
    )
    for slug, relative_root, specimen_type in family_sources:
        family_root = SOURCES_ROOT / slug / relative_root
        families = sorted(path.name for path in family_root.iterdir() if path.is_dir()) if family_root.is_dir() else []
        descriptions = _family_descriptions(_read_text(SOURCES_ROOT / slug / "notes.md"), families)
        for index, family in enumerate(families, start=1):
            attachments = _artifact_match(slug, [rf"sample-by-family/{re.escape(family)}_sample_", rf"captcha_data/{re.escape(family)}/"])
            if len(attachments) > 12:
                attachments = attachments[:12]
            summary = descriptions.get(family) or f"Source-backed {_title(family)} puzzle family with local generator or benchmark artifacts and sampled states."
            specimens.append(_specimen(
                specimen_id=f"{slug}--{family}",
                title=_title(family),
                summary=summary,
                source_slugs=[slug],
                specimen_type=specimen_type,
                category="procedural visual puzzle family",
                action_type="family-specific computer use",
                grading="family-specific ground truth",
                seed_strength="high",
                tags=["procedural", "generator", _title(family)],
                artifacts=attachments,
                source_index=source_index,
                ordinal=index,
            ))

    specimens.sort(key=lambda item: (
        0 if item.get("cover") else 1,
        0 if item.get("seed_strength") == "high" else 1,
        _source_status_rank(str(item.get("status"))),
        str(item.get("source_label", "")).lower(),
        int(item.get("ordinal") or 10_000),
        str(item["title"]).lower(),
    ))
    return tuple(specimens)


CAPTCHA_ROYALE_DESCRIPTIONS = {
    "balance": "Read a balance scale and infer which side or object satisfies the weight relation.",
    "booleanlogic": "Evaluate a visual Boolean-logic expression rather than transcribing a symbol.",
    "cascade": "Complete a time-pressured cascade of small CAPTCHA decisions.",
    "clock": "Read or manipulate an analog clock face.",
    "color": "Resolve an adversarial color-perception or Ishihara-style prompt.",
    "cubefolding": "Mentally fold a 2D cube net and identify the valid 3D result.",
    "dotcount": "Count visually disrupted dots while ignoring decoys.",
    "fraction": "Compare fractions represented through a visual interface.",
    "gears": "Predict gear rotation through a connected mechanical system.",
    "gradient": "Order or select swatches by a subtle visual gradient.",
    "graphread": "Read a plotted graph and answer a question about its values.",
    "grid": "Solve an image or shape selection grid generated from a seed.",
    "jigsaw": "Reconstruct an occluded image by manipulating jigsaw pieces.",
    "math": "Solve a visually disrupted arithmetic expression with decoy marks.",
    "matrix": "Complete a visual matrix by combining several transformation rules.",
    "metamorphic": "Track a puzzle whose visual state mutates during interaction.",
    "mirror": "Distinguish valid mirror transforms from subtly invalid ones.",
    "multistep": "Carry information through a chain of dependent verification steps.",
    "oddity": "Find the semantic or visual odd-one-out.",
    "overlap": "Count or reason about shapes hidden inside overlapping geometry.",
    "pathtracing": "Trace a valid route through a generated visual maze.",
    "rotation": "Recognize an object after rotation while rejecting lookalikes.",
    "sequence": "Infer the missing element in a visual sequence.",
    "shadow": "Reason about whether a rendered shadow is geometrically consistent.",
    "spatial": "Resolve a 3D spatial relationship from a rendered scene.",
    "text": "Transcribe warped text with noise, decoys, and overlapping strokes.",
    "typography": "Interpret adversarial typography whose layout carries part of the answer.",
    "unscramble": "Reorder a visually disrupted set of letters into the intended word.",
}


EVIL_CAPTCHA_DESCRIPTIONS = {
    "advanced_comprehension_test": "Click the requested shape using another object's color, size, or state as an indirect reference.",
    "amongus": "Inspect a cast of characters and identify the impostor.",
    "butterfly": "Control the character and eat every moving butterfly.",
    "comprehension_test": "Parse a compositional shape-and-color instruction, then click the matching object.",
    "gambling": "Operate a betting interface until the balance exceeds a target.",
    "image_search": "Search a cluttered visual field for the named object.",
    "math": "Solve a rendered equation whose result is truncated to an integer.",
    "multi_box": "Keep selecting matching image boxes as the set replenishes.",
    "puzzle_slide": "Drag a puzzle fragment into its matching gap.",
    "rorschach": "Answer a deliberately subjective inkblot question in four words or fewer.",
    "single_box": "Select all matching cells in a single image grid above a required accuracy threshold.",
    "slimer": "Use WASD to cross a hazardous lane without touching minecarts or water.",
    "sponsor": "Watch or navigate an interrupting sponsor message before verification continues.",
    "wimmelbild": "Find a tiny requested target inside a dense hidden-object scene.",
    "wizard": "Chase and capture a moving wizard before it escapes.",
    "wonky_text": "Type the characters shown in a distorted image.",
}


@lru_cache(maxsize=1)
def _extra_variants() -> tuple[dict[str, Any], ...]:
    """Return source-exact variants omitted by the original six-format extractor.

    These records come only from explicit generator files or structured extraction
    manifests. Advertised counts without an enumerated artifact are intentionally
    not expanded into invented cards.
    """
    source_index = {str(source["slug"]): source for source in _base_sources()}
    variants: list[dict[str, Any]] = []

    def add(
        slug: str,
        key: str,
        title: str,
        summary: str,
        specimen_type: str,
        *,
        category: str,
        action_type: str,
        grading: str,
        tags: list[str],
        artifacts: list[dict[str, Any]],
        ordinal: int,
    ) -> None:
        if slug not in source_index:
            return
        variants.append(_specimen(
            specimen_id=f"{slug}--{key}",
            title=title,
            summary=summary,
            source_slugs=[slug],
            specimen_type=specimen_type,
            category=category,
            action_type=action_type,
            grading=grading,
            seed_strength="high",
            tags=tags,
            artifacts=artifacts,
            source_index=source_index,
            ordinal=ordinal,
        ))

    royale_slug = "captcha-royale"
    royale_root = SOURCES_ROOT / royale_slug / "raw/repos/captcha-royale/packages/captcha-engine/src/generators"
    generators = sorted(path for path in royale_root.glob("*.rs") if path.name != "mod.rs")
    for index, path in enumerate(generators, start=1):
        generator = path.stem
        add(
            royale_slug,
            f"generator-{generator}",
            _title(generator),
            CAPTCHA_ROYALE_DESCRIPTIONS.get(generator, f"Verified procedural {generator} generator."),
            "verified_generator",
            category="procedural CAPTCHA generator",
            action_type="generator-specific computer use",
            grading="seeded server-side answer key",
            tags=["procedural", "seeded", generator],
            artifacts=_artifact_match(royale_slug, [rf"/generators/{re.escape(path.name)}$", r"media/page-endless-started"]),
            ordinal=index,
        )

    nicholas_slug = "github-nicholasdejesse-captcha-game"
    nicholas_rows = _read_json_value(SOURCES_ROOT / nicholas_slug / "raw/extracted-mechanics.json")
    for index, row in enumerate(nicholas_rows if isinstance(nicholas_rows, list) else [], start=1):
        component = str(row.get("component") or f"component-{index}")
        mechanic = str(row.get("mechanic") or "Source-extracted CAPTCHA component.")
        keywords = [word for word in re.findall(r"[A-Za-z0-9]+", component) if len(word) > 3]
        patterns = [r"raw/extracted-mechanics\.json$"] + [re.escape(word) for word in keywords]
        add(
            nicholas_slug,
            f"component-{component.lower()}",
            re.sub(r"(?<!^)(?=[A-Z])", " ", component),
            mechanic,
            "source_component",
            category="web CAPTCHA game component",
            action_type="component-specific computer use",
            grading="source component verifier",
            tags=["component", "web game", component],
            artifacts=_artifact_match(nicholas_slug, patterns)[:8],
            ordinal=index,
        )

    simple_slug = "github-ttuples-simplecaptcha"
    simple_rows = _read_json_value(SOURCES_ROOT / simple_slug / "raw/extracted-mechanics.json")
    for index, row in enumerate(simple_rows if isinstance(simple_rows, list) else [], start=1):
        mechanic_id = str(row.get("id") or f"grid-{index}")
        positives = int(row.get("positive_count") or 0)
        add(
            simple_slug,
            f"grid-{mechanic_id}",
            _title(mechanic_id),
            f"A verified 4×4 Minecraft image grid with {positives} positive cell{'s' if positives != 1 else ''}; prompt key: {row.get('prompt_key') or 'unknown'}.",
            "extracted_grid_family",
            category="game-native image selection grid",
            action_type="multi-cell selection",
            grading="exact positive-cell set",
            tags=["Minecraft", "4x4 grid", mechanic_id],
            artifacts=_artifact_match(simple_slug, [rf"media/captcha-grids/{re.escape(mechanic_id)}\.", r"raw/extracted-mechanics\.json$"])[:6],
            ordinal=index,
        )

    evil_slug = "modrinth-evil-captcha"
    evil_payload = _read_json(SOURCES_ROOT / evil_slug / "raw/extracted-mechanics.json")
    screen_rows = evil_payload.get("screen_classes") if isinstance(evil_payload.get("screen_classes"), list) else []
    screen_rows = [row for row in screen_rows if str(row.get("mechanic_id") or "") != "abstract"]
    for index, row in enumerate(screen_rows, start=1):
        mechanic_id = str(row.get("mechanic_id") or f"screen-{index}")
        screen_class = str(row.get("screen_class") or "CaptchaScreen")
        add(
            evil_slug,
            f"screen-{mechanic_id}",
            _title(mechanic_id),
            EVIL_CAPTCHA_DESCRIPTIONS.get(mechanic_id, f"Verified screen class {screen_class}."),
            "extracted_game_screen",
            category="in-game interruption CAPTCHA",
            action_type="screen-specific keyboard and pointer control",
            grading="game screen verifier",
            tags=["Minecraft", "interruptive", mechanic_id],
            artifacts=_artifact_match(evil_slug, [re.escape(screen_class), r"raw/extracted-mechanics\.json$"])[:8],
            ordinal=index,
        )

    henry_slug = "github-henryamatsu-im-not-a-robot"
    henry_payload = _read_json(SOURCES_ROOT / henry_slug / "raw/extracted-mechanics.json")
    base_categories = henry_payload.get("base_image_categories") if isinstance(henry_payload.get("base_image_categories"), list) else []
    modifiers = henry_payload.get("challenge_modifiers") if isinstance(henry_payload.get("challenge_modifiers"), list) else []
    for index, category in enumerate(base_categories, start=1):
        key = str(category)
        add(
            henry_slug,
            f"category-{key}",
            f"Select {_title(key)}",
            f"Select {key} from a replenishing image grid until none remain; difficulty can add visual modifiers and additional blocks.",
            "source_category",
            category="replenishing image-grid category",
            action_type="repeated multi-cell selection",
            grading="source positive-cell set",
            tags=["image grid", "replenishing", key],
            artifacts=_artifact_match(henry_slug, [re.escape(key), r"raw/extracted-mechanics\.json$"])[:6],
            ordinal=index,
        )
    for offset, modifier in enumerate(modifiers, start=1):
        key = str(modifier)
        add(
            henry_slug,
            f"modifier-{key}",
            f"{_title(key)} Modifier",
            f"A verified challenge modifier that applies {key} to the image-grid task as difficulty rises.",
            "source_modifier",
            category="image-grid difficulty modifier",
            action_type="visually transformed multi-cell selection",
            grading="source positive-cell set",
            tags=["modifier", "difficulty", key],
            artifacts=_artifact_match(henry_slug, [re.escape(key), r"raw/extracted-mechanics\.json$"])[:6],
            ordinal=len(base_categories) + offset,
        )

    variants.sort(key=lambda item: (str(item["source_label"]).lower(), int(item.get("ordinal") or 0), str(item["title"]).lower()))
    return tuple(variants)


INSTANCE_DATASETS = (
    {
        "slug": "nextgen-captchas-benchmark",
        "dataset": "NextGen-CAPTCHAs",
        "relative_root": "raw/repos/NextGen-CAPTCHAs/captcha_data",
    },
    {
        "slug": "opencaptchaworld-benchmark",
        "dataset": "OpenCaptchaWorld",
        "relative_root": "raw/repos/OpenCaptchaWorld/captcha_data",
    },
)

INSTANCE_MEDIA_EXTENSIONS = IMAGE_EXTENSIONS | VIDEO_EXTENSIONS | AUDIO_EXTENSIONS
INSTANCE_PRIMARY_FIELDS = (
    "image", "media_path", "movement_gif", "main_image", "reference_image", "reference",
    "order_image", "object_base_image", "component_image", "cell_id",
)
INSTANCE_COLLECTION_FIELDS = (
    "options", "option_images", "pieces", "cells", "cell_files", "images",
)
INSTANCE_ANSWER_FIELDS = (
    "answer", "answer_top", "correct_positions", "correct_selections", "correct_patches",
    "correct_option", "correct_option_index", "sum", "target_position", "required_hits",
)


def _artifact_for_file(slug: str, path: Path) -> dict[str, Any] | None:
    source_root = (SOURCES_ROOT / slug).resolve()
    try:
        resolved = path.resolve()
        relative = resolved.relative_to(source_root).as_posix()
        size = resolved.stat().st_size
    except (OSError, ValueError):
        return None
    kind = _artifact_kind(resolved)
    return {
        "source_slug": slug,
        "path": relative,
        "name": resolved.name,
        "kind": kind,
        "bucket": relative.split("/", 1)[0] if "/" in relative else "record",
        "size_bytes": size,
        "url": _artifact_url(slug, relative),
        "previewable": kind in {"image", "video", "audio", "document", "text", "code"},
    }


def _string_values(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [item for item in value if isinstance(item, str)]
    return []


def _instance_assets(
    slug: str,
    dataset_root: Path,
    family_root: Path,
    record_key: str,
    ground_truth: dict[str, Any],
) -> list[dict[str, Any]]:
    files = [path for path in family_root.rglob("*") if path.is_file() and path.suffix.lower() in INSTANCE_MEDIA_EXTENSIONS]
    by_name: dict[str, list[Path]] = defaultdict(list)
    by_stem: dict[str, list[Path]] = defaultdict(list)
    for path in files:
        by_name[path.name.lower()].append(path)
        by_stem[path.stem.lower()].append(path)

    candidates: list[str] = []
    if Path(record_key).suffix.lower() in INSTANCE_MEDIA_EXTENSIONS:
        candidates.append(record_key)
    else:
        candidates.append(record_key)
    for field in INSTANCE_PRIMARY_FIELDS + INSTANCE_COLLECTION_FIELDS:
        candidates.extend(_string_values(ground_truth.get(field)))

    cell_pool = _read_json(family_root / "cell_pool.json")
    expanded_candidates: list[str] = []
    for candidate in candidates:
        expanded_candidates.append(candidate)
        pool_record = cell_pool.get(candidate)
        if isinstance(pool_record, dict) and isinstance(pool_record.get("filename"), str):
            expanded_candidates.append(str(pool_record["filename"]))
    candidates = expanded_candidates

    subfolders = [str(ground_truth.get(key) or "") for key in ("subfolder", "puzzle_dir")]
    resolved: list[Path] = []
    seen_paths: set[Path] = set()

    def accept(path: Path) -> bool:
        if not path.is_file() or path.suffix.lower() not in INSTANCE_MEDIA_EXTENSIONS:
            return False
        canonical = path.resolve()
        if canonical in seen_paths:
            return False
        seen_paths.add(canonical)
        resolved.append(path)
        return True

    for raw_candidate in candidates:
        candidate = raw_candidate.strip().replace("\\", "/").removeprefix("./")
        if not candidate:
            continue
        relative_candidate = Path(candidate)
        direct: list[Path] = [family_root / relative_candidate]
        if candidate.startswith("captcha_data/"):
            direct.insert(0, dataset_root.parent / relative_candidate)
        for subfolder in subfolders:
            if subfolder:
                direct.append(family_root / subfolder / relative_candidate.name)
        if not relative_candidate.suffix:
            expanded: list[Path] = []
            for path in direct:
                expanded.extend(path.with_suffix(extension) for extension in sorted(INSTANCE_MEDIA_EXTENSIONS))
            direct = expanded + direct
        matched = False
        for path in direct:
            matched = accept(path) or matched
        if matched:
            continue
        lookup = by_name.get(relative_candidate.name.lower()) or by_stem.get(relative_candidate.stem.lower()) or []
        if lookup:
            preferred = next((path for path in lookup if any(folder and folder in path.parts for folder in subfolders)), lookup[0])
            accept(preferred)
        if len(resolved) >= 32:
            break

    return [artifact for path in resolved[:32] if (artifact := _artifact_for_file(slug, path)) is not None]


def _answer_preview(ground_truth: dict[str, Any]) -> str | None:
    for field in INSTANCE_ANSWER_FIELDS:
        if field not in ground_truth:
            continue
        try:
            rendered = json.dumps(ground_truth[field], ensure_ascii=False, separators=(",", ":"))
        except TypeError:
            rendered = str(ground_truth[field])
        return _compact(rendered, 260)
    return None


def _instance_interaction(ground_truth: dict[str, Any]) -> str:
    if ground_truth.get("input_type"):
        return _title(str(ground_truth["input_type"]))
    if ground_truth.get("hold_time"):
        return "Timed press and hold"
    if ground_truth.get("correct_positions") or ground_truth.get("component_image"):
        return "Drag and place"
    if ground_truth.get("target_position") or isinstance(ground_truth.get("answer"), dict):
        return "Coordinate click or placement"
    if ground_truth.get("required_hits"):
        return "Timed reaction clicks"
    if ground_truth.get("cells") or ground_truth.get("options") or ground_truth.get("correct_patches"):
        return "Visual selection"
    if ground_truth.get("media_type"):
        return f"{_title(str(ground_truth['media_type']))} response"
    return "Source-defined computer use"


def _record_title(family: str, record_key: str, ordinal: int) -> str:
    del record_key  # Source keys mix zero- and one-based numbering; JSON order is the stable display ordinal.
    return f"{_title(family)} · {ordinal:03d}"


def _virc_prompts() -> dict[tuple[str, int], str]:
    path = SOURCES_ROOT / "visual-reasoning-captcha-vtt" / "media/examples/Examples.md"
    prompts: dict[tuple[str, int], str] = {}
    family = ""
    for line in _read_text(path).splitlines():
        heading = re.match(r"^##\s+(.+)$", line.strip())
        if heading:
            family = heading.group(1).strip().lower()
            continue
        item = re.match(r"^(\d+)\.\s+(.+)$", line.strip())
        if family and item:
            prompts[(family, int(item.group(1)))] = item.group(2).strip()
    return prompts


@lru_cache(maxsize=1)
def _base_instances() -> tuple[dict[str, Any], ...]:
    source_index = {str(source["slug"]): source for source in _base_sources()}
    records: list[dict[str, Any]] = []

    for provider in INSTANCE_DATASETS:
        slug = str(provider["slug"])
        dataset_root = SOURCES_ROOT / slug / str(provider["relative_root"])
        source = source_index.get(slug, {})
        for family_root in sorted((path for path in dataset_root.iterdir() if path.is_dir()), key=lambda path: path.name.lower()) if dataset_root.is_dir() else []:
            ground_truth_path = family_root / "ground_truth.json"
            payload = _read_json(ground_truth_path)
            ordinal = 0
            for record_key, raw_truth in payload.items():
                if record_key == "config" or not isinstance(raw_truth, dict):
                    continue
                ordinal += 1
                ground_truth = deepcopy(raw_truth)
                assets = _instance_assets(slug, dataset_root, family_root, str(record_key), ground_truth)
                prompt = str(ground_truth.get("prompt") or "Source record does not include a prompt.")
                description = str(ground_truth.get("description") or prompt)
                records.append({
                    "id": f"instance--{slug}--{family_root.name}--{record_key}",
                    "layer": "instance",
                    "title": _record_title(family_root.name, str(record_key), ordinal),
                    "source_slug": slug,
                    "source_label": str(source.get("title") or _title(slug)),
                    "dataset": str(provider["dataset"]),
                    "family": family_root.name,
                    "family_title": _title(family_root.name),
                    "variant_id": f"{slug}--{family_root.name}",
                    "record_key": str(record_key),
                    "record_type": "ground_truth_challenge",
                    "ground_truth_status": "recorded",
                    "prompt": _compact(prompt, 800),
                    "summary": _compact(description, 800),
                    "interaction": _instance_interaction(ground_truth),
                    "media_type": str(ground_truth.get("media_type") or (assets[0]["kind"] if assets else "not recorded")),
                    "answer_preview": _answer_preview(ground_truth),
                    "cover": str(assets[0]["url"]) if assets else None,
                    "asset_count": len(assets),
                    "assets": assets,
                    "ground_truth": ground_truth,
                })

    virc_slug = "visual-reasoning-captcha-vtt"
    virc_source = source_index.get(virc_slug, {})
    examples_root = SOURCES_ROOT / virc_slug / "media/examples"
    prompts = _virc_prompts()
    example_paths = sorted(path for path in examples_root.iterdir() if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS) if examples_root.is_dir() else []
    for path in example_paths:
        match = re.match(r"([A-Za-z]+)_(\d+)$", path.stem)
        family = match.group(1).lower() if match else "unknown"
        ordinal = int(match.group(2)) if match else 0
        prompt = prompts.get((family, ordinal), "Prompt not transcribed in the local example index.")
        artifact = _artifact_for_file(virc_slug, path)
        assets = [artifact] if artifact else []
        records.append({
            "id": f"instance--{virc_slug}--{family}--{path.name}",
            "layer": "instance",
            "title": f"{_title(family)} captured example · {ordinal:02d}",
            "source_slug": virc_slug,
            "source_label": str(virc_source.get("title") or "Visual Reasoning CAPTCHA / ViRC"),
            "dataset": "ViRC public examples",
            "family": family,
            "family_title": _title(family),
            "variant_id": None,
            "record_key": path.name,
            "record_type": "captured_example",
            "ground_truth_status": "unavailable",
            "prompt": prompt,
            "summary": "A real public visual-reasoning CAPTCHA example preserved as survey evidence; the local artifact does not include an answer key.",
            "interaction": "Prompt-conditioned coordinate click",
            "media_type": "image",
            "answer_preview": None,
            "cover": str(artifact["url"]) if artifact else None,
            "asset_count": len(assets),
            "assets": assets,
            "ground_truth": None,
        })

    records.sort(key=lambda item: (str(item["source_label"]).lower(), str(item["family_title"]).lower(), str(item["record_key"]).lower()))
    return tuple(records)


def _instance_summary(record: dict[str, Any], curation: dict[str, dict[str, Any]]) -> dict[str, Any]:
    summary = {key: deepcopy(value) for key, value in record.items() if key not in {"assets", "ground_truth"}}
    summary["curation"] = _curation_record(str(record["id"]), curation)
    return summary


def instance_page(
    *,
    query: str = "",
    source: str = "all",
    family: str = "all",
    record_type: str = "all",
    decision: str = "all",
    offset: int = 0,
    limit: int = 36,
    store: AtlasCurationStore | None = None,
) -> dict[str, Any]:
    if record_type not in {"all", "ground_truth_challenge", "captured_example"}:
        raise ValueError("unknown instance record type")
    if decision not in {"all", "promoted", *DECISIONS}:
        raise ValueError("unknown curation decision")
    offset = max(0, int(offset))
    limit = max(1, min(int(limit), 72))
    needle = query.strip().lower()
    curation = (store or AtlasCurationStore()).all()
    matches: list[dict[str, Any]] = []
    for record in _base_instances():
        if source != "all" and record["source_slug"] != source:
            continue
        if family != "all" and record["family"] != family:
            continue
        if record_type != "all" and record["record_type"] != record_type:
            continue
        mark = _curation_record(str(record["id"]), curation)
        if decision == "promoted" and not mark["promoted"]:
            continue
        if decision not in {"all", "promoted"} and mark["decision"] != decision:
            continue
        haystack = " ".join(str(record.get(key) or "") for key in (
            "title", "source_label", "dataset", "family_title", "record_key", "prompt", "summary",
            "interaction", "answer_preview",
        )).lower()
        if needle and needle not in haystack:
            continue
        matches.append(record)
    page_records = [_instance_summary(record, curation) for record in matches[offset: offset + limit]]
    return {
        "query": query,
        "source": source,
        "family": family,
        "record_type": record_type,
        "decision": decision,
        "offset": offset,
        "limit": limit,
        "total": len(matches),
        "has_more": offset + len(page_records) < len(matches),
        "instances": page_records,
    }


def instance_detail(item_id: str, store: AtlasCurationStore | None = None) -> dict[str, Any]:
    record = next((item for item in _base_instances() if item["id"] == item_id), None)
    if record is None:
        raise ValueError("unknown Atlas instance")
    output = deepcopy(record)
    output["curation"] = _curation_record(item_id, (store or AtlasCurationStore()).all())
    source = next((item for item in _base_sources() if item["slug"] == record["source_slug"]), None)
    output["source"] = deepcopy(source) if source else None
    variant = next((item for item in (*_base_specimens(), *_extra_variants()) if item["id"] == record.get("variant_id")), None)
    output["variant"] = deepcopy(variant) if variant else None
    return output


@lru_cache(maxsize=1)
def _atlas_item_ids() -> frozenset[str]:
    return frozenset(
        str(item["id"])
        for item in (*_base_specimens(), *_extra_variants(), *_base_instances())
    )


class AtlasCurationStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = (path or DEFAULT_CURATION_PATH).expanduser().resolve()
        self._lock = threading.RLock()

    def all(self) -> dict[str, dict[str, Any]]:
        with self._lock:
            payload = _read_json(self.path)
            items = payload.get("items") if isinstance(payload, dict) else {}
            if not isinstance(items, dict):
                return {}
            return {str(key): dict(value) for key, value in items.items() if isinstance(value, dict)}

    def update(self, item_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        if item_id not in _atlas_item_ids():
            raise ValueError("unknown Atlas record")
        decision = str(payload.get("decision") or "unreviewed")
        if decision not in DECISIONS:
            raise ValueError("invalid curation decision")
        note = str(payload.get("note") or "").strip()
        if len(note) > 5_000:
            raise ValueError("curation note is too long")
        promoted = bool(payload.get("promoted", False))
        if promoted:
            decision = "shortlisted"
        if decision == "rejected":
            promoted = False

        with self._lock:
            existing_payload = _read_json(self.path)
            items = existing_payload.get("items") if isinstance(existing_payload.get("items"), dict) else {}
            previous = items.get(item_id) if isinstance(items.get(item_id), dict) else {}
            now = utc_now()
            record = {
                "decision": decision,
                "note": note,
                "promoted": promoted,
                "created_at": previous.get("created_at") or now,
                "updated_at": now,
                "promoted_at": (previous.get("promoted_at") or now) if promoted else None,
            }
            if decision == "unreviewed" and not note and not promoted:
                items.pop(item_id, None)
            else:
                items[item_id] = record
            output = {"version": 1, "updated_at": now, "items": items}
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.path.with_suffix(self.path.suffix + ".tmp")
            temporary.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            temporary.replace(self.path)
            return record


def _curation_record(item_id: str, records: dict[str, dict[str, Any]]) -> dict[str, Any]:
    record = records.get(item_id) or {}
    decision = str(record.get("decision") or "unreviewed")
    if decision not in DECISIONS:
        decision = "unreviewed"
    return {
        "decision": decision,
        "note": str(record.get("note") or ""),
        "promoted": bool(record.get("promoted")),
        "created_at": record.get("created_at"),
        "updated_at": record.get("updated_at"),
        "promoted_at": record.get("promoted_at"),
    }


def build_atlas(store: AtlasCurationStore | None = None) -> dict[str, Any]:
    store = store or AtlasCurationStore()
    curation = store.all()
    related = _related_environments_by_source()
    sources = [deepcopy(source) for source in _base_sources()]
    records = [deepcopy(item) for item in (*_base_specimens(), *_extra_variants())]
    designs = [item for item in records if item["layer"] == "design"]
    variants = [item for item in records if item["layer"] == "variant"]

    for item in records:
        item["curation"] = _curation_record(str(item["id"]), curation)
        environment_ids: set[str] = set()
        linked: list[dict[str, Any]] = []
        for slug in item["source_slugs"]:
            for environment in related.get(str(slug), []):
                if environment["id"] not in environment_ids:
                    environment_ids.add(environment["id"])
                    linked.append(environment)
        item["related_environments"] = linked
        item["related_environment_count"] = len(linked)

    instances = _base_instances()
    instance_source_counts = Counter(str(item["source_slug"]) for item in instances)
    instance_family_counts = Counter((str(item["source_slug"]), str(item["family"])) for item in instances)
    instance_type_counts = Counter(str(item["record_type"]) for item in instances)
    instance_family_covers: dict[tuple[str, str], str | None] = {}
    for item in instances:
        key = (str(item["source_slug"]), str(item["family"]))
        if key not in instance_family_covers or (not instance_family_covers[key] and item.get("cover")):
            instance_family_covers[key] = str(item["cover"]) if item.get("cover") else None

    design_source_counts = Counter(slug for item in designs for slug in item["source_slugs"])
    variant_source_counts = Counter(slug for item in variants for slug in item["source_slugs"])
    for source in sources:
        slug = str(source["slug"])
        source["related_environments"] = related.get(slug, [])
        source["related_environment_count"] = len(source["related_environments"])
        source["design_count"] = design_source_counts[slug]
        source["variant_count"] = variant_source_counts[slug]
        source["instance_count"] = instance_source_counts[slug]
        source["instance_family_count"] = sum(1 for candidate, _family in instance_family_counts if candidate == slug)

    known = _atlas_item_ids()
    valid_marks = {item_id: _curation_record(item_id, curation) for item_id in curation if item_id in known}
    counts = Counter(mark["decision"] for mark in valid_marks.values())
    layer_ids = {
        "designs": {str(item["id"]) for item in designs},
        "variants": {str(item["id"]) for item in variants},
        "instances": {str(item["id"]) for item in instances},
    }
    layer_curation: dict[str, dict[str, int]] = {}
    for layer, item_ids in layer_ids.items():
        marks = [mark for item_id, mark in valid_marks.items() if item_id in item_ids]
        layer_counts = Counter(mark["decision"] for mark in marks)
        layer_curation[layer] = {
            "reviewed": len(marks),
            "shortlisted": layer_counts["shortlisted"],
            "maybe": layer_counts["maybe"],
            "rejected": layer_counts["rejected"],
            "promoted": sum(bool(mark["promoted"]) for mark in marks),
        }

    artifact_total = sum(int(source["artifact_total"]) for source in sources)
    media_total = sum(int(source["media_total"]) for source in sources)
    visual_asset_total = sum(int(source["artifact_counts"].get("image", 0)) for source in sources)
    family_facets = [
        {
            "source_slug": slug,
            "family": family,
            "family_title": _title(family),
            "count": count,
            "cover": instance_family_covers.get((slug, family)),
        }
        for (slug, family), count in sorted(instance_family_counts.items(), key=lambda item: (item[0][0], item[0][1].lower()))
    ]
    source_index = {str(source["slug"]): source for source in sources}
    instance_sources = [
        {
            "slug": slug,
            "title": str(source_index.get(slug, {}).get("title") or _title(slug)),
            "count": count,
            "families": sum(1 for candidate, _family in instance_family_counts if candidate == slug),
        }
        for slug, count in sorted(instance_source_counts.items(), key=lambda item: str(source_index.get(item[0], {}).get("title") or item[0]).lower())
    ]
    selection_total = len(designs) + len(variants) + len(instances)
    return {
        "available": bool(sources),
        "title": "Survey Atlas",
        "tagline": "From reusable mechanic to concrete challenge, with every source file intact.",
        "stats": {
            "designs": len(designs),
            "variants": len(variants),
            "instances": len(instances),
            "ground_truth_instances": instance_type_counts["ground_truth_challenge"],
            "captured_examples": instance_type_counts["captured_example"],
            "selection_records": selection_total,
            "catalog_records": selection_total + len(sources),
            "specimens": len(designs) + len(variants),
            "sources": len(sources),
            "files": artifact_total,
            "media": media_total,
            "visual_assets": visual_asset_total,
            "indexed_mechanics": len(_read_json_lines(COLLECTION_ROOT / "mechanic-index.jsonl")),
            "seed_ready_sources": sum(source["status"] in {"seed_ready", "seed_ready_with_gaps"} for source in sources),
            "reviewed": len(valid_marks),
            "shortlisted": counts["shortlisted"],
            "maybe": counts["maybe"],
            "rejected": counts["rejected"],
            "promoted": sum(bool(mark["promoted"]) for mark in valid_marks.values()),
        },
        "layer_curation": layer_curation,
        "decisions": list(DECISIONS),
        "statuses": sorted({str(source["status"]) for source in sources}, key=_source_status_rank),
        "families": sorted({str(source["source_family"]) for source in sources}),
        "artifact_kinds": ["image", "video", "audio", "document", "text", "code", "archive", "other"],
        "designs": designs,
        "variants": variants,
        "specimens": records,
        "instance_sources": instance_sources,
        "instance_families": family_facets,
        "featured_instances": [_instance_summary(item, curation) for item in instances if item.get("cover")][:12],
        "sources": sources,
    }


def specimen_detail(item_id: str, store: AtlasCurationStore | None = None) -> dict[str, Any]:
    atlas = build_atlas(store)
    specimen = next((item for item in atlas["specimens"] if item["id"] == item_id), None)
    if specimen is None:
        raise ValueError("unknown Atlas specimen")
    source_index = {source["slug"]: source for source in atlas["sources"]}
    sources = [source_index[slug] for slug in specimen["source_slugs"] if slug in source_index]
    attachments = list(specimen["artifact_preview"])
    seen = {(item["url"], item["path"]) for item in attachments}
    for source in sources:
        for artifact in source["sample_artifacts"]:
            key = (artifact["url"], artifact["path"])
            if key not in seen:
                seen.add(key)
                attachments.append(artifact)
    for artifact in attachments[:24]:
        artifact["excerpt"] = _artifact_excerpt(
            str(artifact["source_slug"]),
            str(artifact["path"]),
            str(artifact["kind"]),
        )
    specimen["artifacts"] = attachments[:24]
    specimen["sources"] = sources
    return specimen


def source_detail(slug: str, store: AtlasCurationStore | None = None) -> dict[str, Any]:
    atlas = build_atlas(store)
    source = next((item for item in atlas["sources"] if item["slug"] == slug), None)
    if source is None:
        raise ValueError("unknown Atlas source")
    source["notes"] = _read_text(SOURCES_ROOT / slug / "notes.md")
    linked_records = [
        {
            "id": specimen["id"],
            "title": specimen["title"],
            "layer": specimen["layer"],
            "specimen_type": specimen["specimen_type"],
            "cover": specimen["cover"],
            "summary": specimen["summary"],
            "curation": specimen["curation"],
        }
        for specimen in atlas["specimens"]
        if slug in specimen["source_slugs"]
    ]
    source["designs"] = [item for item in linked_records if item["layer"] == "design"]
    source["variants"] = [item for item in linked_records if item["layer"] == "variant"]
    source["specimens"] = linked_records
    page = instance_page(source=slug, limit=12, store=store)
    source["instances"] = page["instances"]
    source["instance_total"] = page["total"]
    source["instance_families"] = [item for item in atlas["instance_families"] if item["source_slug"] == slug]
    return source


def clear_atlas_caches() -> None:
    source_artifacts.cache_clear()
    _base_sources.cache_clear()
    _base_specimens.cache_clear()
    _extra_variants.cache_clear()
    _base_instances.cache_clear()
    _atlas_item_ids.cache_clear()


__all__ = [
    "AtlasCurationStore",
    "COLLECTION_ROOT",
    "DEFAULT_CURATION_PATH",
    "DECISIONS",
    "RESEARCH_ROOT",
    "SOURCES_ROOT",
    "artifact_page",
    "build_atlas",
    "clear_atlas_caches",
    "instance_detail",
    "instance_page",
    "source_detail",
    "specimen_detail",
]
