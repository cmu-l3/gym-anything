#!/usr/bin/env python3
"""
Verifier for osw_flight_dublin_vienna task.
Ported from OSWorld task f79439ad-3ee8-4f99-a518-0eb60e5652b0.

Checks that Ryanair URL contains correct flight params: DUB→VIE, 2 adults, one-way,
on 10th next month (resolved at verification time).
OSWorld metric: check_direct_json_object
OSWorld getter: active_tab_url_parse
OSWorld expected getter: rule_relativeTime (from="10th next month")
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


def apply_time_format(fmt: str, dt: datetime) -> str:
    result = fmt
    result = result.replace("{DoW}", DAY_OF_WEEK[dt.weekday()])
    result = result.replace("{Month}", MONTH_ABBR[dt.month])
    result = result.replace("{DayD}", str(dt.day))
    result = result.replace("{Year}", str(dt.year))
    result = result.replace("{Month0D}", f"{dt.month:02d}")
    result = result.replace("{Day0D}", f"{dt.day:02d}")
    result = result.replace("{MonthD}", str(dt.month))
    return result


def resolve_relative_date(relative_time: str, now: datetime = None) -> datetime:
    if now is None:
        now = datetime.now()
    if relative_time == "10th next month":
        next_year = now.year + 1 if now.month == 12 else now.year
        next_month = now.month + 1 if now.month < 12 else 1
        return datetime(next_year, next_month, 10)
    else:
        raise ValueError(f"Unknown relative time: {relative_time}")


def parse_url_params(url: str) -> Dict[str, str]:
    parsed = urlparse(url)
    params = {}
    qs = parse_qs(parsed.query, keep_blank_values=True)
    for k, v in qs.items():
        params[k] = v[0] if len(v) == 1 else v
    if parsed.fragment:
        frag_qs = parse_qs(parsed.fragment, keep_blank_values=True)
        for k, v in frag_qs.items():
            params[k] = v[0] if len(v) == 1 else v
    return params


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

        # Parse URL parameters
        url_params = parse_url_params(active_url)
        feedback.append(f"Parsed URL params: {url_params}")

        # OSWorld parse_keys with rename: tpStartDate → time
        result = {}
        parse_keys = ["originIata", "destinationIata", "tpAdults", "tpTeens",
                       "tpChildren", "tpStartDate", "isReturn"]
        rename = {"tpStartDate": "time"}
        for key in parse_keys:
            if key in url_params:
                mapped_key = rename.get(key, key)
                result[mapped_key] = url_params[key]

        feedback.append(f"Extracted result: {result}")

        # Resolve relative time
        now = datetime.now()
        abs_date = resolve_relative_date("10th next month", now)
        # Format: {Year}-{Month0D}-{DayD} (note: DayD = no zero-padding)
        expected_time = apply_time_format("{Year}-{Month0D}-{DayD}", abs_date)
        feedback.append(f"Resolved '10th next month' -> expected time: {expected_time}")

        expected = {
            "originIata": "DUB",
            "destinationIata": "VIE",
            "tpAdults": "2",
            "tpTeens": "0",
            "tpChildren": "0",
            "time": expected_time,
            "isReturn": "false"
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
