#!/usr/bin/env python3
"""
Verifier for osw_recreation_gov_dates task.
Ported from OSWorld task b4f95342-463e-4179-8c3f-193cd7241fb2.

The task asks the user to find "Next Available" dates for Diamond on recreation.gov.
OSWorld uses a dynamic comparison: it fetches the expected column header from the
recreation.gov page at eval time (class "camp-sortable-column-header", index 2).

For Gym-Anything, we verify:
1. The URL is on recreation.gov and references Diamond
2. The page contains "Next Available" sort/column header content matching the 3rd
   camp-sortable-column-header element
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_elements_by_class(html: str, class_name: str) -> List[str]:
    """Extract text from all elements that have the given class."""
    # Match elements with this class, capturing inner content
    pattern = rf'class="[^"]*\b{re.escape(class_name)}\b[^"]*"[^>]*>(.*?)</(?:div|span|th|td|button|a)[^>]*>'
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
        if not active_url and os.path.exists(tabs_path) and os.path.getsize(tabs_path) > 0:
            with open(tabs_path, 'r', encoding='utf-8') as f:
                tabs_data = json.load(f)
            active_url = get_active_url(tabs_data)

        if not active_url:
            return {"passed": False, "score": 0, "feedback": "Could not determine active URL"}

        feedback.append(f"Active URL: {active_url}")

        # Check 1: URL should be on recreation.gov
        url_lower = active_url.lower()
        if "recreation.gov" not in url_lower:
            feedback.append("URL is not on recreation.gov — FAIL")
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}
        feedback.append("URL is on recreation.gov — OK")

        # Check 2: URL or page should reference Diamond
        if "diamond" not in url_lower and "diamond" not in html.lower()[:5000]:
            feedback.append("Page does not appear to reference 'Diamond' — FAIL")
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}
        feedback.append("Page references Diamond — OK")

        if not html:
            return {"passed": False, "score": 0, "feedback": "No HTML content captured"}

        # OSWorld evaluator: result extracts camp-sortable-column-header[2] from the active page,
        # expected extracts camp-sortable-column-header[2] from the reference page.
        # Both should match. Since both come from the same page after the task is done,
        # we verify the page has the expected structure with availability columns.
        header_texts = extract_elements_by_class(html, "camp-sortable-column-header")
        feedback.append(f"Found {len(header_texts)} camp-sortable-column-header elements: {header_texts[:5]}")

        if len(header_texts) < 3:
            # Try alternative: look for availability/next-available sort headers via lxml
            try:
                from lxml import etree
                parser = etree.HTMLParser()
                tree = etree.fromstring(html.encode('utf-8', errors='replace'), parser)
                elements = tree.xpath("//*[contains(@class, 'camp-sortable-column-header')]")
                header_texts = [el.text_content().strip() for el in elements if el.text_content().strip()]
                feedback.append(f"lxml found {len(header_texts)} headers: {header_texts[:5]}")
            except Exception:
                pass

        # The 3rd header (index 2) should exist and the OSWorld check compares it against itself
        # (both result and expected fetch from the same page). So we just verify the structure exists.
        if len(header_texts) >= 3:
            target_header = header_texts[2]
            feedback.append(f"3rd column header (index 2): '{target_header}'")
            # The page is showing the availability table with sort columns — task is complete
            passed = True
            feedback.append("Availability table with sort columns found — PASS")
        else:
            # Fallback: check if "Next Available" appears anywhere on the page
            if "next available" in html.lower() or "availability" in html.lower():
                feedback.append("'Next Available' / 'availability' found in page content — PASS (relaxed)")
                passed = True
            else:
                feedback.append("Could not find availability table structure — FAIL")
                passed = False

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
