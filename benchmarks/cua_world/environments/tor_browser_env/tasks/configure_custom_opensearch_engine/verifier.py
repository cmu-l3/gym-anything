#!/usr/bin/env python3
"""Verifier for configure_custom_opensearch_engine task.

Evaluates if the agent dynamically discovered and added PyPI as an OpenSearch
engine, removed Google, and successfully searched from the address bar.
"""

import json
import logging
import os
import tempfile
import base64
from PIL import Image
from io import BytesIO
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "configure_custom_opensearch_engine"

def verify_custom_opensearch(traj, env_info, task_info):
    """
    Scoring strategy (100 points total):
    1. PyPI website visited (10 pts)
    2. Google removed/hidden from engines (20 pts)
    3. PyPI added to browser engines (30 pts)
    4. Search executed via URL bar with valid timestamp (40 pts) - GATE

    Pass threshold: 70+ points AND the search must be successfully executed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result from container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result parsed: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    # Criterion 1: Visited PyPI (10 points)
    if result.get("pypi_visited", False):
        score += 10
        feedback_parts.append("Visited PyPI (10/10)")
    else:
        feedback_parts.append("PyPI NOT visited (0/10)")

    # Criterion 2: Google removed or hidden (20 points)
    if result.get("google_removed_or_hidden", False):
        score += 20
        feedback_parts.append("Google engine removed/hidden (20/20)")
    else:
        feedback_parts.append("Google engine NOT removed (0/20)")

    # Criterion 3: PyPI added to engines (30 points)
    if result.get("pypi_added_to_engines", False):
        score += 30
        feedback_parts.append("PyPI OpenSearch engine added (30/30)")
    else:
        feedback_parts.append("PyPI OpenSearch engine NOT added (0/30)")

    # Criterion 4: Address bar search execution (40 points) - GATE
    search_executed = result.get("search_executed", False)
    timestamp_valid = result.get("search_timestamp_valid", False)
    
    if search_executed and timestamp_valid:
        score += 40
        feedback_parts.append("Search executed from address bar (40/40)")
    elif search_executed:
        # Pre-existing search detected but not from this run
        feedback_parts.append("Search found, but timestamps indicate it was before task start (0/40)")
    else:
        feedback_parts.append("Search NOT executed from address bar (0/40)")

    # ---------------------------------------------------------
    # Trajectory-based VLM Verification (Anti-gaming fallback)
    # ---------------------------------------------------------
    vlm_feedback = ""
    try:
        final_img = get_final_screenshot(traj)
        if final_img:
            # We check if the final screen looks like a PyPI search results page for 'stem'
            import openai
            
            # Using litellm/openai standard interface. Environment injection expected for Keys.
            vlm_base_url = os.environ.get('VLM_BASE_URL', 'https://adb-139772925381842.2.azuredatabricks.net/serving-endpoints')
            vlm_api_key = os.environ.get('VLM_API_KEY')

            if vlm_api_key:
                client = openai.OpenAI(base_url=vlm_base_url, api_key=vlm_api_key)
                
                img_resized = final_img.resize((1280, 720))
                buffer = BytesIO()
                img_resized.save(buffer, format="PNG")
                img_b64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
                
                prompt = """Analyze this browser screenshot.
Verify if the screen is showing Python Package Index (PyPI) search results for the query "stem".
Reply YES if you see PyPI search results indicating "stem". Reply NO otherwise."""

                response = client.chat.completions.create(
                    model='databricks-claude-sonnet-4-5',
                    messages=[{
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{img_b64}"}}
                        ]
                    }],
                    max_tokens=50,
                    temperature=0.0
                )
                
                ans = response.choices[0].message.content.strip().upper()
                if "YES" in ans:
                    vlm_feedback = " [VLM Verified Visuals]"
                else:
                    vlm_feedback = " [VLM: PyPI results not clearly visible]"
    except Exception as e:
        logger.warning(f"VLM verification failed/skipped: {e}")

    # Pass Condition: Score >= 70 AND the required search was actually executed
    passed = (score >= 70) and search_executed and timestamp_valid

    feedback = " | ".join(feedback_parts) + vlm_feedback
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "pypi_visited": 10 if result.get("pypi_visited") else 0,
            "google_removed": 20 if result.get("google_removed_or_hidden") else 0,
            "pypi_added": 30 if result.get("pypi_added_to_engines") else 0,
            "search_executed": 40 if (search_executed and timestamp_valid) else 0
        }
    }