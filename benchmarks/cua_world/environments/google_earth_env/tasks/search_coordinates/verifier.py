"""
Verifier for search_coordinates task.

Task: "Search for and navigate to specific GPS coordinates in Google Earth.
       Navigate to coordinates 40.7128, -74.0060 (New York City)."

What this actually means:
- Agent should enter GPS coordinates (40.7128, -74.0060) in Google Earth search
- The final view should show New York City area
- Task does NOT specify zoom level or what must be visible in NYC

Verification Strategy:
- VLM-only verification on final screenshot
- Check if the view shows NYC metropolitan area
- No programmatic coordinate extraction (unreliable)
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any

from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# VLM PROMPT
# =============================================================================

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully completed a navigation task in Google Earth.

TASK: Navigate to GPS coordinates 40.7128, -74.0060 (New York City).

Look at this screenshot and determine:
1. Is this Google Earth (satellite/aerial imagery, not a photo or other app)?
2. Does this show New York City area? Look for:
   - Manhattan island (distinctive elongated shape surrounded by water)
   - Dense urban grid pattern
   - Hudson River on west, East River on east
   - Central Park (large green rectangle) if zoomed to show Manhattan
   - NYC metro area urban development
3. Is the view centered on or near the NYC metropolitan area?

Note: The coordinates (40.7128, -74.0060) are for Lower Manhattan/City Hall area. The agent may show a close-up view or a wider NYC area view. Both are acceptable as long as it's clearly NYC.

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_nyc": true/false,
    "manhattan_or_metro_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_coordinates(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that Google Earth view shows New York City area.

    Uses VLM-only verification on the final screenshot.

    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info
        task_info: Task info with task_id

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    feedback_parts = []
    result_details = {}

    # Get final screenshot
    query_vlm = env_info.get('query_vlm')
    final_screenshot = get_final_screenshot(traj)
    result_details['final_screenshot'] = final_screenshot

    if not final_screenshot:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ No screenshot available for verification",
            "details": result_details,
        }

    if not query_vlm:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ VLM query function not available for verification",
            "details": result_details,
        }

    # Query VLM
    vlm_result = query_vlm(
        prompt=VERIFICATION_PROMPT,
        image=final_screenshot,
    )
    result_details['vlm_result'] = vlm_result

    if not vlm_result.get("success"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ VLM verification failed: {vlm_result.get('error', 'Unknown error')}",
            "details": result_details,
        }

    # Parse VLM response
    parsed = vlm_result.get("parsed", {})

    is_google_earth = parsed.get("is_google_earth", False)
    shows_nyc = parsed.get("shows_nyc", False)
    manhattan_visible = parsed.get("manhattan_or_metro_visible", False)
    confidence = parsed.get("confidence", "low")
    reasoning = parsed.get("reasoning", "")

    # Calculate score based on criteria
    criteria_met = 0
    total_criteria = 3

    if is_google_earth:
        criteria_met += 1
        feedback_parts.append("✅ Google Earth view confirmed")
    else:
        feedback_parts.append("❌ Not clearly Google Earth")

    if shows_nyc:
        criteria_met += 1
        feedback_parts.append("✅ NYC area visible")
    else:
        feedback_parts.append("❌ NYC not identified")

    if manhattan_visible:
        criteria_met += 1
        feedback_parts.append("✅ Manhattan/metro area visible")
    else:
        feedback_parts.append("❌ Manhattan/metro not found")

    # Adjust for confidence
    if confidence == "high" and criteria_met == total_criteria:
        score = 100
    elif confidence == "medium" and criteria_met == total_criteria:
        score = 90
    elif criteria_met == total_criteria:
        score = 80
    else:
        score = int((criteria_met / total_criteria) * 70)

    passed = criteria_met == total_criteria

    # Add reasoning if available
    if reasoning:
        feedback_parts.append(f"VLM: {reasoning}")

    # Summary
    if passed:
        feedback_parts.append("🎉 Successfully navigated to NYC coordinates!")
    else:
        feedback_parts.append("❌ Navigation to NYC coordinates not confirmed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
