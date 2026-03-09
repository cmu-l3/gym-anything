#!/usr/bin/env python3
"""
Verifier for find_broken_links task.

Checks that the user found broken links (404 errors) on the real test website
https://crawler-test.com/links/broken_links
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_find_broken_links(traj, env_info, task_info):
    """
    Verify that broken links were found on the test website.

    STRICT verification:
    1. Screaming Frog was used (running)
    2. The CORRECT URL (crawler-test.com/links/broken_links) was crawled
    3. Response codes were checked (via tab or export)
    4. Broken links (404s) were actually identified
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_status_code = metadata.get('expected_status_code', 404)
    target_url = metadata.get('target_url', 'https://crawler-test.com/links/broken_links')

    feedback_parts = []
    score = 0

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criterion 1: Screaming Frog was running (20 pts)
    sf_running = result.get('screaming_frog_running', False)
    if sf_running:
        score += 20
        feedback_parts.append("Screaming Frog active")
    else:
        feedback_parts.append("Screaming Frog not running")

    # Criterion 2: STRICT - Correct URL was crawled (25 pts)
    # Must show crawler-test in window title
    window_info = result.get('window_info', '').lower()
    crawl_performed = result.get('crawl_performed', False)
    correct_url_crawled = 'crawler-test' in window_info

    if correct_url_crawled:
        score += 25
        feedback_parts.append("Correct URL (crawler-test.com) crawled")
    elif crawl_performed:
        # Some crawl but wrong URL
        score += 5
        feedback_parts.append("Crawl performed but wrong URL")
    else:
        feedback_parts.append("No crawl of crawler-test.com detected")

    # Criterion 3: Response codes were checked (25 pts)
    response_codes_checked = result.get('response_codes_checked', False)
    if response_codes_checked:
        score += 25
        feedback_parts.append("Response codes checked")
    else:
        feedback_parts.append("Response codes not checked")

    # Criterion 4: Broken link was actually found (30 pts)
    broken_link_found = result.get('broken_link_found', False)
    broken_in_export = result.get('broken_link_in_export', False)

    if broken_link_found or broken_in_export:
        score += 30
        feedback_parts.append(f"404 broken links identified")
    else:
        feedback_parts.append(f"No 404 broken links found")

    # VLM verification if available
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_prompt = """Analyze this screenshot of Screaming Frog SEO Spider.

Answer YES or NO:
1. Is Screaming Frog visible?
2. Does the window show "crawler-test" in the title or URL area?
3. Is the "Response Codes" tab selected OR are 404/Client Error items visible?
4. Are there any rows showing 404 status or "Client Error" in the results?

Rate confidence (0-100) that broken links (404s) from crawler-test.com were found."""

                # query_vlm returns dict with: success, response, parsed, error
                vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot)

                # Safety check: ensure vlm_result is a dict
                if not isinstance(vlm_result, dict):
                    feedback_parts.append(f"VLM returned unexpected type: {type(vlm_result).__name__}")
                elif vlm_result.get('success'):
                    response_text = vlm_result.get('response', '')
                    if not isinstance(response_text, str):
                        response_text = str(response_text) if response_text else ''
                    vlm_lower = response_text.lower()

                    # Check for positive indicators
                    if '404' in vlm_lower or 'client error' in vlm_lower:
                        vlm_score = 10
                        feedback_parts.append("VLM confirms 404s visible")
                    elif 'crawler-test' in vlm_lower and 'yes' in vlm_lower:
                        vlm_score = 5
                        feedback_parts.append("VLM confirms crawler-test.com crawled")
                else:
                    error_msg = vlm_result.get('error', 'unknown') if isinstance(vlm_result, dict) else 'invalid response'
                    feedback_parts.append(f"VLM query failed: {str(error_msg)[:30]}")
        except Exception as e:
            feedback_parts.append(f"VLM check failed: {str(e)[:30]}")

    score += vlm_score

    # STRICT pass criteria:
    # Must have: SF running AND correct URL AND (response codes checked OR broken link found)
    passed = (
        sf_running and
        correct_url_crawled and
        (response_codes_checked or broken_link_found)
    )

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": {
            "screaming_frog_running": sf_running,
            "correct_url_crawled": correct_url_crawled,
            "response_codes_checked": response_codes_checked,
            "broken_link_found": broken_link_found,
            "vlm_score": vlm_score
        }
    }
