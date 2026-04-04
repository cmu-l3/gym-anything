#!/usr/bin/env python3
"""
Verifier for Add Website task in Matomo

Verification Strategy:
1. PRIMARY: Database verification via exported JSON
2. Check that website was created with correct name, URL, timezone, currency

Scoring (100 points):
- Website exists with correct name: 40 points
- URL correct: 20 points
- Timezone correct: 10 points
- Currency correct: 10 points
- Created during task execution (anti-gaming): 20 points

Pass threshold: 70 points with website record existing
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


def normalize_url(url: str) -> str:
    """Normalize URL for comparison (remove trailing slashes, etc)."""
    if not url:
        return ""
    url = url.strip().lower()
    # Remove trailing slash
    url = url.rstrip('/')
    # Remove protocol for comparison
    url = re.sub(r'^https?://', '', url)
    return url


def verify_add_website(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a new website was added to Matomo with correct information.

    Uses copy_from_env to retrieve exported results from the container.
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
        "site_name": metadata.get('expected_site_name', 'TechBlog Demo'),
        "site_url": metadata.get('expected_site_url', 'https://techblog-demo.example.com'),
        "timezone": metadata.get('expected_timezone', 'UTC'),
        "currency": metadata.get('expected_currency', 'USD')
    }

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_website_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "site_exists": False,
            "url_correct": False,
            "timezone_correct": False,
            "currency_correct": False,
            "created_during_task": False
        }

        # Extract data from result
        site_found = result.get('site_found', False)
        created_during_task = result.get('created_during_task', False)
        site = result.get('site', {})
        initial_count = result.get('initial_site_count', 0)
        current_count = result.get('current_site_count', 0)
        task_start = result.get('task_start_timestamp', 0)

        logger.info(f"Result: found={site_found}, created_during_task={created_during_task}")
        logger.info(f"Site data: {site}")

        # CRITERION 1: Site exists with correct name (40 points)
        if site_found:
            actual_name = site.get('name', '')

            if normalize_string(actual_name) == normalize_string(expected["site_name"]):
                score += 40
                subscores["site_exists"] = True
                feedback_parts.append(f"Site '{expected['site_name']}' found in database")
            else:
                feedback_parts.append(f"Name mismatch: expected '{expected['site_name']}', got '{actual_name}'")
        else:
            feedback_parts.append(f"Site '{expected['site_name']}' NOT found in database")

            # Check if any new sites were added
            if current_count > initial_count:
                feedback_parts.append(f"Note: {current_count - initial_count} new site(s) added but not with expected name")
            else:
                feedback_parts.append("No new sites were added to the database")

            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: URL correct (20 points)
        actual_url = site.get('main_url', '')
        additional_urls = site.get('additional_urls', '')
        all_urls = actual_url + ',' + additional_urls if additional_urls else actual_url

        expected_url_normalized = normalize_url(expected["site_url"])
        url_found = False

        for url in all_urls.split(','):
            if normalize_url(url) == expected_url_normalized:
                url_found = True
                break

        if url_found:
            score += 20
            subscores["url_correct"] = True
            feedback_parts.append(f"URL correct: {expected['site_url']}")
        else:
            feedback_parts.append(f"URL incorrect: expected '{expected['site_url']}', got '{actual_url}'")

        # CRITERION 3: Timezone correct (10 points)
        # Accept UTC-equivalent timezones (Europe/London, Atlantic/Reykjavik, etc.)
        actual_timezone = site.get('timezone', '')
        acceptable_timezones = metadata.get('acceptable_timezones', [expected["timezone"]])
        timezone_match = normalize_string(actual_timezone) == normalize_string(expected["timezone"])
        if not timezone_match:
            # Check acceptable alternatives
            for tz in acceptable_timezones:
                if normalize_string(actual_timezone) == normalize_string(tz):
                    timezone_match = True
                    break

        if timezone_match:
            score += 10
            subscores["timezone_correct"] = True
            feedback_parts.append(f"Timezone correct: {actual_timezone}")
        else:
            feedback_parts.append(f"Timezone incorrect: expected '{expected['timezone']}' (or equivalent), got '{actual_timezone}'")

        # CRITERION 4: Currency correct (10 points)
        actual_currency = site.get('currency', '')
        if normalize_string(actual_currency) == normalize_string(expected["currency"]):
            score += 10
            subscores["currency_correct"] = True
            feedback_parts.append(f"Currency correct: {expected['currency']}")
        else:
            feedback_parts.append(f"Currency incorrect: expected '{expected['currency']}', got '{actual_currency}'")

        # CRITERION 5: Created during task (anti-gaming) (20 points)
        if created_during_task:
            score += 20
            subscores["created_during_task"] = True
            feedback_parts.append(f"Site created during task execution")
        else:
            site_ts = site.get('created_timestamp', 0)
            feedback_parts.append(f"Site may have existed before task (created_ts={site_ts}, task_start={task_start})")

        # Determine pass/fail
        # Must have: site exists (40) + created during task (20) = 60 minimum
        # Plus at least 10 more points from other criteria for 70 total
        key_criteria_met = subscores["site_exists"] and subscores["created_during_task"]
        passed = score >= 70 and key_criteria_met

        # If site exists but not created during task, cap score and fail
        if subscores["site_exists"] and not subscores["created_during_task"]:
            feedback_parts.append("Anti-gaming check failed: site record may not have been created during this task")
            passed = False

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "expected": expected,
                "actual": site,
                "initial_count": initial_count,
                "current_count": current_count
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found in container")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result file not found - task may not have completed properly",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }
