"""
Verifier for navigate_to_location task.

Task: "Navigate Google Earth to view the Eiffel Tower in Paris, France.
       Use the search functionality to find and fly to the Eiffel Tower location."

What this actually means:
- Agent should use search to navigate to the Eiffel Tower
- The final view should show the Paris/Eiffel Tower area
- Task does NOT specify zoom level, 3D mode, or that tower must be clearly visible

Verification Strategy:
- VLM-only verification on final screenshot
- Check if the view shows Paris area / Eiffel Tower region
- No programmatic coordinate extraction (unreliable without invasive operations)
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

TASK: Navigate Google Earth to view the Eiffel Tower in Paris, France.

Look at this screenshot and determine:
1. Is this Google Earth (satellite/aerial imagery, not a photo or other app)?
2. Does this show Paris, France? Look for:
   - Urban area with distinctive Paris street patterns (radial boulevards)
   - The Eiffel Tower location (tower itself OR the Champ de Mars park area)
   - The Seine River running through the city
   - Dense European urban development
3. Is the view centered on or near the Eiffel Tower area?

Note: The agent may have zoomed in close (showing the tower structure) OR zoomed out (showing the Paris area with the tower location visible). Both are acceptable.

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_paris": true/false,
    "eiffel_tower_area_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_navigation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that Google Earth view shows the Eiffel Tower area in Paris.

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
    shows_paris = parsed.get("shows_paris", False)
    eiffel_area = parsed.get("eiffel_tower_area_visible", False)
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

    if shows_paris:
        criteria_met += 1
        feedback_parts.append("✅ Paris area visible")
    else:
        feedback_parts.append("❌ Paris not identified")

    if eiffel_area:
        criteria_met += 1
        feedback_parts.append("✅ Eiffel Tower area visible")
    else:
        feedback_parts.append("❌ Eiffel Tower area not found")

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
        feedback_parts.append("🎉 Successfully navigated to Eiffel Tower!")
    else:
        feedback_parts.append("❌ Navigation to Eiffel Tower not confirmed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
