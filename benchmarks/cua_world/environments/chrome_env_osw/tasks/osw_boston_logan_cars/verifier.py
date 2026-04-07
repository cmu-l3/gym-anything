#!/usr/bin/env python3
"""
Verifier for osw_boston_logan_cars task.
Ported from OSWorld task 47543840-672a-467d-80df-8f7c3b9788c9.

Multi-evaluator (conj=AND, 3 checks):
1. is_expected_url_pattern_match: URL contains "reservation#/vehicles"
2. check_direct_json_object: HTML class-based parse, location + dates (relativeTime from/to)
3. check_direct_json_object: HTML xpath parse, rank = "Number of Seats (High to Low)"
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List

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
    elif relative_time == "11th next month":
        next_year = now.year + 1 if now.month == 12 else now.year
        next_month = now.month + 1 if now.month < 12 else 1
        return datetime(next_year, next_month, 11)
    else:
        raise ValueError(f"Unknown relative time: {relative_time}")


def extract_multi_class_texts(html: str, class_name: str) -> List[str]:
    """Extract text from elements with the given class."""
    pattern = rf'class="[^"]*{re.escape(class_name)}[^"]*"[^>]*>(.*?)</[^>]+>'
    matches = re.findall(pattern, html, re.DOTALL)
    results = []
    for m in matches:
        text = re.sub(r'<[^>]+>', '', m).strip()
        results.append(text)
    return results


def extract_by_xpath_approx(html: str, xpath: str) -> str:
    """Approximate xpath extraction using regex on the HTML.
    For budget.com sort dropdown link text extraction."""
    try:
        from lxml import etree
        parser = etree.HTMLParser()
        tree = etree.fromstring(html.encode('utf-8', errors='replace'), parser)
        elements = tree.xpath(xpath)
        if elements:
            if hasattr(elements[0], 'text_content'):
                return elements[0].text_content().strip()
            return str(elements[0]).strip()
    except Exception:
        pass
    # Fallback: try to find sort text in HTML
    sort_pattern = r'Number of Seats \(High to Low\)'
    if re.search(sort_pattern, html):
        return "Number of Seats (High to Low)"
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

        html = ""
        active_url = ""
        if os.path.exists(page_path) and os.path.getsize(page_path) > 0:
            with open(page_path, 'r', encoding='utf-8') as f:
                page_data = json.load(f)
            html = page_data.get("html", "")
            active_url = page_data.get("url", "")
        if not active_url and os.path.exists(tabs_path) and os.path.getsize(tabs_path) > 0:
            with open(tabs_path, 'r', encoding='utf-8') as f:
                tabs_data = json.load(f)
            active_url = get_active_url(tabs_data)

        if not active_url:
            return {"passed": False, "score": 0, "feedback": "Could not determine active URL"}

        feedback.append(f"Active URL: {active_url}")

        check_results = []

        # ===== CHECK 1: is_expected_url_pattern_match =====
        # URL must contain "reservation#/vehicles"
        url_pattern = "reservation#/vehicles"
        check1_passed = url_pattern in active_url
        feedback.append(f"Check 1 (URL pattern '{url_pattern}'): {'PASS' if check1_passed else 'FAIL'}")
        check_results.append(check1_passed)

        # ===== CHECK 2: check_direct_json_object with relativeTime =====
        if html:
            result2 = {}

            # class_multiObject: location-info → 0: start_location, 1: end_location
            location_texts = extract_multi_class_texts(html, "location-info")
            if len(location_texts) > 0:
                result2["start_location"] = location_texts[0]
            if len(location_texts) > 1:
                result2["end_location"] = location_texts[1]

            # class_multiObject: day-time-info → 0: from, 1: to
            day_time_texts = extract_multi_class_texts(html, "day-time-info")
            if len(day_time_texts) > 0:
                result2["from"] = day_time_texts[0]
            if len(day_time_texts) > 1:
                result2["to"] = day_time_texts[1]

            feedback.append(f"Check 2 extracted: {result2}")

            # Resolve relative times
            now = datetime.now()
            from_date = resolve_relative_date("10th next month", now)
            to_date = resolve_relative_date("11th next month", now)

            expected_from = apply_time_format("{DoW}, {Month} {Day0D}, 12:00 PM", from_date)
            expected_to = apply_time_format("{DoW}, {Month} {Day0D}, 12:00 PM", to_date)

            # Expected values - location strings contain whitespace/newlines so we check key content
            check2_passed = True

            # Check start_location contains "Boston Logan" and "BOS"
            start_loc = result2.get("start_location", "")
            if "Boston Logan" not in start_loc or "BOS" not in start_loc:
                feedback.append(f"Check 2: start_location missing 'Boston Logan' or 'BOS': '{start_loc[:80]}...' — FAIL")
                check2_passed = False
            else:
                feedback.append(f"Check 2: start_location contains Boston Logan + BOS — PASS")

            # Check end_location contains "Boston Logan" and "BOS"
            end_loc = result2.get("end_location", "")
            if "Boston Logan" not in end_loc or "BOS" not in end_loc:
                feedback.append(f"Check 2: end_location missing 'Boston Logan' or 'BOS': '{end_loc[:80]}...' — FAIL")
                check2_passed = False
            else:
                feedback.append(f"Check 2: end_location contains Boston Logan + BOS — PASS")

            # Check from date
            actual_from = result2.get("from", "")
            if expected_from != actual_from:
                feedback.append(f"Check 2: from expected '{expected_from}', got '{actual_from}' — FAIL")
                check2_passed = False
            else:
                feedback.append(f"Check 2: from date matched — PASS")

            # Check to date
            actual_to = result2.get("to", "")
            if expected_to != actual_to:
                feedback.append(f"Check 2: to expected '{expected_to}', got '{actual_to}' — FAIL")
                check2_passed = False
            else:
                feedback.append(f"Check 2: to date matched — PASS")

            check_results.append(check2_passed)
        else:
            feedback.append("Check 2: No HTML content — FAIL")
            check_results.append(False)

        # ===== CHECK 3: check_direct_json_object (xpath for rank) =====
        if html:
            xpath_expr = "/html/body/div[6]/div[2]/div[1]/div/div/div[2]/section[1]/div[1]/form/div[1]/div[1]/div[2]/div/a"
            rank_text = extract_by_xpath_approx(html, xpath_expr)
            feedback.append(f"Check 3 rank text: '{rank_text}'")

            expected_rank = "Number of Seats (High to Low)"
            check3_passed = rank_text == expected_rank
            if not check3_passed:
                feedback.append(f"Check 3: expected '{expected_rank}', got '{rank_text}' — FAIL")
            else:
                feedback.append(f"Check 3: rank matched — PASS")
            check_results.append(check3_passed)
        else:
            feedback.append("Check 3: No HTML content — FAIL")
            check_results.append(False)

        # conj="and": ALL checks must pass
        all_passed = all(check_results)
        feedback.append(f"\nOverall (AND): {check_results} -> {'PASS' if all_passed else 'FAIL'}")

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
