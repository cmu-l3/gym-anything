#!/usr/bin/env python3
"""
Verifier for osw_nyc_hotel_tripadvisor task.
Ported from OSWorld task b7895e80-f4d1-4648-bee0-4eb45a6f1fa8.

Multi-evaluator (conj=OR, 2 options):
Option 1: xpath parse, relativeTime from="next week Saturday" to="next week Sunday", timezone=America/New_York
  Expected: from="{DoW}, {Month} {Day0D}", to="{DoW}, {Month} {Day0D}",
            city="New York City Hotels", adult="Rooms/Guests1 Room, 2 Guests",
            rank="Price (low to high)"
Option 2: xpath parse, relativeTime from="next week Friday" to="next week Sunday", timezone=America/New_York
  Expected: from="Check In{DoW}, {Month} {Day0D}", to="Check Out{DoW}, {Month} {Day0D}",
            city/adult/rank same
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
    if relative_time == "next week Saturday":
        days_to_next_monday = 7 - now.weekday()
        return now + timedelta(days=days_to_next_monday + 5)
    elif relative_time == "next week Friday":
        days_to_next_monday = 7 - now.weekday()
        return now + timedelta(days=days_to_next_monday + 4)
    elif relative_time == "next week Sunday":
        days_to_next_monday = 7 - now.weekday()
        return now + timedelta(days=days_to_next_monday + 6)
    else:
        raise ValueError(f"Unknown relative time: {relative_time}")


def extract_by_xpath(html: str, xpath: str) -> str:
    """Extract text using lxml xpath, with regex fallback."""
    try:
        from lxml import etree
        parser = etree.HTMLParser()
        tree = etree.fromstring(html.encode('utf-8', errors='replace'), parser)
        elements = tree.xpath(xpath)
        if elements:
            if hasattr(elements[0], 'text_content'):
                return elements[0].text_content().strip()
            return str(elements[0]).strip()
    except Exception as e:
        logger.warning(f"lxml xpath failed: {e}")
    return ""


def get_active_url(tabs_data) -> str:
    if not tabs_data:
        return ""
    for tab in tabs_data:
        if tab.get("type") == "page":
            return tab.get("url", "")
    return tabs_data[0].get("url", "") if tabs_data else ""


def try_option(html: str, xpaths: Dict[str, str], expected: Dict[str, str], feedback: list, option_name: str) -> bool:
    """Try one evaluation option (xpath extraction + comparison)."""
    result = {}
    for xpath_expr, key in xpaths.items():
        value = extract_by_xpath(html, xpath_expr)
        if value:
            result[key] = value

    feedback.append(f"  {option_name} extracted: {result}")

    passed = True
    for key, expected_value in expected.items():
        actual_value = result.get(key)
        if actual_value is None:
            feedback.append(f"  {option_name} key '{key}': not found — FAIL")
            passed = False
            continue
        if expected_value != actual_value:
            feedback.append(f"  {option_name} key '{key}': expected '{expected_value}', got '{actual_value}' — FAIL")
            passed = False
        else:
            feedback.append(f"  {option_name} key '{key}': matched — PASS")

    return passed


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

        # Use America/New_York timezone for date resolution
        try:
            import pytz
            tz = pytz.timezone("America/New_York")
            now = datetime.now(tz)
        except ImportError:
            now = datetime.now()

        # ===== OPTION 1: Saturday → Sunday =====
        feedback.append("Option 1 (Sat→Sun):")
        sat_date = resolve_relative_date("next week Saturday", now)
        sun_date = resolve_relative_date("next week Sunday", now)

        xpaths_1 = {
            "//button[@data-automation='checkin']//div[contains(@class,'Wh')]//span": "from",
            "//button[@data-automation='checkout']//div[contains(@class,'Wh')]//span": "to",
            "//h2[@data-automation='header_geo_title']": "city",
            "//button[@data-automation='roomsandguests']//div[contains(@class,'Wh')]": "adult",
            "//button[contains(@aria-label,'PRICE_LOW_TO_HIGH: Price (low to high)') or contains(@aria-label,'PRICE')]//div[contains(@class,'biGQs') and contains(@class,'SewaP')]": "rank"
        }

        expected_1 = {
            "from": apply_time_format("{DoW}, {Month} {Day0D}", sat_date),
            "to": apply_time_format("{DoW}, {Month} {Day0D}", sun_date),
            "city": "New York City Hotels",
            "adult": "Rooms/Guests1 Room, 2 Guests",
            "rank": "Price (low to high)"
        }

        option1_passed = try_option(html, xpaths_1, expected_1, feedback, "Option 1")

        # ===== OPTION 2: Friday → Sunday =====
        feedback.append("Option 2 (Fri→Sun):")
        fri_date = resolve_relative_date("next week Friday", now)
        # Sunday is same as option 1

        xpaths_2 = {
            "//button[@data-automation='checkin']//div[contains(@class,'Wh')]": "from",
            "//button[@data-automation='checkout']//div[contains(@class,'Wh')]": "to",
            "//h2[@data-automation='header_geo_title']": "city",
            "//button[@data-automation='roomsandguests']//div[contains(@class,'Wh')]": "adult",
            "//button[contains(@aria-label,'PRICE_LOW_TO_HIGH: Price (low to high)') or contains(@aria-label,'PRICE')]//div[contains(@class,'biGQs') and contains(@class,'SewaP')]": "rank"
        }

        expected_2 = {
            "from": apply_time_format("Check In{DoW}, {Month} {Day0D}", fri_date),
            "to": apply_time_format("Check Out{DoW}, {Month} {Day0D}", sun_date),
            "city": "New York City Hotels",
            "adult": "Rooms/Guests1 Room, 2 Guests",
            "rank": "Price (low to high)"
        }

        option2_passed = try_option(html, xpaths_2, expected_2, feedback, "Option 2")

        # conj="or": ANY option passing is sufficient
        passed = option1_passed or option2_passed
        feedback.append(f"\nOverall (OR): Option1={option1_passed}, Option2={option2_passed} -> {'PASS' if passed else 'FAIL'}")

        return {
            "passed": passed,
            "score": 100 if passed else 0,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}
    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
