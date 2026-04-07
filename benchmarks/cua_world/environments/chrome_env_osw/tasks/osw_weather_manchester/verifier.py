#!/usr/bin/env python3
"""
Verifier for osw_weather_manchester task.
Ported from OSWorld task 368d9ba4-203c-40c1-9fa3-da2f1430ce63.

Multi-evaluator (2 checks, implicit AND):
1. check_direct_json_object: url_dashPart extraction, relativeTime from="this month"
   Extract the second-to-last dash-separated part of the URL path.
   Expected: time="{month}-weather" (e.g. "march-weather")
2. is_expected_url_pattern_match: URL contains "/manchester/"
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime
from urllib.parse import urlparse
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MONTH_LOWER = {
    1: 'january', 2: 'february', 3: 'march', 4: 'april',
    5: 'may', 6: 'june', 7: 'july', 8: 'august',
    9: 'september', 10: 'october', 11: 'november', 12: 'december'
}


def apply_time_format(fmt: str, dt: datetime) -> str:
    result = fmt
    result = result.replace("{month}", MONTH_LOWER[dt.month])
    result = result.replace("{Year}", str(dt.year))
    result = result.replace("{Month0D}", f"{dt.month:02d}")
    result = result.replace("{Day0D}", f"{dt.day:02d}")
    result = result.replace("{DayD}", str(dt.day))
    result = result.replace("{MonthD}", str(dt.month))
    return result


def get_url_dash_part(url: str, part_index: int) -> str:
    """Extract a dash-separated part from the URL path.
    part_index: -2 means second-to-last part of the path when split by '/'.
    Then we look at that path segment (which is something like "march-weather").
    """
    parsed = urlparse(url)
    path_parts = [p for p in parsed.path.split('/') if p]
    if not path_parts:
        return ""
    try:
        segment = path_parts[part_index]
        return segment
    except IndexError:
        return ""


def get_active_url(tabs_data) -> str:
    if not tabs_data:
        return ""
    for tab in tabs_data:
        if tab.get("type") == "page":
            return tab.get("url", "")
    return tabs_data[0].get("url", "") if tabs_data else ""


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function available"}

    temp_dir = tempfile.mkdtemp()
    feedback = []

    try:
        page_path = os.path.join(temp_dir, "page_content.json")
        tabs_path = os.path.join(temp_dir, "active_tabs.json")
        try:
            copy_from_env("/tmp/page_content.json", page_path)
        except Exception:
            pass
        try:
            copy_from_env("/tmp/active_tabs.json", tabs_path)
        except Exception:
            pass

        active_url = ""
        if os.path.exists(page_path) and os.path.getsize(page_path) > 0:
            with open(page_path, 'r', encoding='utf-8') as f:
                page_data = json.load(f)
            active_url = page_data.get("url", "")
        elif os.path.exists(tabs_path) and os.path.getsize(tabs_path) > 0:
            with open(tabs_path, 'r', encoding='utf-8') as f:
                tabs_data = json.load(f)
            active_url = get_active_url(tabs_data)

        if not active_url:
            return {"passed": False, "score": 0, "feedback": "Could not determine active URL"}

        feedback.append(f"Active URL: {active_url}")

        check_results = []

        # ===== CHECK 1: check_direct_json_object (url_dashPart) =====
        # Extract second-to-last path segment (partIndex=-2)
        # URL like: https://www.accuweather.com/en/gb/manchester/M15+6/march-weather/325072
        # path_parts = ['en', 'gb', 'manchester', 'M15+6', 'march-weather', '325072']
        # partIndex -2 = 'march-weather'
        url_part = get_url_dash_part(active_url, -2)
        result1 = {"time": url_part}
        feedback.append(f"Check 1: URL dash part (index -2): '{url_part}'")

        # Resolve relative time: "this month" = current month
        now = datetime.now()
        expected_time = apply_time_format("{month}-weather", now)
        feedback.append(f"Expected time: '{expected_time}'")

        check1_passed = result1.get("time") == expected_time
        if not check1_passed:
            feedback.append(f"Check 1: expected '{expected_time}', got '{result1.get('time')}' — FAIL")
        else:
            feedback.append(f"Check 1: matched — PASS")
        check_results.append(check1_passed)

        # ===== CHECK 2: is_expected_url_pattern_match =====
        url_pattern = "/manchester/"
        check2_passed = bool(re.search(re.escape(url_pattern), active_url, re.IGNORECASE))
        feedback.append(f"Check 2 (URL pattern '{url_pattern}'): {'PASS' if check2_passed else 'FAIL'}")
        check_results.append(check2_passed)

        # Both checks must pass (implicit AND for list evaluators)
        all_passed = all(check_results)
        feedback.append(f"\nOverall: {check_results} -> {'PASS' if all_passed else 'FAIL'}")

        return {
            "passed": all_passed,
            "score": 100 if all_passed else 0,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}
    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
