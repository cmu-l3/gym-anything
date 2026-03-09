#!/usr/bin/env python3
"""
Verifier for View Visitors Dashboard task in Matomo

Verification Strategy:
1. PRIMARY: VLM-based screenshot analysis (most reliable for navigation tasks)
2. FALLBACK: URL/title analysis from exported JSON (if VLM unavailable)

This task involves UI navigation without database changes. VLM is the most reliable
method for verifying visual state of the browser.

Scoring (100 points):
- Visitors section visible: 35 points
- Overview page loaded: 30 points
- Date range shows Last 30 days: 35 points

Pass threshold: 70 points with at least visitors_section AND overview_page criteria met
"""

import sys
import os
import json
import logging
import tempfile
import re
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_string(s: str) -> str:
    """Normalize string for flexible comparison."""
    if not s:
        return ""
    return s.strip().lower()


def parse_vlm_response(response: Any) -> Dict[str, Any]:
    """
    Parse VLM response which may be a dict, JSON string, or free text.
    Returns a normalized dict with boolean values where possible.
    """
    if isinstance(response, dict):
        return response

    if isinstance(response, str):
        # Try to parse as JSON
        try:
            # Find JSON in the response (may be wrapped in markdown code blocks)
            json_match = re.search(r'\{[^{}]*\}', response, re.DOTALL)
            if json_match:
                return json.loads(json_match.group())
        except json.JSONDecodeError:
            pass

        # Parse free text response
        response_lower = response.lower()
        parsed = {
            "is_visitors_page": False,
            "is_overview_page": False,
            "date_range_last30": False,
            "confidence": "medium",
            "raw_response": response
        }

        # Check for visitors page indicators
        visitors_indicators = ['visitors', 'visitor overview', 'visitors overview', 'visits summary']
        if any(ind in response_lower for ind in visitors_indicators):
            # Check it's not just negation
            if not any(neg in response_lower for neg in ['not visitors', 'no visitors', "isn't visitors", "is not visitors"]):
                parsed["is_visitors_page"] = True

        # Check for overview page indicators
        overview_indicators = ['overview page', 'overview section', 'on the overview', 'showing overview']
        if any(ind in response_lower for ind in overview_indicators):
            parsed["is_overview_page"] = True

        # Check for date range indicators
        date_indicators = ['last 30', '30 days', '30 day', 'past 30', 'last month', 'previous 30']
        if any(ind in response_lower for ind in date_indicators):
            parsed["date_range_last30"] = True

        # Extract confidence if mentioned
        if 'high confidence' in response_lower or 'confident' in response_lower:
            parsed["confidence"] = "high"
        elif 'low confidence' in response_lower or 'uncertain' in response_lower:
            parsed["confidence"] = "low"

        return parsed

    return {}


