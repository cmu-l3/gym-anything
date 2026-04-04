#!/usr/bin/env python3
"""Verifier for visit_onion_service task.

Verifies that the agent successfully visited DuckDuckGo's onion service
and performed a search for 'Tor Project'.

Includes VLM-based verification to prevent clipboard/history manipulation attacks.
"""

import json
import logging
import os
import re
import tempfile
import base64
from urllib.parse import urlparse, parse_qs
from PIL import Image
from io import BytesIO

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_screenshot_with_vlm(screenshot_path: str, search_query: str) -> dict:
    """
    Use VLM to verify the screenshot shows DuckDuckGo search results for the query.

    This prevents adversarial attacks where an agent manipulates history/clipboard
    without actually visiting the onion page.

    Args:
        screenshot_path: Path to the task_end.png screenshot
        search_query: Expected search query (e.g., 'Tor Project')

    Returns:
        dict with 'verified' (bool), 'confidence' (float), 'details' (str)
    """
    try:
        if not os.path.exists(screenshot_path):
            return {
                'verified': None,
                'confidence': 0.0,
                'details': 'Screenshot not found for VLM verification'
            }

        # Encode image for VLM
        image = Image.open(screenshot_path)
        image = image.resize((1280, 720))
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        image_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')

        # Use openai for VLM verification
        # SECURITY: API credentials from environment variables
        import openai

        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')

        if not vlm_api_key:
            logger.warning("VLM_API_KEY not set in environment, VLM verification will be skipped")
            return {
                'verified': None,
                'confidence': 0.0,
                'details': 'VLM_API_KEY environment variable not set'
            }

        client = openai.OpenAI(
            base_url=vlm_base_url,
            api_key=vlm_api_key
        )

        verification_prompt = f"""Analyze this screenshot and verify it shows DuckDuckGo search results.

I need to verify that:
1. The browser is showing DuckDuckGo (look for the DuckDuckGo logo or branding)
2. The URL bar shows a .onion address (specifically duckduckgo...onion)
3. Search results are displayed for the query "{search_query}"

Look for:
- DuckDuckGo's distinctive duck logo or "DuckDuckGo" text
- A .onion URL in the address bar
- Search results related to "{search_query}"

Please respond with:
- VERIFIED: YES if you can clearly see DuckDuckGo search results for "{search_query}"
- VERIFIED: NO if this is NOT DuckDuckGo or doesn't show search results
- VERIFIED: UNCERTAIN if you cannot determine

Also provide:
- CONFIDENCE: A number from 0 to 100 indicating how confident you are
- DETAILS: A brief description of what you see

Format your response exactly as:
VERIFIED: [YES/NO/UNCERTAIN]
CONFIDENCE: [0-100]
DETAILS: [description]"""

        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": verification_prompt},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/png;base64,{image_base64}"}
                    }
                ]
            }
        ]

        response = client.chat.completions.create(
            model='databricks-claude-sonnet-4-5',
            messages=messages,
            max_tokens=500,
            temperature=0.0
        )

        response_text = response.choices[0].message.content
        if isinstance(response_text, list):
            response_text = response_text[-1].get('text', '') if isinstance(response_text[-1], dict) else str(response_text[-1])

        # Parse response
        verified = None
        confidence = 0.0
        details = response_text

        lines = response_text.strip().split('\n')
        for line in lines:
            line_upper = line.upper().strip()
            if line_upper.startswith('VERIFIED:'):
                value = line_upper.replace('VERIFIED:', '').strip()
                if value == 'YES':
                    verified = True
                elif value == 'NO':
                    verified = False
                else:
                    verified = None
            elif line_upper.startswith('CONFIDENCE:'):
                try:
                    confidence = float(line_upper.replace('CONFIDENCE:', '').strip()) / 100.0
                except:
                    confidence = 0.5
            elif line_upper.startswith('DETAILS:'):
                details = line.replace('DETAILS:', '').strip()

        logger.info(f"VLM verification result: verified={verified}, confidence={confidence}")
        logger.info(f"VLM details: {details}")

        return {
            'verified': verified,
            'confidence': confidence,
            'details': details
        }

    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return {
            'verified': None,
            'confidence': 0.0,
            'details': f'VLM verification error: {str(e)}'
        }


