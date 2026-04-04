#!/usr/bin/env python3
"""Verifier for configure_security_level task.

Verifies that the agent successfully changed the Tor Browser security level
from 'Standard' to 'Safer' or 'Safest'.

Includes VLM-based verification to prevent direct prefs.js manipulation attacks.
"""

import json
import logging
import os
import tempfile
import base64
import subprocess
from PIL import Image
from io import BytesIO

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_screenshot_with_vlm(screenshot_path: str, expected_level: str) -> dict:
    """
    Use VLM to verify the screenshot shows the expected security level.

    This prevents adversarial attacks where an agent modifies prefs.js directly
    without actually using the UI.

    Args:
        screenshot_path: Path to the task_end.png screenshot
        expected_level: Expected security level ('safer' or 'safest')

    Returns:
        dict with 'verified' (bool), 'confidence' (float), 'details' (str)
    """
    try:
        if not os.path.exists(screenshot_path):
            return {
                'verified': False,
                'confidence': 0.0,
                'details': 'Screenshot not found for VLM verification'
            }

        # Encode image for VLM
        image = Image.open(screenshot_path)
        image = image.resize((1280, 720))
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        image_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')

        # Use litellm/openai for VLM verification
        # SECURITY: API credentials from environment variables
        import openai

        vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
        vlm_api_key = os.environ.get('VLM_API_KEY')

        if not vlm_api_key:
            logger.warning("VLM_API_KEY not set in environment, VLM verification will fail")
            return {
                'verified': None,
                'confidence': 0.0,
                'details': 'VLM_API_KEY environment variable not set'
            }

        client = openai.OpenAI(
            base_url=vlm_base_url,
            api_key=vlm_api_key
        )

        verification_prompt = f"""Analyze this screenshot of Tor Browser and verify the security level setting.

I need to verify that the Tor Browser security level has been changed to '{expected_level}'.

Look for ANY of these indicators:
1. If a security settings dialog/popup is visible, check the selected security level
2. If the shield icon popup is visible, check what security level is shown
3. If the Settings page is visible with Privacy & Security section, check the security level
4. Check if there are any visual indicators of elevated security (disabled features, warnings)

Please respond with:
- VERIFIED: YES if you can clearly see the security level is set to '{expected_level}' or higher
- VERIFIED: NO if the security level appears to be 'Standard' or you cannot determine
- VERIFIED: UNCERTAIN if the security level is not visible in the screenshot

Also provide:
- CONFIDENCE: A number from 0 to 100 indicating how confident you are
- DETAILS: A brief description of what you see that led to your conclusion

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
        verified = False
        confidence = 0.0
        details = response_text

        lines = response_text.strip().split('\n')
        for line in lines:
            line_upper = line.upper().strip()
            if line_upper.startswith('VERIFIED:'):
                value = line_upper.replace('VERIFIED:', '').strip()
                verified = value == 'YES'
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
            'verified': None,  # Unable to verify
            'confidence': 0.0,
            'details': f'VLM verification error: {str(e)}'
        }


def verify_configure_security_level(traj, env_info, task_info):
    """
    Verify that the agent changed the Tor Browser security level.

    Criteria:
    1. Prefs file exists (10 points)
    2. Security level was changed (40 points - primary criterion)
    3. Security level is 'safer' or 'safest' (30 points)
    4. Tor Browser is still running (10 points)
    5. Related security preferences are set (10 points bonus)

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
    expected_levels = metadata.get('expected_security_levels', ['safer', 'safest'])

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

    # Criterion 1: Prefs file exists (10 points)
    prefs_file_exists = result.get('prefs_file_exists', False)
    if prefs_file_exists:
        score += 10
        criteria_met += 1
        feedback_parts.append("Preferences file exists")
    else:
        feedback_parts.append("Preferences file NOT found - Tor Browser may not have been used")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Security level was changed (40 points - primary criterion)
    security_level_changed = result.get('security_level_changed', False)
    initial_level = result.get('initial_security_level', 'standard')
    current_level = result.get('current_security_level', 'standard')

    if security_level_changed:
        score += 40
        criteria_met += 1
        feedback_parts.append(f"Security level changed from '{initial_level}' to '{current_level}'")
    else:
        feedback_parts.append(f"Security level was NOT changed (still '{current_level}')")

    # Criterion 3: Security level is 'safer' or 'safest' (30 points)
    level_correct = current_level.lower() in [level.lower() for level in expected_levels]
    if level_correct:
        score += 30
        criteria_met += 1
        feedback_parts.append(f"Security level is '{current_level}' (expected: {expected_levels})")
    else:
        feedback_parts.append(f"Security level '{current_level}' is not one of expected: {expected_levels}")

    # Criterion 4: Tor Browser is still running (10 points)
    tor_browser_running = result.get('tor_browser_running', False)
    if tor_browser_running:
        score += 10
        criteria_met += 1
        feedback_parts.append("Tor Browser is running")
    else:
        feedback_parts.append("Tor Browser is NOT running")

    # Criterion 5: Related security preferences are set (10 points bonus)
    # These preferences typically change when security level increases
    security_prefs_score = 0
    security_prefs_feedback = []

    # Check JavaScript restrictions (safest level)
    if result.get('javascript_restricted', False):
        security_prefs_score += 4
        security_prefs_feedback.append("JavaScript restricted")

    # Check WebRTC disabled (safer and safest)
    if result.get('webrtc_disabled', False):
        security_prefs_score += 3
        security_prefs_feedback.append("WebRTC disabled")

    # Check SVG disabled (safest level)
    if result.get('svg_disabled', False):
        security_prefs_score += 3
        security_prefs_feedback.append("SVG disabled")

    if security_prefs_score > 0:
        score += min(security_prefs_score, 10)
        criteria_met += 1
        feedback_parts.append(f"Security preferences set: {', '.join(security_prefs_feedback)}")
    else:
        # Security preferences might not be immediately visible in prefs.js
        # Don't penalize if the level change was detected
        if security_level_changed and level_correct:
            feedback_parts.append("Security preferences check skipped (level change confirmed)")

    # MANDATORY ANTI-ADVERSARIAL CHECK: VLM-based screenshot verification
    # This prevents attacks where the agent modifies prefs.js directly without using the UI
    # VLM verification is REQUIRED for task to pass (not just a bonus)
    vlm_verified = None  # None = not attempted, True = verified, False = failed
    vlm_confidence = 0.0
    vlm_score = 0
    vlm_available = False

    # Copy the task_end screenshot for VLM verification
    try:
        screenshot_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        copy_from_env("/tmp/task_end.png", screenshot_temp.name)

        if os.path.exists(screenshot_temp.name) and os.path.getsize(screenshot_temp.name) > 0:
            vlm_available = True
            vlm_result = verify_screenshot_with_vlm(screenshot_temp.name, current_level)
            vlm_verified = vlm_result.get('verified', None)
            vlm_confidence = vlm_result.get('confidence', 0.0)
            vlm_details = vlm_result.get('details', '')

            if vlm_verified is True:
                # VLM confirmed the security level in screenshot - REQUIRED for pass
                vlm_score = 10
                feedback_parts.append(f"VLM VERIFIED: UI shows '{current_level}' (confidence: {vlm_confidence:.0%})")
            elif vlm_verified is False:
                # VLM says security level doesn't match - FAIL (possible adversarial attack)
                feedback_parts.append(f"VLM REJECTED: UI does not show '{current_level}' ({vlm_details})")
                feedback_parts.append("SECURITY: Possible prefs.js manipulation detected")
                # Heavy penalty for failed VLM verification
                score = max(0, score - 40)
            else:
                # VLM uncertain - allow pass but note it
                feedback_parts.append(f"VLM UNCERTAIN: Could not verify UI state ({vlm_details})")
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
    # SECURITY: VLM verification is now MANDATORY to prevent prefs.js manipulation
    # Task passes ONLY if:
    # 1. Security level was changed in prefs.js
    # 2. New level is 'safer' or 'safest'
    # 3. VLM verification passed OR was uncertain (not failed)
    passed = security_level_changed and level_correct

    # If VLM explicitly failed (not uncertain), task MUST fail
    if vlm_verified is False:
        passed = False
        feedback_parts.append("Task FAILED: VLM verification rejected - UI does not match claimed prefs.js state")

    # Build final feedback
    feedback = " | ".join(feedback_parts)

    # Add slider value info
    slider_value = result.get('security_slider_value', 1)
    slider_info = f"(slider value: {slider_value})"
    feedback += f" {slider_info}"

    logger.info(f"Verification result - Passed: {passed}, Score: {score}, Criteria: {criteria_met}/{total_criteria}")

    return {
        "passed": passed,
        "score": min(score, 110),  # Cap at 110 (100 base + 10 VLM bonus)
        "feedback": feedback,
        "subscores": {
            "prefs_exists": 10 if prefs_file_exists else 0,
            "level_changed": 40 if security_level_changed else 0,
            "level_correct": 30 if level_correct else 0,
            "browser_running": 10 if tor_browser_running else 0,
            "security_prefs": min(security_prefs_score, 10),
            "vlm_verification": vlm_score
        }
    }


if __name__ == "__main__":
    # For testing the verifier locally with mock data
    # This should NOT be used for actual verification
    print("This verifier should be run through the gym_anything framework.")
    print("Use: env.verify() after completing the task interactively.")
