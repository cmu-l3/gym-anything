#!/usr/bin/env python3
"""
Verifier for osw_flight_mumbai_stockholm task.
Ported from OSWorld task 82bc8d6a-36eb-4d2d-8801-ef714fb1e55a.

Checks that the active tab URL contains flight search params for Mumbai→Stockholm
on next Monday (resolved at verification time).
OSWorld metric: check_direct_json_object (expect_in_result=true)
OSWorld getter: active_tab_url_parse (parse_keys: fromStation, toStation, departing→time)
OSWorld expected getter: rule_relativeTime (from="next Monday")
"""

import json
import os
import tempfile
import logging
from datetime import datetime, timedelta
from urllib.parse import urlparse, parse_qs
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
    """Apply OSWorld time format placeholders to a datetime."""
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
    """Resolve a relative time expression to an absolute date, matching OSWorld logic."""
    if now is None:
        now = datetime.now()

    if relative_time == "tomorrow":
        return now + timedelta(days=1)
    elif relative_time == "next Monday":
        days_until_monday = (6 - now.weekday()) + 1
        return now + timedelta(days=days_until_monday)
    elif relative_time == "5th next month":
        next_year = now.year + 1 if now.month == 12 else now.year
        next_month = now.month + 1 if now.month < 12 else 1
        return datetime(next_year, next_month, 5)
    elif relative_time == "10th next month":
        next_year = now.year + 1 if now.month == 12 else now.year
        next_month = now.month + 1 if now.month < 12 else 1
        return datetime(next_year, next_month, 10)
    elif relative_time == "11th next month":
        next_year = now.year + 1 if now.month == 12 else now.year
        next_month = now.month + 1 if now.month < 12 else 1
        return datetime(next_year, next_month, 11)
    elif relative_time == "this month":
        return now
    elif relative_time == "first monday eight months later":
        next_year = now.year + 1 if now.month >= 5 else now.year
        next_month = (now.month + 8) % 12
        if next_month == 0:
            next_month = 12
        temp_date = datetime(next_year, next_month, 1)
        days_to_monday = ((6 - temp_date.weekday()) + 1) % 7
        return temp_date + timedelta(days=days_to_monday)
    elif relative_time == "first monday four months later":
        next_year = now.year + 1 if now.month >= 9 else now.year
        next_month = (now.month + 4) % 12
        if next_month == 0:
            next_month = 12
        temp_date = datetime(next_year, next_month, 1)
        days_to_monday = ((6 - temp_date.weekday()) + 1) % 7
        return temp_date + timedelta(days=days_to_monday)
    elif relative_time == "next week Saturday":
        days_to_next_monday = 7 - now.weekday()
        return now + timedelta(days=days_to_next_monday + 5)
    elif relative_time == "next week Friday":
        days_to_next_monday = 7 - now.weekday()
        return now + timedelta(days=days_to_next_monday + 4)
    elif relative_time == "next week Sunday":
        days_to_next_monday = 7 - now.weekday()
        return now + timedelta(days=days_to_next_monday + 6)
    elif relative_time == "next Saturday":
        if now.weekday() < 5:
            return now + timedelta(days=5 - now.weekday())
        elif now.weekday() == 5:
            return now + timedelta(days=7)
        else:
            return now + timedelta(days=6)
    elif relative_time == "next Friday":
        if now.weekday() < 4:
            return now + timedelta(days=4 - now.weekday())
        elif now.weekday() == 4:
            return now + timedelta(days=7)
        else:
            return now + timedelta(days=(7 - now.weekday()) + 4)
    elif relative_time == "next Sunday":
        if now.weekday() < 6:
            return now + timedelta(days=6 - now.weekday())
        else:
            return now + timedelta(days=7)
    elif relative_time == "this Saturday":
        return now + timedelta(days=5 - now.weekday())
    elif relative_time == "this Sunday":
        return now + timedelta(days=6 - now.weekday())
    else:
        raise ValueError(f"Unknown relative time expression: {relative_time}")


def parse_url_params(url: str) -> Dict[str, str]:
    """Parse URL query parameters and path fragments into a flat dict."""
    parsed = urlparse(url)
    params = {}
    # Parse query string
    qs = parse_qs(parsed.query, keep_blank_values=True)
    for k, v in qs.items():
        params[k] = v[0] if len(v) == 1 else v
    # Also parse path-based params (some sites encode in path or fragment)
    if parsed.fragment:
        frag_qs = parse_qs(parsed.fragment, keep_blank_values=True)
        for k, v in frag_qs.items():
            params[k] = v[0] if len(v) == 1 else v
    return params


def get_active_url(tabs_data) -> str:
    """Extract the active tab URL from CDP /json response."""
    if not tabs_data:
        return ""
    for tab in tabs_data:
        if tab.get("type") == "page":
            return tab.get("url", "")
    if tabs_data:
        return tabs_data[0].get("url", "")
    return ""


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function available"}

    temp_dir = tempfile.mkdtemp()
    feedback = []

    try:
        # Load page content
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

        # Parse URL parameters
        url_params = parse_url_params(active_url)
        feedback.append(f"Parsed URL params: {url_params}")

        # OSWorld parse_keys: fromStation, toStation, departing (renamed to time)
        result = {}
        for key in ["fromStation", "toStation", "departing"]:
            if key in url_params:
                result[key if key != "departing" else "time"] = url_params[key]
            # Also check case-insensitive and common URL patterns
            lower_params = {k.lower(): v for k, v in url_params.items()}
            if key.lower() in lower_params and key not in result:
                result[key if key != "departing" else "time"] = lower_params[key.lower()]

        feedback.append(f"Extracted result: {result}")

        # Resolve relative time: next Monday
        now = datetime.now()
        abs_date = resolve_relative_date("next Monday", now)
        expected_time = apply_time_format("{Year}-{Month0D}-{Day0D}", abs_date)
        feedback.append(f"Resolved 'next Monday' to: {abs_date.strftime('%Y-%m-%d')} -> expected time: {expected_time}")

        # Expected values (expect_in_result mode: each expected value must be found in result)
        expected = {
            "fromStation": ["BOM"],
            "toStation": ["STO", "ARN"],
            "time": [expected_time]
        }

        # Check using expect_in_result logic (list values: any match is OK)
        all_passed = True
        for key, expected_values in expected.items():
            actual = result.get(key)
            if actual is None:
                feedback.append(f"Key '{key}' not found in result — FAIL")
                all_passed = False
                continue

            found = False
            for ev in expected_values:
                if isinstance(actual, list) and ev in actual:
                    found = True
                    break
                elif isinstance(actual, str) and ev == actual:
                    found = True
                    break
            if found:
                feedback.append(f"Key '{key}': found expected value in result — PASS")
            else:
                feedback.append(f"Key '{key}': expected one of {expected_values}, got '{actual}' — FAIL")
                all_passed = False

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
