#!/usr/bin/env python3
"""
Verifier for crawl_website task.

Checks that the Screaming Frog SEO Spider successfully crawled https://crawler-test.com/
Uses VLM verification to confirm actual crawl results are visible in the UI.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_crawl_website(traj, env_info, task_info):
    """
    Verify that the website crawl was performed successfully.

    Uses strict verification:
    1. Screaming Frog was running during the task
    2. Window title shows the CORRECT target URL (crawler-test.com)
    3. URL count > 0 from actual crawl data
    4. VLM verification confirms crawl results visible in UI
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_min_urls = metadata.get('expected_min_urls', 10)
    target_url = metadata.get('target_url', 'https://crawler-test.com/')

    # Extract domain from target URL for matching
    target_domain = 'crawler-test.com'
    if 'crawler-test.com' in target_url:
        target_domain = 'crawler-test'

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

    # Criterion 1: Screaming Frog was running (15 pts)
    sf_running = result.get('screaming_frog_running', False)
    if sf_running:
        score += 15
        feedback_parts.append("Screaming Frog running")
    else:
        feedback_parts.append("Screaming Frog NOT running")

    # Criterion 2: STRICT - Window title must show crawler-test.com (25 pts)
    # This proves the CORRECT URL was crawled, not just any URL
    window_info = result.get('window_info', '').lower()
    crawl_detected = result.get('crawl_detected', False)
    correct_url_crawled = target_domain.lower() in window_info

    if correct_url_crawled:
        score += 25
        feedback_parts.append(f"Correct URL crawled: {target_domain} found in window title")
    elif crawl_detected:
        # Some crawl detected but NOT the correct URL - partial credit
        score += 5
        feedback_parts.append(f"Crawl detected but wrong URL (expected {target_domain})")
    else:
        feedback_parts.append(f"No crawl of {target_domain} detected in window title")

    # Criterion 3: URLs were actually found (35 pts)
    # Must have actual url_count > 0, no fabrication
    # Also verify export content contains crawler-test.com URLs
    url_count = result.get('url_count', 0)
    crawl_status = result.get('crawl_status', '')
    has_export_results = result.get('has_export_results', False)

    # Additional check: Try to verify export content contains crawler-test.com
    export_content_verified = False
    if has_export_results:
        try:
            export_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            try:
                # Try to copy the latest export file
                copy_from_env("/tmp/exported_crawl_report.csv", export_temp.name)
                with open(export_temp.name, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().lower()
                    if 'crawler-test' in content:
                        export_content_verified = True
            except Exception:
                pass  # Export may not exist, that's OK
            finally:
                if os.path.exists(export_temp.name):
                    os.unlink(export_temp.name)
        except Exception:
            pass

    if url_count >= expected_min_urls:
        if export_content_verified:
            score += 35
            feedback_parts.append(f"Found {url_count} URLs from crawler-test.com (verified)")
        else:
            score += 30  # Slightly less if content not verified
            feedback_parts.append(f"Found {url_count} URLs (>= {expected_min_urls})")
    elif url_count > 0:
        # Partial credit based on actual count
        partial = int(30 * (url_count / expected_min_urls))
        score += partial
        feedback_parts.append(f"Found {url_count} URLs (partial, expected >= {expected_min_urls})")
    elif crawl_status == 'complete' and correct_url_crawled:
        # Crawl completed for correct URL, URL count may not be extracted
        # Give partial credit only
        score += 15
        feedback_parts.append(f"Crawl completed for {target_domain}, URL count not extracted")
    else:
        feedback_parts.append(f"No URLs found (expected >= {expected_min_urls})")

    # Criterion 4: VLM verification of final screenshot (25 pts)
    # Check that crawl results are actually visible
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    episode_dir = env_info.get('episode_dir', '')

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_prompt = """Analyze this screenshot of Screaming Frog SEO Spider.

Answer these questions with YES or NO:
1. Is the Screaming Frog application visible?
2. Does the window title or URL bar show "crawler-test" or "crawler-test.com"?
3. Are there URLs listed in the main results panel (not empty)?
4. Does it look like a crawl has been completed (URLs visible, not loading)?

Based on your answers, rate confidence (0-100) that a crawl of crawler-test.com was successfully completed."""

                # query_vlm returns dict with: success, response, parsed, error
                vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot)

                # Safety check: ensure vlm_result is a dict
                if not isinstance(vlm_result, dict):
                    feedback_parts.append(f"VLM returned unexpected type: {type(vlm_result).__name__}")
                elif vlm_result.get('success'):
                    # Parse VLM response for confidence
                    response_text = vlm_result.get('response', '')
                    if not isinstance(response_text, str):
                        response_text = str(response_text) if response_text else ''
                    vlm_response_lower = response_text.lower()

                    # Count positive indicators
                    positive_count = 0
                    if 'yes' in vlm_response_lower and 'crawler-test' in vlm_response_lower:
                        positive_count += 1
                    if 'urls' in vlm_response_lower and ('visible' in vlm_response_lower or 'listed' in vlm_response_lower):
                        positive_count += 1
                    if 'completed' in vlm_response_lower or 'complete' in vlm_response_lower:
                        positive_count += 1
                    if 'crawl' in vlm_response_lower and 'success' in vlm_response_lower:
                        positive_count += 1

                    # Award points based on positive indicators
                    if positive_count >= 3:
                        vlm_score = 25
                        feedback_parts.append("VLM confirms crawl results visible")
                    elif positive_count >= 2:
                        vlm_score = 15
                        feedback_parts.append("VLM partially confirms crawl results")
                    elif positive_count >= 1:
                        vlm_score = 5
                        feedback_parts.append("VLM shows some crawl activity")
                    else:
                        feedback_parts.append("VLM could not confirm crawl results")
                else:
                    error_msg = vlm_result.get('error', 'unknown') if isinstance(vlm_result, dict) else 'invalid response'
                    feedback_parts.append(f"VLM query failed: {str(error_msg)[:40]}")
        except Exception as e:
            feedback_parts.append(f"VLM verification failed: {str(e)[:50]}")
    else:
        # No VLM available - can still pass without it but score capped
        feedback_parts.append("VLM verification not available")

    score += vlm_score

    # STRICT passing criteria:
    # Must have: SF running AND correct URL crawled AND (url_count > 0 OR VLM confirms)
    passed = (
        sf_running and
        correct_url_crawled and
        (url_count > 0 or vlm_score >= 15)
    )

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": {
            "screaming_frog_running": sf_running,
            "correct_url_crawled": correct_url_crawled,
            "url_count": url_count,
            "vlm_score": vlm_score
        }
    }
