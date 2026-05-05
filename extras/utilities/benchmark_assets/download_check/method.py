"""Scan and optionally check external benchmark asset URLs.

Adapted for `gym-anything-extras` from the asset download/check script
shared by Tianbao Xie (GitHub: @Timothyxxx) in cmu-l3/gym-anything
issue #2:

    https://github.com/cmu-l3/gym-anything/issues/2

This utility is intentionally an extras method, not runtime code. It reads
benchmark setup scripts, reports external asset dependencies, and can either
probe links or download them into a local cache for investigation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterable, Optional
from urllib.parse import unquote, urlparse


DEFAULT_SKIP_PATTERNS = (
    "localhost",
    "127.0.0.1",
    "0.0.0.0",
    "${",
    "$(",
    "svc.cluster.local",
    "/api/",
    "/xmlrpc/",
    "/web/login",
    "/login",
    "/health",
    "/flush",
    "/index.php",
    "/interface/",
)


DEFAULT_ALLOWED_DOMAINS = {
    # Media / images
    "upload.wikimedia.org",
    "images.metmuseum.org",
    "esahubble.org",
    "dl.polyhaven.org",
    "imagej.nih.gov",
    "wsr.imagej.net",
    "imagej.net",
    # Data / science
    "files.rcsb.org",
    "eutils.ncbi.nlm.nih.gov",
    "archive.ics.uci.edu",
    "data.broadinstitute.org",
    "naciscdn.org",
    "data.celltrackingchallenge.net",
    "earthquake.usgs.gov",
    "gml.noaa.gov",
    "www.ncei.noaa.gov",
    "data.usaid.gov",
    "fred.stlouisfed.org",
    "feodotracker.abuse.ch",
    "www.cisa.gov",
    "physionet.org",
    "zenodo.org",
    "ndownloader.figshare.com",
    # Code / tools
    "raw.githubusercontent.com",
    "github.com",
    "repo1.maven.org",
    "services.gradle.org",
    # GIS / maps
    "www.naturalearthdata.com",
    "naturalearth.s3.amazonaws.com",
    "download.geofabrik.de",
    "tile.loc.gov",
    # 3D / assets
    "download.blender.org",
    # Books
    "www.gutenberg.org",
    # Video / audio
    "commondatastorage.googleapis.com",
    "actions.google.com",
    # Science tools
    "www.astro.louisville.edu",
    "m-selig.ae.illinois.edu",
    "energyplus-weather.s3.amazonaws.com",
    "wiki.wireshark.org",
    # Misc
    "en.wikipedia.org",
    "web.archive.org",
    "huggingface.co",
    "cdn.huggingface.co",
    "www.rubomedical.com",
    "downloads.mysql.com",
    "download.oracle.com",
    "download.eclipse.org",
    "ftp.ebi.ac.uk",
    "ftp.ncbi.nlm.nih.gov",
    "stacks.iop.org",
    "www.sample-videos.com",
    "filesamples.com",
    "file-examples.com",
}


@dataclass
class UrlSource:
    source_file: str
    line: int
    output_name: Optional[str] = None


@dataclass
class AssetEntry:
    url: str
    domain: Optional[str]
    filename: str
    used_by: list[str] = field(default_factory=list)
    sources: list[UrlSource] = field(default_factory=list)
    local_path: Optional[str] = None
    status: Optional[str] = None
    http_code: Optional[int] = None
    size_bytes: Optional[int] = None
    error: Optional[str] = None


def _repo_root() -> Path:
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "src" / "gym_anything").is_dir() and (parent / "benchmarks").is_dir():
            return parent
    return Path.cwd()


def _default_benchmarks_root() -> Path:
    return _repo_root() / "benchmarks" / "cua_world" / "environments"


def _default_output_dir() -> Path:
    return _repo_root() / "gym_anything_asset_audit"


def extract_urls_from_file(script_path: Path) -> list[tuple[str, int, Optional[str]]]:
    """Extract download-looking URLs from one script.

    The patterns intentionally match the issue author's script: shell
    `wget`/`curl`, Python `urllib`/`requests`, and URL variable assignment.
    """
    try:
        content = script_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []

    results: list[tuple[str, int, Optional[str]]] = []
    for line_num, line in enumerate(content.splitlines(), 1):
        urls: list[str] = []
        output_name: Optional[str] = None

        if "wget" in line or (
            "curl" in line and ("-o" in line.lower() or "--output" in line)
        ):
            urls = re.findall(r"https?://[^\s\"'\\)}>]+", line)
            match = re.search(r"-[oO]\s+[\"']?([^\s\"']+)", line)
            if match:
                output_name = match.group(1)
            if not output_name:
                match = re.search(r">\s*[\"']?([^\s\"']+)", line)
                if match:
                    output_name = match.group(1)
        elif any(keyword in line for keyword in ("urlretrieve", "urlopen", "requests.get")):
            urls = re.findall(r"https?://[^\s\"'\\)}>]+", line)
        elif re.search(
            r"(?:url|URL|download_url|DATA_URL|DOWNLOAD_URL|FILE_URL|SRC_URL)\s*=\s*[\"']https?://",
            line,
        ):
            urls = re.findall(r"https?://[^\s\"'\\)}>]+", line)

        for url in urls:
            results.append((url.rstrip(",;"), line_num, output_name))
    return results


def should_skip(url: str, skip_patterns: Iterable[str] = DEFAULT_SKIP_PATTERNS) -> bool:
    return any(pattern in url for pattern in skip_patterns)


def is_allowed_domain(url: str, allowed_domains: set[str]) -> bool:
    if not allowed_domains:
        return True
    return urlparse(url).hostname in allowed_domains


def scan_assets(
    benchmarks_root: Path,
    *,
    all_domains: bool = False,
    include_env_scripts: bool = True,
) -> tuple[list[AssetEntry], list[dict[str, Optional[str]]]]:
    """Scan benchmark setup scripts and return unique URL entries."""
    allowed_domains = set() if all_domains else DEFAULT_ALLOWED_DOMAINS
    entries_by_url: dict[str, AssetEntry] = {}
    filtered: list[dict[str, Optional[str]]] = []

    def add_entry(script: Path, used_by: str) -> None:
        for url, line, output_name in extract_urls_from_file(script):
            if should_skip(url):
                continue
            domain = urlparse(url).hostname
            if not is_allowed_domain(url, allowed_domains):
                filtered.append({"url": url, "domain": domain})
                continue
            parsed = urlparse(url)
            filename = unquote(Path(parsed.path).name) or "index.html"
            entry = entries_by_url.get(url)
            if entry is None:
                entry = AssetEntry(url=url, domain=domain, filename=filename)
                entries_by_url[url] = entry
            if used_by not in entry.used_by:
                entry.used_by.append(used_by)
            entry.sources.append(
                UrlSource(
                    source_file=str(script),
                    line=line,
                    output_name=output_name,
                )
            )

    for script in sorted(benchmarks_root.glob("*/tasks/*/setup_task.sh")):
        parts = script.relative_to(benchmarks_root).parts
        add_entry(script, f"{parts[0]}/{parts[2]}")

    if include_env_scripts:
        for script in sorted(benchmarks_root.glob("*/scripts/*.sh")):
            env_name = script.relative_to(benchmarks_root).parts[0]
            add_entry(script, f"{env_name}/_env_scripts")

    return list(entries_by_url.values()), filtered


def url_to_local_path(entry: AssetEntry, output_dir: Path) -> Path:
    domain = entry.domain or "unknown"
    filename = re.sub(r"[?#].*$", "", entry.filename)
    filename = re.sub(r"[^\w.\-]", "_", filename)
    if not filename or filename == "index.html":
        filename = hashlib.md5(entry.url.encode()).hexdigest()[:12]
    url_hash = hashlib.md5(entry.url.encode()).hexdigest()[:8]
    safe_name = f"{url_hash}_{filename}"
    if len(safe_name) > 200:
        ext = Path(filename).suffix
        safe_name = f"{url_hash}_{filename[:100]}{ext}"
    return output_dir / "files" / domain / safe_name


def _proxy_args(proxy: Optional[str]) -> list[str]:
    proxy = (
        proxy
        or os.environ.get("HTTPS_PROXY")
        or os.environ.get("https_proxy")
        or os.environ.get("HTTP_PROXY")
        or os.environ.get("http_proxy")
    )
    return ["--proxy", proxy] if proxy else []


def check_one_url(
    entry: AssetEntry,
    *,
    connect_timeout: int,
    max_time: int,
    proxy: Optional[str] = None,
) -> AssetEntry:
    """Probe a URL without downloading the full file."""
    curl_base = [
        "curl",
        "--silent",
        "--show-error",
        "--location",
        "--connect-timeout",
        str(connect_timeout),
        "--max-time",
        str(max_time),
        "--retry",
        "1",
        "--user-agent",
        "gym-anything-asset-check/0.1 (+https://github.com/cmu-l3/gym-anything)",
        *_proxy_args(proxy),
    ]

    commands = [
        [*curl_base, "-I", "-o", "/dev/null", "-w", "%{http_code}", entry.url],
        [
            *curl_base,
            "--range",
            "0-0",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            entry.url,
        ],
    ]

    last_error = ""
    for command in commands:
        result = subprocess.run(command, capture_output=True, text=True)
        code = _parse_http_code(result.stdout)
        if code and code != 405:
            entry.http_code = code
            entry.status = "ok" if 200 <= code < 400 else "failed"
            if entry.status == "failed":
                entry.error = (result.stderr or "").strip()[:240] or f"HTTP {code}"
            return entry
        last_error = (result.stderr or result.stdout or "").strip()

    entry.status = "failed"
    entry.http_code = None
    entry.error = last_error[:240] or "No HTTP status returned"
    return entry


def _parse_http_code(text: str) -> Optional[int]:
    text = (text or "").strip()
    if not text:
        return None
    token = text.split()[-1]
    try:
        return int(token)
    except ValueError:
        return None


def download_one(
    entry: AssetEntry,
    output_dir: Path,
    *,
    connect_timeout: int,
    max_time: int,
    proxy: Optional[str] = None,
) -> AssetEntry:
    """Download one URL into the local audit cache."""
    local_path = url_to_local_path(entry, output_dir)
    entry.local_path = str(local_path)
    if local_path.exists() and local_path.stat().st_size > 0:
        entry.status = "already_exists"
        entry.size_bytes = local_path.stat().st_size
        return entry

    local_path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "curl",
        "--silent",
        "--show-error",
        "--fail",
        "--location",
        "--connect-timeout",
        str(connect_timeout),
        "--max-time",
        str(max_time),
        "--retry",
        "2",
        "--insecure",
        "-o",
        str(local_path),
        "-H",
        "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
        *_proxy_args(proxy),
        entry.url,
    ]

    try:
        result = subprocess.run(command, capture_output=True, timeout=max_time + 60)
    except subprocess.TimeoutExpired:
        entry.status = "timeout"
        entry.error = "download timed out"
        local_path.unlink(missing_ok=True)
        return entry

    if result.returncode == 0 and local_path.exists() and local_path.stat().st_size > 0:
        entry.status = "downloaded"
        entry.size_bytes = local_path.stat().st_size
        return entry

    stderr = result.stderr.decode(errors="replace") if isinstance(result.stderr, bytes) else str(result.stderr)
    entry.status = "failed"
    entry.error = stderr[:240]
    local_path.unlink(missing_ok=True)
    return entry


def _entry_to_dict(entry: AssetEntry) -> dict[str, Any]:
    data = asdict(entry)
    data["sources"] = [asdict(source) for source in entry.sources]
    return data


def summarize(entries: list[AssetEntry], filtered: list[dict[str, Optional[str]]]) -> dict[str, Any]:
    failed = [
        entry for entry in entries
        if entry.status in {"failed", "timeout", "error"}
        or (entry.http_code is not None and not (200 <= entry.http_code < 400))
    ]
    affected_tasks = sorted(
        {
            used_by
            for entry in failed
            for used_by in entry.used_by
            if not used_by.endswith("/_env_scripts")
        }
    )
    affected_env_scripts = sorted(
        {
            used_by
            for entry in failed
            for used_by in entry.used_by
            if used_by.endswith("/_env_scripts")
        }
    )
    status_counts: dict[str, int] = {}
    domain_counts: dict[str, int] = {}
    for entry in failed:
        key = str(entry.http_code) if entry.http_code is not None else (entry.status or "unknown")
        status_counts[key] = status_counts.get(key, 0) + 1
        domain = entry.domain or "unknown"
        domain_counts[domain] = domain_counts.get(domain, 0) + 1

    return {
        "total_urls": len(entries) + len(filtered),
        "downloadable_urls": len(entries),
        "filtered_urls": len(filtered),
        "checked_or_downloaded_urls": sum(1 for entry in entries if entry.status is not None),
        "failed_urls": len(failed),
        "affected_tasks": len(affected_tasks),
        "affected_env_scripts": len(affected_env_scripts),
        "failed_status_counts": dict(sorted(status_counts.items())),
        "failed_domain_counts": dict(
            sorted(domain_counts.items(), key=lambda item: (-item[1], item[0]))
        ),
        "affected_task_ids": affected_tasks,
        "affected_env_script_ids": affected_env_scripts,
    }


def write_report(
    output_dir: Path,
    entries: list[AssetEntry],
    filtered: list[dict[str, Optional[str]]],
) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "summary": summarize(entries, filtered),
        "entries": [_entry_to_dict(entry) for entry in entries],
        "filtered_entries": filtered,
    }
    path = output_dir / "asset_download_check.json"
    path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def _print_text_summary(summary: dict[str, Any], report_path: Optional[Path]) -> None:
    print("Gym Anything benchmark asset URL audit")
    print(f"  total external URLs:       {summary['total_urls']}")
    print(f"  downloadable URLs:         {summary['downloadable_urls']}")
    print(f"  filtered URLs:             {summary['filtered_urls']}")
    print(f"  checked/downloaded URLs:   {summary['checked_or_downloaded_urls']}")
    print(f"  failed URLs:               {summary['failed_urls']}")
    print(f"  affected task scripts:     {summary['affected_tasks']}")
    print(f"  affected env scripts:      {summary['affected_env_scripts']}")
    if summary["failed_status_counts"]:
        print("  failed status counts:")
        for status, count in summary["failed_status_counts"].items():
            print(f"    {status}: {count}")
    if report_path:
        print(f"  report: {report_path}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gym-anything-extras utilities benchmark_assets download_check",
        description="Scan CUA-World setup scripts for external asset URLs.",
    )
    parser.add_argument(
        "--benchmarks-root",
        type=Path,
        default=_default_benchmarks_root(),
        help="Path to benchmarks/cua_world/environments.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=_default_output_dir(),
        help="Directory for reports and optional downloaded files.",
    )
    parser.add_argument(
        "--all-domains",
        action="store_true",
        help="Include every non-skipped URL, not just known asset domains.",
    )
    parser.add_argument(
        "--no-env-scripts",
        action="store_true",
        help="Only scan task-level setup_task.sh scripts.",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check-links",
        action="store_true",
        help="Probe URLs with HEAD/range requests without downloading full files.",
    )
    mode.add_argument(
        "--download",
        action="store_true",
        help="Download all discovered asset URLs into the output cache.",
    )
    parser.add_argument("--jobs", type=int, default=4, help="Parallel workers.")
    parser.add_argument("--proxy", default=None, help="HTTP(S) proxy URL.")
    parser.add_argument("--connect-timeout", type=int, default=30)
    parser.add_argument("--max-time", type=int, default=300)
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print summary JSON instead of text.",
    )
    parser.add_argument(
        "--fail-on-dead",
        action="store_true",
        help="Exit 1 when checked/downloaded URLs include failures.",
    )
    return parser


def _run_parallel(
    entries: list[AssetEntry],
    *,
    jobs: int,
    worker,
) -> list[AssetEntry]:
    completed: list[AssetEntry] = []
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        futures = {pool.submit(worker, entry): entry for entry in entries}
        for index, future in enumerate(as_completed(futures), 1):
            completed.append(future.result())
            if index % 50 == 0:
                print(f"  processed {index}/{len(entries)} URLs", file=sys.stderr)
    return completed


def run(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    benchmarks_root = args.benchmarks_root.resolve()
    output_dir = args.output_dir.resolve()

    entries, filtered = scan_assets(
        benchmarks_root,
        all_domains=args.all_domains,
        include_env_scripts=not args.no_env_scripts,
    )
    for entry in entries:
        entry.local_path = str(url_to_local_path(entry, output_dir))

    if args.check_links:
        entries = _run_parallel(
            entries,
            jobs=args.jobs,
            worker=lambda entry: check_one_url(
                entry,
                connect_timeout=args.connect_timeout,
                max_time=args.max_time,
                proxy=args.proxy,
            ),
        )
    elif args.download:
        entries = _run_parallel(
            entries,
            jobs=args.jobs,
            worker=lambda entry: download_one(
                entry,
                output_dir,
                connect_timeout=args.connect_timeout,
                max_time=args.max_time,
                proxy=args.proxy,
            ),
        )

    report_path = write_report(output_dir, entries, filtered)
    summary = summarize(entries, filtered)
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        _print_text_summary(summary, report_path)

    if args.fail_on_dead and summary["failed_urls"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
