#!/usr/bin/env python3
"""
Verifier for osw_flight_seattle_nyc task.
Ported from OSWorld task 6c4c23a1-42a4-43cc-9db1-2f86ff3738cc.

Checks that Delta.com page shows SEA→NYC flight results for 5th next month, Miles tab active.
OSWorld metric: check_direct_json_object
OSWorld getter: active_tab_html_parse (class-based)
OSWorld expected getter: rule_relativeTime (from="5th next month")
Expected: start=SEA, end=NYC, time="{DoW}, {Month} {Day0D}, {Year}", category=Miles
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime, timedelta
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DAY_OF_WEEK = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
MONTH_ABBR = {1: 'Jan', 2: 'Feb', 3: 'Mar', 4: 'Apr', 5: 'May', 6: 'Jun',
              7: 'Jul', 8: 'Aug', 9: 'Sep', 10: 'Oct', 11: 'Nov', 12: 'Dec'}
MONTH_FULL = {1: 'January', 2: 'February', 3: 'March', 4: 'April', 5: 'May', 6: 'June',
              7: 'July', 8: 'August', 9: 'September', 10: 'October', 11: 'November', 12: 'December'}
MONTH_LOWER = {k: v.lower() for k, v in MONTH_FULL.items()}


def apply_time_format(fmt: str, dt: datetime) -> str:
    result = fmt
    result = result.replace("{DoW}", DAY_OF_WEEK[dt.weekday()])
    result = result.replace("{Month}", MONTH_ABBR[dt.month])
    result = result.replace("{DayD}", str(dt.day))
    result = result.replace("{Year}", str(dt.year))
    result = result.replace("{Month0D}", f"{dt.month:02d}")
    result = result.replace("{month}", MONTH_LOWER[dt.month])
    result = result.replace("{MonthFull}", MONTH_FULL[dt.month])
    result = result.replace("{Day0D}", f"{dt.day:02d}")
    result = result.replace("{MonthD}", str(dt.month))
    return result


def resolve_relative_date(relative_time: str, now: datetime = None) -> datetime:
    if now is None:
        now = datetime.now()
    if relative_time == "5th next month":
        next_year = now.year + 1 if now.month == 12 else now.year
        next_month = now.month + 1 if now.month < 12 else 1
        return datetime(next_year, next_month, 5)
    elif relative_time == "tomorrow":
        return now + timedelta(days=1)
    elif relative_time == "next Monday":
        return now + timedelta(days=(6 - now.weekday()) + 1)
    else:
        raise ValueError(f"Unknown relative time: {relative_time}")


def extract_text_by_class(html: str, class_name: str) -> str:
    """Extract text content from elements with given class name."""
    pattern = rf'class="[^"]*{re.escape(class_name)}[^"]*"[^>]*>(.*?)</[^>]+>'
    matches = re.findall(pattern, html, re.DOTALL)
    if matches:
        # Strip HTML tags from match
        text = re.sub(r'<[^>]+>', '', matches[0]).strip()
        return text
    return ""


def extract_multi_class_children(html: str, class_name: str) -> list:
    """Extract text from multiple elements with the given class."""
    pattern = rf'class="[^"]*{re.escape(class_name)}[^"]*"[^>]*>(.*?)</[^>]+>'
    matches = re.findall(pattern, html, re.DOTALL)
    results = []
    for m in matches:
        text = re.sub(r'<[^>]+>', '', m).strip()
        if text:
            results.append(text)
    return results


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

        html = ""
        active_url = ""
        if os.path.exists(page_path) and os.path.getsize(page_path) > 0:
            with open(page_path, 'r', encoding='utf-8') as f:
                page_data = json.load(f)
            html = page_data.get("html", "")
            active_url = page_data.get("url", "")

        if not html:
            return {"passed": False, "score": 0, "feedback": "No HTML content captured"}

        feedback.append(f"Active URL: {active_url}")
        feedback.append(f"HTML length: {len(html)}")

        # Extract values from HTML using class names (OSWorld class_singleObject + class_multiObject_child)
        result = {}

        # class_singleObject: mach-flight-context-info__wrapper--date → time
        time_text = extract_text_by_class(html, "mach-flight-context-info__wrapper--date")
        if time_text:
            result["time"] = time_text

        # class_singleObject: mach-global-tabs-small__wrapper__tab--active → category
        category_text = extract_text_by_class(html, "mach-global-tabs-small__wrapper__tab--active")
        if category_text:
            result["category"] = category_text

        # class_multiObject_child: mach-flight-context-info__wrapper__info--separator
        # 0 → start, 1 → end
        separator_texts = extract_multi_class_children(html, "mach-flight-context-info__wrapper__info--separator")
        if len(separator_texts) > 0:
            result["start"] = separator_texts[0]
        if len(separator_texts) > 1:
            result["end"] = separator_texts[1]

        feedback.append(f"Extracted result: {result}")

        # Resolve relative time
        now = datetime.now()
        abs_date = resolve_relative_date("5th next month", now)
        expected_time = apply_time_format("{DoW}, {Month} {Day0D}, {Year}", abs_date)
        feedback.append(f"Resolved '5th next month' -> expected time: {expected_time}")

        expected = {
            "start": "SEA",
            "end": "NYC",
            "time": expected_time,
            "category": "Miles"
        }

        # check_direct_json_object: exact match per key
        all_passed = True
        for key, expected_value in expected.items():
            actual_value = result.get(key)
            if actual_value is None:
                feedback.append(f"Key '{key}': not found in result — FAIL")
                all_passed = False
                continue
            if expected_value != actual_value:
                feedback.append(f"Key '{key}': expected '{expected_value}', got '{actual_value}' — FAIL")
                all_passed = False
            else:
                feedback.append(f"Key '{key}': matched '{expected_value}' — PASS")

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
