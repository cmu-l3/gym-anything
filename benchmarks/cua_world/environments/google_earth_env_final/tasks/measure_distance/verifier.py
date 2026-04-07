"""
Verifier for measure_distance task.

Task: "Use Google Earth's ruler/measurement tool to measure the distance
       between two landmarks. Measure the distance from the Statue of Liberty
       to the Empire State Building in New York City."

What this actually means:
- Agent should open the ruler tool in Google Earth
- Agent should click on Statue of Liberty, then Empire State Building
- The ruler should show a distance of approximately 8.5 km (5.3 miles)

IMPORTANT: Google Earth's ruler tool does NOT save measurements to KML
automatically. The measurement only exists while the ruler dialog is open.
Therefore, we CANNOT rely on KML parsing for verification.

Verification Strategy:
- VLM-only verification on final screenshot
- Check if ruler/measurement dialog is visible
- Check if measurement shows ~8.5km / ~5.3mi
- Check if the view shows NYC area (both landmarks relevant)
"""

import sys
import logging
from pathlib import Path
from typing import Dict, Any

from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected distance: Statue of Liberty to Empire State Building
# Calculated: haversine(40.6892, -74.0445, 40.7484, -73.9857) ≈ 8.5 km
EXPECTED_DISTANCE_KM = 8.5
EXPECTED_DISTANCE_MI = 5.3


# =============================================================================
# VLM PROMPT
# =============================================================================

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully completed a measurement task in Google Earth.

TASK: Use the ruler tool to measure the distance from the Statue of Liberty to the Empire State Building in NYC. Expected distance is approximately 8.5 km (5.3 miles).

Look at this screenshot and determine:

1. Is Google Earth's ruler/measurement tool visible? Look for:
   - A "Ruler" dialog box or measurement panel
   - Distance readout showing a number with units (km, mi, m, etc.)
   - A measurement line drawn on the map (usually yellow or white)
   - Start and end point markers

2. If a measurement is visible, what distance does it show?
   - The expected distance is approximately 8-9 km or 5-6 miles
   - Accept values in the range 7.5-9.5 km or 4.7-6.0 miles

3. Is this the NYC area where Statue of Liberty and Empire State Building are located?
   - View should show Lower Manhattan / NYC harbor area
   - Measurement line should span from harbor area (Liberty Island) to midtown Manhattan

Respond in JSON format:
{
    "ruler_tool_visible": true/false,
    "measurement_displayed": true/false,
    "distance_value": "the exact value shown (e.g., '8.52 km', '5.31 mi') or null if not visible",
    "distance_in_expected_range": true/false,
    "nyc_area_visible": true/false,
    "measurement_line_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def check_measurement(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a distance measurement between Statue of Liberty and
    Empire State Building was performed.

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

    ruler_visible = parsed.get("ruler_tool_visible", False)
    measurement_displayed = parsed.get("measurement_displayed", False)
    distance_value = parsed.get("distance_value")
    distance_in_range = parsed.get("distance_in_expected_range", False)
    nyc_visible = parsed.get("nyc_area_visible", False)
    line_visible = parsed.get("measurement_line_visible", False)
    confidence = parsed.get("confidence", "low")
    reasoning = parsed.get("reasoning", "")

    # Calculate score based on criteria
    criteria_met = 0
    total_criteria = 4

    # Criterion 1: Ruler tool visible
    if ruler_visible:
        criteria_met += 1
        feedback_parts.append("✅ Ruler tool visible")
    else:
        feedback_parts.append("❌ Ruler tool not visible")

    # Criterion 2: Measurement displayed with correct value
    if measurement_displayed and distance_in_range:
        criteria_met += 1
        if distance_value:
            feedback_parts.append(f"✅ Distance shown: {distance_value}")
        else:
            feedback_parts.append(f"✅ Distance in expected range (~{EXPECTED_DISTANCE_KM}km)")
    elif measurement_displayed:
        criteria_met += 0.5
        if distance_value:
            feedback_parts.append(f"⚠️ Distance shown: {distance_value} (expected ~{EXPECTED_DISTANCE_KM}km)")
        else:
            feedback_parts.append("⚠️ Measurement visible but value unclear")
    else:
        feedback_parts.append("❌ No measurement value displayed")

    # Criterion 3: NYC area visible
    if nyc_visible:
        criteria_met += 1
        feedback_parts.append("✅ NYC area visible")
    else:
        feedback_parts.append("❌ NYC area not confirmed")

    # Criterion 4: Measurement line visible
    if line_visible:
        criteria_met += 1
        feedback_parts.append("✅ Measurement line visible")
    else:
        feedback_parts.append("❌ No measurement line visible")

    # Adjust for confidence
    if confidence == "high" and criteria_met >= 3.5:
        score = min(100, int((criteria_met / total_criteria) * 100) + 10)
    elif confidence == "medium" and criteria_met >= 3:
        score = int((criteria_met / total_criteria) * 100)
    else:
        score = int((criteria_met / total_criteria) * 90)

    passed = criteria_met >= 3  # Need at least 3 of 4 criteria

    # Add reasoning if available
    if reasoning:
        feedback_parts.append(f"VLM: {reasoning}")

    # Summary
    if passed:
        feedback_parts.append(f"🎉 Successfully measured distance (~{EXPECTED_DISTANCE_KM}km)!")
    else:
        feedback_parts.append("❌ Distance measurement not confirmed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details,
    }