def verify_view_visitors_dashboard(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the user navigated to Visitors Overview and changed the date range.

    PRIMARY: VLM-based screenshot analysis
    FALLBACK: URL/title analysis from exported JSON
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected = {
        "section": metadata.get('expected_section', 'visitors'),
        "subsection": metadata.get('expected_subsection', 'overview'),
        "date_range": metadata.get('expected_date_range', 'last30')
    }

    score = 0
    feedback_parts = []
    subscores = {
        "visitors_section_visible": False,
        "overview_page_loaded": False,
        "date_range_changed": False
    }
    vlm_used = False
    vlm_result_parsed = {}

    # PRIMARY: Try VLM-based verification first
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            # Copy screenshot for VLM analysis
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/task_final_screenshot.png", temp_screenshot.name)

                # Verify screenshot exists and has content
                if os.path.getsize(temp_screenshot.name) < 1000:
                    logger.warning("Screenshot file too small, may be invalid")
                else:
                    vlm_prompt = """Analyze this screenshot of a web application (should be Matomo Analytics).

Please answer these specific questions:

1. VISITORS SECTION: Is the current page showing the "Visitors" section of Matomo?
   Look for: "Visitors" highlighted in the left menu, or "Visitors Overview" in the page title/header.

2. OVERVIEW PAGE: Is this specifically the "Overview" page (not Real-time, Locations, Devices, etc.)?
   Look for: "Overview" selected in submenu, graphs showing visit trends, metrics like visits/pageviews.

3. DATE RANGE: What date range is currently selected?
   Look at the date picker (usually top-right area). Is it showing "Last 30 days" or similar 30-day range?

Respond in this exact JSON format:
{
    "is_visitors_page": true or false,
    "is_overview_page": true or false,
    "date_range_last30": true or false,
    "date_range_description": "describe what date range you see",
    "page_description": "brief description of what page/state is shown",
    "confidence": "high/medium/low"
}"""

                    vlm_result = query_vlm(prompt=vlm_prompt, images=[temp_screenshot.name])

                    if vlm_result:
                        vlm_used = True
                        vlm_result_parsed = parse_vlm_response(vlm_result)
                        logger.info(f"VLM result parsed: {vlm_result_parsed}")

                        # Score based on VLM results
                        # CRITERION 1: Visitors section (35 points)
                        if vlm_result_parsed.get('is_visitors_page'):
                            score += 35
                            subscores["visitors_section_visible"] = True
                            feedback_parts.append("VLM: Visitors section confirmed")
                        else:
                            feedback_parts.append("VLM: Visitors section NOT detected")

                        # CRITERION 2: Overview page (30 points)
                        if vlm_result_parsed.get('is_overview_page'):
                            score += 30
                            subscores["overview_page_loaded"] = True
                            feedback_parts.append("VLM: Overview page confirmed")
                        else:
                            feedback_parts.append("VLM: Overview page NOT detected")

                        # CRITERION 3: Date range (35 points)
                        if vlm_result_parsed.get('date_range_last30'):
                            score += 35
                            subscores["date_range_changed"] = True
                            date_desc = vlm_result_parsed.get('date_range_description', 'Last 30 days')
                            feedback_parts.append(f"VLM: Date range confirmed ({date_desc})")
                        else:
                            date_desc = vlm_result_parsed.get('date_range_description', 'unknown')
                            feedback_parts.append(f"VLM: Date range NOT Last 30 days (found: {date_desc})")

                        # Add confidence info
                        confidence = vlm_result_parsed.get('confidence', 'unknown')
                        feedback_parts.append(f"VLM confidence: {confidence}")

            finally:
                if os.path.exists(temp_screenshot.name):
                    os.unlink(temp_screenshot.name)

        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"VLM verification failed: {str(e)}")

    # FALLBACK: If VLM didn't provide results, use URL/title analysis
    if not vlm_used:
        feedback_parts.append("WARNING: VLM unavailable, using fallback URL/title analysis (less reliable)")

        try:
            # Copy result JSON from container
            temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            try:
                copy_from_env("/tmp/visitors_dashboard_result.json", temp_result.name)
                with open(temp_result.name, 'r') as f:
                    result = json.load(f)
            finally:
                if os.path.exists(temp_result.name):
                    os.unlink(temp_result.name)

            # Extract data from result
            window_title = result.get('window_title', '')
            current_url = result.get('current_url', '')

            logger.info(f"Fallback - Window title: {window_title}")
            logger.info(f"Fallback - Current URL: {current_url}")

            url_lower = normalize_string(current_url)
            title_lower = normalize_string(window_title)

            # CRITERION 1: Visitors section (35 points) - FALLBACK
            visitors_url_patterns = [
                'module=visitssummary',
                'module=visitorinterest',
                'module=visittime',
                'module=usercount',
                'category=general_visitors',
                'subcategory=general_overview'
            ]

            if any(pattern in url_lower for pattern in visitors_url_patterns):
                score += 30  # Slightly less than VLM score due to lower reliability
                subscores["visitors_section_visible"] = True
                feedback_parts.append("Fallback: Visitors section detected via URL")
            elif re.search(r'\bvisitor', title_lower) or re.search(r'\bvisitor', url_lower):
                score += 20  # Even lower score for title-only
                subscores["visitors_section_visible"] = True
                feedback_parts.append("Fallback: Visitors section detected in title (low confidence)")
            else:
                feedback_parts.append("Fallback: Visitors section NOT detected")

            # CRITERION 2: Overview page (30 points) - FALLBACK
            if 'action=index' in url_lower or 'subcategory=general_overview' in url_lower:
                score += 25
                subscores["overview_page_loaded"] = True
                feedback_parts.append("Fallback: Overview page detected via URL")
            elif 'overview' in title_lower:
                score += 20
                subscores["overview_page_loaded"] = True
                feedback_parts.append("Fallback: Overview page detected in title (low confidence)")
            else:
                feedback_parts.append("Fallback: Overview page NOT detected")

            # CRITERION 3: Date range (35 points) - FALLBACK
            date_range_url_patterns = [
                'period=range',
                'date=last30',
                'period=month'
            ]

            if any(pattern in url_lower for pattern in date_range_url_patterns):
                score += 25
                subscores["date_range_changed"] = True
                feedback_parts.append("Fallback: Date range detected via URL")
            elif 'last 30' in title_lower or '30 days' in title_lower:
                score += 20
                subscores["date_range_changed"] = True
                feedback_parts.append("Fallback: Date range detected in title (low confidence)")
            else:
                feedback_parts.append("Fallback: Date range NOT detected")

        except FileNotFoundError:
            logger.error("Result file not found and VLM unavailable")
            feedback_parts.append("Fallback: Export file not found")
        except Exception as e:
            logger.error(f"Fallback verification error: {e}")
            feedback_parts.append(f"Fallback error: {str(e)}")

    # Determine pass/fail
    # MANDATORY CRITERIA: Must have visitors section visible AND overview page loaded
    key_criteria_met = subscores["visitors_section_visible"] and subscores["overview_page_loaded"]
    passed = score >= 70 and key_criteria_met

    if not key_criteria_met and score >= 70:
        feedback_parts.append("Score meets threshold but mandatory criteria not met (visitors_section AND overview_page required)")

    if not key_criteria_met and score < 70:
        feedback_parts.append("Task incomplete: navigate to Visitors > Overview and set date range to Last 30 days")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "key_criteria_met": key_criteria_met,
        "verification_method": "vlm" if vlm_used else "fallback_url_title",
        "details": {
            "expected": expected,
            "vlm_result": vlm_result_parsed if vlm_used else None
        }
    }