def verify_visit_onion_service(traj, env_info, task_info):
    """
    Verify that the agent visited DuckDuckGo's onion service and searched.

    Criteria:
    1. Tor Browser is running (10 points)
    2. Onion URL was visited (30 points - primary criterion)
    3. URL matches expected DuckDuckGo onion pattern (20 points)
    4. Search was performed with expected query (25 points)
    5. New history entries were added (15 points)

    Args:
        traj: Trajectory data from the agent
        env_info: Environment information including copy_from_env function
        task_info: Task metadata including expected values

    Returns:
        dict: {"passed": bool, "score": float (0-100), "feedback": str}
    """
    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available from framework"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_url_pattern = metadata.get('expected_url_pattern', 'duckduckgo.*onion')
    expected_title_pattern = metadata.get('expected_title_pattern', 'DuckDuckGo')
    search_query = metadata.get('search_query', 'Tor Project')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []

    # Log result for debugging
    logger.info(f"Task result: {json.dumps(result, indent=2)}")

    # Criterion 1: Tor Browser is running (10 points)
    tor_browser_running = result.get('tor_browser_running', False)
    if tor_browser_running:
        score += 10
        criteria_met += 1
        feedback_parts.append("Tor Browser is running")
    else:
        feedback_parts.append("Tor Browser is NOT running")

    # Criterion 2: Onion URL was visited (30 points - primary criterion)
    onion_url_visited = result.get('onion_url_visited', False)
    visited_url = result.get('visited_url', '')
    page_title = result.get('page_title', '')

    if onion_url_visited:
        score += 30
        criteria_met += 1
        feedback_parts.append(f"Onion service visited: {visited_url[:80]}...")
    else:
        if result.get('onion_already_visited', False):
            feedback_parts.append("Onion service was previously visited - task may need fresh start")
        else:
            feedback_parts.append("Onion service was NOT visited")

    # Criterion 3: URL matches expected DuckDuckGo onion pattern (20 points)
    # STRICT: Must match the exact DuckDuckGo onion address to prevent spoofing
    url_matches = False
    EXACT_ONION_DOMAIN = "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion"
    if visited_url:
        try:
            # First try exact domain match (more secure)
            if EXACT_ONION_DOMAIN in visited_url.lower():
                score += 20
                criteria_met += 1
                url_matches = True
                feedback_parts.append(f"URL matches exact DuckDuckGo onion domain")
            # Fall back to pattern from metadata only if it's strict enough
            elif expected_url_pattern and len(expected_url_pattern) > 30:
                if re.search(expected_url_pattern, visited_url, re.IGNORECASE):
                    score += 20
                    criteria_met += 1
                    url_matches = True
                    feedback_parts.append(f"URL matches DuckDuckGo onion pattern")
                else:
                    feedback_parts.append(f"URL doesn't match expected pattern: {expected_url_pattern}")
            else:
                feedback_parts.append(f"URL '{visited_url[:50]}...' doesn't match exact DuckDuckGo onion domain")
        except Exception as e:
            logger.warning(f"URL pattern matching failed: {e}")
            feedback_parts.append(f"URL pattern validation failed: {str(e)}")

    # Criterion 4: Search was performed with expected query (25 points)
    # STRICT: Must contain ALL search terms (e.g., "Tor" AND "Project")
    search_performed = result.get('search_performed', False)
    search_query_found = False

    if visited_url:
        try:
            parsed = urlparse(visited_url)
            query_params = parse_qs(parsed.query)

            # Check for search query parameter (DuckDuckGo uses 'q')
            q_param = query_params.get('q', [''])[0]
            if q_param:
                # Check if the search query contains ALL expected terms
                search_terms = search_query.lower().split()
                found_terms = sum(1 for term in search_terms if term in q_param.lower())

                # STRICT: Require ALL search terms to be present
                if found_terms == len(search_terms):
                    score += 25
                    criteria_met += 1
                    search_query_found = True
                    feedback_parts.append(f"Search performed with exact query: {q_param}")
                elif found_terms > 0:
                    # Partial credit only if at least one term found
                    partial_score = int(10 * (found_terms / len(search_terms)))
                    score += partial_score
                    feedback_parts.append(f"Partial search match: found {found_terms}/{len(search_terms)} terms in '{q_param}' (expected: '{search_query}')")
                else:
                    # Minimal credit for any search
                    score += 5
                    feedback_parts.append(f"Search performed but query '{q_param}' doesn't contain expected terms '{search_query}'")
            elif search_performed:
                score += 5
                feedback_parts.append("Search detected but query not verified")
            else:
                feedback_parts.append("No search query found in URL")
        except Exception as e:
            logger.warning(f"Query parsing failed: {e}")
            if search_performed:
                score += 5
                feedback_parts.append("Search detected but query parsing failed")

    # Criterion 5: New history entries were added (15 points)
    new_history = result.get('new_history_entries', 0)
    if new_history > 0 and onion_url_visited:
        score += 15
        criteria_met += 1
        feedback_parts.append(f"{new_history} new history entries added")
    else:
        initial = result.get('initial_history_count', 0)
        current = result.get('current_history_count', 0)
        feedback_parts.append(f"No new history entries (initial: {initial}, current: {current})")

    # ANTI-ADVERSARIAL CHECK: Timestamp verification
    # Ensures the visit happened AFTER the task started, preventing insertion attacks
    visit_after_task_start = result.get('visit_after_task_start', False)
    visit_timestamp = result.get('visit_timestamp', 0)
    task_start_timestamp = result.get('task_start_timestamp', 0)

    if onion_url_visited:
        if visit_timestamp > 0 and task_start_timestamp > 0:
            if visit_after_task_start:
                feedback_parts.append(f"Timestamp verified: visit occurred after task start")
            else:
                # Visit timestamp is before task start - possible adversarial attack
                feedback_parts.append(f"WARNING: Visit timestamp ({visit_timestamp}) is before task start ({task_start_timestamp})")
                # Only penalize if we're relying on history (not window title fallback)
                if new_history > 0:
                    score = max(0, score - 15)
                    feedback_parts.append("Score reduced due to timestamp mismatch")
        else:
            # No timestamp data available (might be using window title fallback)
            if result.get('tor_window_title', ''):
                feedback_parts.append("Timestamp verification skipped (using window title fallback)")

    # MANDATORY ANTI-ADVERSARIAL CHECK: VLM-based screenshot verification
    # This prevents attacks where the agent manipulates history/clipboard without visiting the page
    vlm_verified = None
    vlm_confidence = 0.0
    vlm_score = 0

    # Copy the task_end screenshot for VLM verification
    try:
        screenshot_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        copy_from_env("/tmp/task_end.png", screenshot_temp.name)

        if os.path.exists(screenshot_temp.name) and os.path.getsize(screenshot_temp.name) > 0:
            vlm_result = verify_screenshot_with_vlm(screenshot_temp.name, search_query)
            vlm_verified = vlm_result.get('verified', None)
            vlm_confidence = vlm_result.get('confidence', 0.0)
            vlm_details = vlm_result.get('details', '')

            if vlm_verified is True:
                # VLM confirmed DuckDuckGo search results page
                vlm_score = 10
                feedback_parts.append(f"VLM VERIFIED: Screenshot shows DuckDuckGo search results (confidence: {vlm_confidence:.0%})")
            elif vlm_verified is False:
                # VLM says this is NOT DuckDuckGo search results - FAIL
                feedback_parts.append(f"VLM REJECTED: Screenshot does not show DuckDuckGo search results ({vlm_details})")
                feedback_parts.append("SECURITY: Possible history/clipboard manipulation detected")
                # Heavy penalty
                score = max(0, score - 40)
            else:
                # VLM uncertain - allow pass but note it
                feedback_parts.append(f"VLM UNCERTAIN: Could not verify screenshot ({vlm_details})")
        else:
            feedback_parts.append("VLM verification failed: Screenshot unavailable or empty")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM verification error: {str(e)}")
    finally:
        if 'screenshot_temp' in locals() and os.path.exists(screenshot_temp.name):
            os.unlink(screenshot_temp.name)

    # Add VLM score to total
    score += vlm_score

    # Determine pass/fail
    # Primary criteria: Onion URL must be visited AND URL must match pattern
    # Pass threshold: score >= 65 (requires onion visit + url match + some other criteria)
    # If VLM explicitly failed, task MUST fail
    passed = onion_url_visited and url_matches and score >= 65

    if vlm_verified is False:
        passed = False
        feedback_parts.append("Task FAILED: VLM verification rejected - screenshot does not show expected page")

    # Build final feedback
    feedback = " | ".join(feedback_parts)

    logger.info(f"Verification result - Passed: {passed}, Score: {score}, Criteria: {criteria_met}/{total_criteria}")

    return {
        "passed": passed,
        "score": min(score, 110),  # Cap at 110 (100 base + 10 VLM bonus)
        "feedback": feedback,
        "subscores": {
            "tor_browser_running": 10 if tor_browser_running else 0,
            "onion_visited": 30 if onion_url_visited else 0,
            "url_matches": 20 if url_matches else 0,
            "search_performed": 25 if search_query_found else (10 if search_performed else 0),
            "new_history": 15 if (new_history > 0 and onion_url_visited) else 0,
            "vlm_verification": vlm_score
        }
    }


if __name__ == "__main__":
    # For testing the verifier locally with mock data
    # This should NOT be used for actual verification
    print("This verifier should be run through the gym_anything framework.")
    print("Use: env.verify() after completing the task interactively.")
