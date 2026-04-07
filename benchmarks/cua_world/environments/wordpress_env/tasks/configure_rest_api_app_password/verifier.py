#!/usr/bin/env python3
"""
Verifier for configure_rest_api_app_password task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic Checks (70 points):
  1. File Existence & Format (10 pts) - Credentials file exists and formatted `admin:XXX`.
  2. Database State: Application Password Exists (10 pts) - Checked via WP DB.
  3. Database State: Post Exists & Is Private (15 pts) - Verified post state.
  4. Integration Test: API Auth Success (35 pts) - The credentials MUST work
     against the live WordPress REST API to fetch the private configuration post,
     proving the full headless integration loop functions properly.

VLM Checks (30 points):
  5. Process Verification (20 pts): Frames show agent creating App Password and Post.
  6. Final State Verification (10 pts): Shows success or file saving.

Pass Threshold: 70 points AND API authentication MUST succeed.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring WordPress API settings.

For success, the agent should:
1. Navigate to Users -> Profile in WordPress admin.
2. Generate an "Application Password" named "MobileApp_iOS".
3. Navigate to Posts -> Add New.
4. Create a post titled "App Configuration Endpoint".
5. Paste a JSON payload into the editor.
6. Set post visibility to "Private" and Publish/Update.

Assess:
1. APP_PASSWORD_GENERATED: Is there evidence of generating/viewing the Application Password?
2. POST_EDITOR_USED: Did the agent use the WordPress post editor?
3. PRIVACY_CONFIGURED: Did the agent interact with the post visibility settings (setting to Private)?
4. MEANINGFUL_PROGRESSION: Do the frames show sequential progress through these stages?

Respond in JSON format:
{
    "app_password_generated": true/false,
    "post_editor_used": true/false,
    "privacy_configured": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress API configuration task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface or a text editor visible?
2. SUCCESS_INDICATORS: Are there success messages like "Post updated" or is the credentials text file saved successfully?
3. ERROR_INDICATORS: Are there any error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_rest_api_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/rest_api_task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found."}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. File Exists & Format (10 pts)
    if result.get('file_exists', False):
        cred_string = result.get('cred_string', '')
        if cred_string.startswith('admin:'):
            score += 10
            feedback_parts.append("Credentials file found & formatted correctly")
        else:
            score += 5
            feedback_parts.append("Credentials file found but format is incorrect")
    else:
        feedback_parts.append("Credentials file NOT found")

    # 2. Database: App Password Exists (10 pts)
    if result.get('app_pwd_exists', False):
        score += 10
        feedback_parts.append("App Password registered in DB")
    else:
        feedback_parts.append("App Password NOT found in DB")

    # 3. Database: Post Exists & Private (15 pts)
    post_id = result.get('post_id')
    post_status = result.get('post_status')
    if post_id and str(post_id).strip():
        if post_status == 'private':
            score += 15
            feedback_parts.append("Private post exists in DB")
        else:
            score += 5
            feedback_parts.append(f"Post exists but status is '{post_status}' (expected 'private')")
    else:
        feedback_parts.append("Target post NOT found in DB")

    # 4. Integration Test: API Auth Success (35 pts)
    api_http_code = result.get('api_http_code', 0)
    api_success = False

    if api_http_code == 200:
        api_response_str = result.get('api_response', '[]')
        try:
            api_data = json.loads(api_response_str)
            if isinstance(api_data, list) and len(api_data) > 0:
                # Search for our expected post in the response
                for post in api_data:
                    title = post.get('title', {}).get('rendered', '')
                    if 'App Configuration Endpoint' in title:
                        content = post.get('content', {}).get('rendered', '')
                        if '"app_version"' in content and '2.4.1' in content:
                            api_success = True
                            break
        except json.JSONDecodeError:
            pass

        if api_success:
            score += 35
            feedback_parts.append("API Integration Test Passed (200 OK + Valid JSON Payload)")
        else:
            score += 15
            feedback_parts.append("API authenticated (200 OK), but correct JSON payload not found in response")
    elif api_http_code in [401, 403]:
        feedback_parts.append(f"API Integration Test Failed (Auth Denied: {api_http_code})")
    else:
        feedback_parts.append(f"API Integration Test Failed (HTTP {api_http_code})")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    query_vlm = env_info.get('query_vlm')
    vlm_executed = False

    if query_vlm:
        try:
            # Trajectory
            frames = sample_trajectory_frames(traj, n=5)
            traj_analysis = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            
            if traj_analysis:
                vlm_executed = True
                if traj_analysis.get('app_password_generated'): score += 7
                if traj_analysis.get('post_editor_used'): score += 7
                if traj_analysis.get('privacy_configured'): score += 6
                feedback_parts.append("VLM confirmed trajectory actions")

            # Final State
            final_img = get_final_screenshot(traj)
            final_analysis = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
            
            if final_analysis:
                vlm_executed = True
                if final_analysis.get('success_indicators') or final_analysis.get('admin_visible'):
                    score += 10
                    feedback_parts.append("VLM confirmed final state")
        except Exception as e:
            logger.warning(f"VLM processing error: {e}")

    # Allow passing if VLM unavailable but programmatic is perfect
    if not vlm_executed:
        score = int(score * (100.0 / 70.0))
        feedback_parts.append("VLM unavailable, scaled programmatic score")

    # Pass logic: Must have functional integration testing success
    passed = score >= 75 and api_success

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }