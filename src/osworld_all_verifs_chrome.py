from __future__ import annotations

import difflib
import json
import os
import re
import zipfile
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse


def _score(value: bool) -> float:
    return 1.0 if value else 0.0


def _normalize_text(value: Any) -> str:
    return str(value or "").strip().lower()


def _flatten_bookmark_names(data: Any) -> list[str]:
    if isinstance(data, dict):
        names = []
        if "name" in data:
            names.append(_normalize_text(data["name"]))
        for child in data.values():
            names.extend(_flatten_bookmark_names(child))
        return names
    if isinstance(data, list):
        names = []
        for item in data:
            names.extend(_flatten_bookmark_names(item))
        return names
    return []


def is_expected_active_tab(result: dict[str, Any], rules: dict[str, Any]) -> float:
    expected = rules.get("expected", {})
    url = _normalize_text(result.get("url"))
    title = _normalize_text(result.get("title"))
    expected_url = _normalize_text(expected.get("url", expected if isinstance(expected, str) else ""))
    expected_title = _normalize_text(expected.get("title"))
    ok = True
    if expected_url:
        ok = ok and expected_url in url
    if expected_title:
        ok = ok and expected_title in title
    return _score(ok)


def is_expected_active_tab_approximate(result: dict[str, Any], rules: dict[str, Any]) -> float:
    expected = rules.get("expected", {})
    actual = _normalize_text(result.get("url") or result.get("title"))
    target = _normalize_text(expected.get("url") or expected.get("title") or expected)
    if not actual or not target:
        return 0.0
    ratio = difflib.SequenceMatcher(None, actual, target).ratio()
    return 1.0 if ratio >= 0.8 or target in actual else 0.0


def is_expected_url_pattern_match(result: dict[str, Any], rules: dict[str, Any]) -> float:
    url = result.get("url", "")
    expected = rules.get("expected", {})
    pattern = expected.get("url") if isinstance(expected, dict) else expected
    if not pattern:
        return 0.0
    pattern_text = str(pattern)
    if pattern_text.startswith("^") or ".*" in pattern_text:
        return _score(bool(re.search(pattern_text, url, re.IGNORECASE)))
    return _score(pattern_text.lower() in url.lower())


def is_expected_tabs(result: dict[str, Any], rules: dict[str, Any]) -> float:
    tabs = result.get("tabs", [])
    expected = rules.get("expected", {})
    expected_tabs = expected.get("tabs", expected if isinstance(expected, list) else [])
    if not isinstance(expected_tabs, list):
        return 0.0
    normalized_tabs = [_normalize_text(tab.get("url") or tab.get("title") or tab) for tab in tabs]
    return _score(all(_normalize_text(item) in normalized_tabs for item in expected_tabs))


def is_expected_bookmarks(result: dict[str, Any], rules: dict[str, Any]) -> float:
    expected = rules.get("expected", {})
    bookmark_data = result.get("bookmarks") or result
    actual_names = _flatten_bookmark_names(bookmark_data)
    expected_items = expected.get("bookmarks", expected if isinstance(expected, list) else [])
    if isinstance(expected_items, dict):
        expected_items = list(expected_items.values())
    if not isinstance(expected_items, list):
        expected_items = [expected_items]
    return _score(all(_normalize_text(item) in actual_names for item in expected_items))


def is_expected_search_query(result: dict[str, Any], rules: dict[str, Any]) -> float:
    url = result.get("url", "")
    expected = _normalize_text((rules.get("expected", {}) or {}).get("query"))
    if not expected:
        return 0.0
    parsed = urlparse(url)
    query_text = " ".join(value for values in parse_qs(parsed.query).values() for value in values)
    return _score(expected in _normalize_text(query_text))


def is_expected_installed_extensions(result: dict[str, Any], rules: dict[str, Any]) -> float:
    extensions = {_normalize_text(item) for item in result.get("extensions", [])}
    expected = rules.get("expected", {})
    required = expected.get("extensions", expected if isinstance(expected, list) else [])
    if not isinstance(required, list):
        required = [required]
    return _score(all(_normalize_text(item) in extensions for item in required))


