#!/usr/bin/env python3
"""
Verifier for osw_mbta_appointment task.
Ported from OSWorld task da46d875-6b82-4681-9284-653b0c7ae241.

Multi-evaluator (conj=AND, 3 checks):
1. is_expected_url_pattern_match: URL contains "book/CharlieCardStoreAppointments@mbta.com/"
2. check_direct_json_object: HTML class-based parse for appointment content + time
   relativeTime from="first monday eight months later"
   Expected: content="Apply for Transportation Access Pass (TAP) CharlieCard non-auto approval"
             time="{MonthFull} {Day0D}, 10:15 AM"
3. check_direct_json_object: HTML input parse for name + email
   Expected: name="James Smith", mail="james.smith@gmail.com"
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
MONTH_FULL = {1: 'January', 2: 'February', 3: 'March', 4: 'April', 5: 'May', 6: 'June',
              7: 'July', 8: 'August', 9: 'September', 10: 'October', 11: 'November', 12: 'December'}


def apply_time_format(fmt: str, dt: datetime) -> str:
    result = fmt
    result = result.replace("{DoW}", DAY_OF_WEEK[dt.weekday()])
    result = result.replace("{Month}", MONTH_ABBR[dt.month])
    result = result.replace("{DayD}", str(dt.day))
    result = result.replace("{Year}", str(dt.year))
    result = result.replace("{Month0D}", f"{dt.month:02d}")
    result = result.replace("{month}", MONTH_FULL[dt.month].lower())
    result = result.replace("{MonthFull}", MONTH_FULL[dt.month])
    result = result.replace("{Day0D}", f"{dt.day:02d}")
    result = result.replace("{MonthD}", str(dt.month))
    return result


def resolve_relative_date(relative_time: str, now: datetime = None) -> datetime:
    if now is None:
        now = datetime.now()
    if relative_time == "first monday eight months later":
        next_year = now.year + 1 if now.month >= 5 else now.year
        next_month = (now.month + 8) % 12
        if next_month == 0:
            next_month = 12
        temp_date = datetime(next_year, next_month, 1)
        days_to_monday = ((6 - temp_date.weekday()) + 1) % 7
        return temp_date + timedelta(days=days_to_monday)
    else:
        raise ValueError(f"Unknown relative time: {relative_time}")


def extract_multi_class_children(html: str, class_name: str) -> List[str]:
    """Extract text from elements with given class (direct children)."""
    pattern = rf'class="[^"]*\b{re.escape(class_name)}\b[^"]*"[^>]*>(.*?)</[^>]+>'
    matches = re.findall(pattern, html, re.DOTALL)
    results = []
    for m in matches:
        text = re.sub(r'<[^>]+>', '', m).strip()
        if text:
            results.append(text)
    return results


def extract_input_by_xpath(html: str, xpath: str) -> str:
    """Extract input value using lxml xpath."""
    try:
        from lxml import etree
        parser = etree.HTMLParser()
        tree = etree.fromstring(html.encode('utf-8', errors='replace'), parser)
        elements = tree.xpath(xpath)
        if elements:
            el = elements[0]
            # For input elements, get the value attribute
            if hasattr(el, 'get'):
                val = el.get('value', '')
                if val:
                    return val
            if hasattr(el, 'text_content'):
                return el.text_content().strip()
            return str(el).strip()
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
        url_pattern = "book/CharlieCardStoreAppointments@mbta.com/"
        check1_passed = url_pattern in active_url
        feedback.append(f"Check 1 (URL pattern): {'PASS' if check1_passed else 'FAIL'}")
        if not check1_passed:
            feedback.append(f"  Expected URL to contain '{url_pattern}'")
        check_results.append(check1_passed)

        # ===== CHECK 2: check_direct_json_object (class_multiObject_only_child HAZ16) =====
        if html:
            result2 = {}

            # class_multiObject_only_child: HAZ16 → 0: content, 1: time
            haz_texts = extract_multi_class_children(html, "HAZ16")
            feedback.append(f"Check 2: Found {len(haz_texts)} HAZ16 elements: {haz_texts[:3]}")

            if len(haz_texts) > 0:
                result2["content"] = haz_texts[0]
            if len(haz_texts) > 1:
                result2["time"] = haz_texts[1]

            # If regex didn't find it, try lxml
            if not result2:
                try:
                    from lxml import etree
                    parser = etree.HTMLParser()
                    tree = etree.fromstring(html.encode('utf-8', errors='replace'), parser)
                    elements = tree.xpath("//*[contains(@class, 'HAZ16')]")
                    for i, el in enumerate(elements):
                        text = el.text_content().strip()
                        if i == 0:
                            result2["content"] = text
                        elif i == 1:
                            result2["time"] = text
                    feedback.append(f"Check 2 lxml: {result2}")
                except Exception:
                    pass

            # Resolve relative time
            now = datetime.now()
            abs_date = resolve_relative_date("first monday eight months later", now)
            expected_time = apply_time_format("{MonthFull} {Day0D}, 10:15 AM", abs_date)
            feedback.append(f"Resolved 'first monday eight months later' -> {abs_date.strftime('%Y-%m-%d')} -> expected time: '{expected_time}'")

            expected2 = {
                "content": "Apply for Transportation Access Pass (TAP) CharlieCard non-auto approval",
                "time": expected_time
            }

            check2_passed = True
            for key, expected_value in expected2.items():
                actual_value = result2.get(key)
                if actual_value is None:
                    feedback.append(f"  Check 2 key '{key}': not found — FAIL")
                    check2_passed = False
                    continue
                if expected_value != actual_value:
                    feedback.append(f"  Check 2 key '{key}': expected '{expected_value}', got '{actual_value}' — FAIL")
                    check2_passed = False
                else:
                    feedback.append(f"  Check 2 key '{key}': matched — PASS")
            check_results.append(check2_passed)
        else:
            feedback.append("Check 2: No HTML — FAIL")
            check_results.append(False)

        # ===== CHECK 3: check_direct_json_object (input fields for name + email) =====
        if html:
            result3 = {}

            name_xpath = "/html/body/div[2]/div/form/div[7]/div/div/div[1]/input[1]"
            mail_xpath = "/html/body/div[2]/div/form/div[7]/div/div/div[1]/input[2]"

            result3["name"] = extract_input_by_xpath(html, name_xpath)
            result3["mail"] = extract_input_by_xpath(html, mail_xpath)

            # Fallback: try to find input values by common patterns
            if not result3["name"]:
                # Look for input with value "James Smith"
                name_match = re.search(r'value="(James Smith)"', html)
                if name_match:
                    result3["name"] = name_match.group(1)
            if not result3["mail"]:
                mail_match = re.search(r'value="(james\.smith@gmail\.com)"', html)
                if mail_match:
                    result3["mail"] = mail_match.group(1)

            feedback.append(f"Check 3 extracted: {result3}")

            expected3 = {
                "name": "James Smith",
                "mail": "james.smith@gmail.com"
            }

            check3_passed = True
            for key, expected_value in expected3.items():
                actual_value = result3.get(key)
                if actual_value is None or actual_value == "":
                    feedback.append(f"  Check 3 key '{key}': not found — FAIL")
                    check3_passed = False
                    continue
                if expected_value != actual_value:
                    feedback.append(f"  Check 3 key '{key}': expected '{expected_value}', got '{actual_value}' — FAIL")
                    check3_passed = False
                else:
                    feedback.append(f"  Check 3 key '{key}': matched — PASS")
            check_results.append(check3_passed)
        else:
            feedback.append("Check 3: No HTML — FAIL")
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