def is_cookie_deleted(result: dict[str, Any], rules: dict[str, Any]) -> float:
    cookies = json.dumps(result.get("cookies", result), sort_keys=True).lower()
    expected = rules.get("expected", {})
    cookie_name = _normalize_text(expected.get("cookie") or expected.get("name") or expected)
    return _score(cookie_name not in cookies)


def is_shortcut_on_desktop(result: dict[str, Any], rules: dict[str, Any]) -> float:
    if isinstance(result, dict) and "exists" in result:
        return _score(bool(result["exists"]))
    expected = _normalize_text((rules.get("expected", {}) or {}).get("name") or rules.get("expected"))
    text = json.dumps(result, sort_keys=True).lower()
    return _score(expected in text if expected else False)


def check_history_deleted(result: dict[str, Any], rules: dict[str, Any]) -> float:
    entries = json.dumps(result.get("history", result), sort_keys=True).lower()
    expected = _normalize_text((rules.get("expected", {}) or {}).get("keyword") or rules.get("expected"))
    return _score(expected not in entries)


def check_enabled_experiments(result: dict[str, Any], rules: dict[str, Any]) -> float:
    enabled = {_normalize_text(item) for item in result.get("enabled_experiments", result.get("experiments", []))}
    expected = rules.get("expected", {})
    required = expected.get("experiments", expected if isinstance(expected, list) else [])
    if not isinstance(required, list):
        required = [required]
    return _score(all(_normalize_text(item) in enabled for item in required))


def check_font_size(result: dict[str, Any], rules: dict[str, Any]) -> float:
    expected = rules.get("expected", {})
    actual = result.get("font_size") or result.get("default_font_size") or result
    target = expected.get("font_size") or expected.get("default_font_size") or expected
    try:
        return _score(int(actual) == int(target))
    except Exception:
        return _score(_normalize_text(actual) == _normalize_text(target))


def is_added_to_steam_cart(result: dict[str, Any], rules: dict[str, Any]) -> float:
    expected = rules.get("expected", {})
    item = _normalize_text(expected.get("item") or expected.get("name") or expected)
    haystack = json.dumps(result, sort_keys=True).lower()
    return _score(item in haystack)


def _file_similarity(path_a: str, path_b: str) -> float:
    file_a = Path(path_a)
    file_b = Path(path_b)
    if not file_a.exists() or not file_b.exists():
        return 0.0
    if file_a.read_bytes() == file_b.read_bytes():
        return 1.0
    size_a = max(file_a.stat().st_size, 1)
    size_b = max(file_b.stat().st_size, 1)
    ratio = min(size_a, size_b) / max(size_a, size_b)
    return 1.0 if ratio >= 0.9 else 0.0


def compare_pdfs(actual_path: str, expected_path: str) -> float:
    return _file_similarity(actual_path, expected_path)


def compare_pdf_images(actual_path: str, expected_path: str) -> float:
    return _file_similarity(actual_path, expected_path)


def compare_archive(actual_path: str, expected_path: str) -> float:
    try:
        with zipfile.ZipFile(actual_path) as actual_zip, zipfile.ZipFile(expected_path) as expected_zip:
            actual_names = sorted(actual_zip.namelist())
            expected_names = sorted(expected_zip.namelist())
            return _score(actual_names == expected_names)
    except Exception:
        return _file_similarity(actual_path, expected_path)


def compare_htmls(actual_path: str, expected_path: str) -> float:
    try:
        actual = Path(actual_path).read_text(encoding="utf-8", errors="ignore")
        expected = Path(expected_path).read_text(encoding="utf-8", errors="ignore")
        normalize = lambda text: re.sub(r"\s+", " ", text).strip().lower()
        return _score(normalize(actual) == normalize(expected))
    except Exception:
        return _file_similarity(actual_path, expected_path)


__all__ = [
    "check_enabled_experiments",
    "check_font_size",
    "check_history_deleted",
    "compare_archive",
    "compare_htmls",
    "compare_pdf_images",
    "compare_pdfs",
    "is_added_to_steam_cart",
    "is_cookie_deleted",
    "is_expected_active_tab",
    "is_expected_active_tab_approximate",
    "is_expected_bookmarks",
    "is_expected_installed_extensions",
    "is_expected_search_query",
    "is_expected_tabs",
    "is_expected_url_pattern_match",
    "is_shortcut_on_desktop",
]
