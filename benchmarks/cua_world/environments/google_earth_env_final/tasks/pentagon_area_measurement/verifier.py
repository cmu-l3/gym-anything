#!/usr/bin/env python3
"""
Verifier for Pentagon Area Measurement task.

VERIFICATION STRATEGY:
This task uses VLM hybrid verification combining:
1. Trajectory analysis - verifies agent actually performed the workflow
2. Final state analysis - verifies correct location and tool usage
3. Programmatic checks - verifies timing and basic state

SCORING (100 points total):
- Navigation to Pentagon: 20 points
- Polygon tool activated: 15 points  
- Polygon vertices placed: 20 points
- Polygon closed/completed: 15 points
- Area measurement visible: 15 points
- Area within tolerance: 15 points

PASS THRESHOLD: 70 points with mandatory criteria (tool activated + area visible)

ANTI-GAMING:
- Uses trajectory frames (not just final screenshot)
- Checks task duration (must be reasonable)
- Verifies state changes occurred
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth for Pentagon
GROUND_TRUTH = {
    "location": "Pentagon, Arlington, Virginia",
    "coordinates": (38.8719, -77.0563),
    "expected_area_m2": 116000,
    "min_area_m2": 90000,
    "max_area_m2": 150000,
    "expected_vertices": 5
}


# =============================================================================
# VLM PROMPTS
# =============================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a polygon area measurement task in Google Earth Pro.

TASK: Navigate to the Pentagon building in Arlington, Virginia, and use the polygon measurement tool to trace the building outline and calculate its area.

The images are in chronological order (earliest to latest). Look for evidence of these workflow stages:

1. INITIAL STATE: Google Earth showing a default/global view
2. NAVIGATION: Search being used, view flying/zooming to Pentagon location  
3. PENTAGON VISIBLE: The distinctive 5-sided Pentagon building is visible from above
4. TOOL ACTIVATION: Ruler dialog opened with Polygon tab selected
5. POLYGON TRACING: Polygon vertices being placed on the Pentagon corners
6. MEASUREMENT COMPLETE: Closed polygon with area measurement displayed

Assess the following:
1. WORKFLOW_PROGRESSION: Do the screenshots show clear progression through multiple stages?
2. PENTAGON_REACHED: Is the Pentagon building (distinctive pentagon shape) visible at any point?
3. TOOL_USED: Is there evidence of the Ruler/measurement tool being opened?
4. POLYGON_DRAWN: Is there a polygon overlay visible on the building?
5. AREA_SHOWN: Is an area measurement value visible in any screenshot?

Respond in JSON format:
{
    "workflow_progression": true/false,
    "stages_observed": ["list of stages you can identify"],
    "pentagon_reached": true/false,
    "tool_used": true/false,
    "polygon_drawn": true/false,
    "area_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the trajectory"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth Pro polygon area measurement task.

TASK: The agent should have navigated to the Pentagon building in Arlington, Virginia, and measured its area using the polygon tool. The expected area is approximately 116,000 square meters (29 acres).

Look at this final screenshot and assess:

1. LOCATION CHECK:
   - Is this Google Earth Pro (satellite imagery application)?
   - Is the Pentagon building visible? (distinctive 5-sided building, Arlington VA)
   - Is the view appropriately zoomed to see the building clearly?

2. TOOL CHECK:
   - Is the Ruler dialog/window visible?
   - Is the Polygon measurement mode active (shown in the Ruler dialog)?

3. POLYGON CHECK:
   - Is there a polygon shape overlaid on the Pentagon building?
   - Does the polygon have approximately 5 sides matching the building shape?
   - Is the polygon closed (complete loop)?

4. MEASUREMENT CHECK:
   - Is an area measurement displayed in the Ruler dialog?
   - If visible, what is the approximate value? (look for numbers with units like m², sq m, acres, etc.)

Respond in JSON format:
{
    "is_google_earth": true/false,
    "pentagon_visible": true/false,
    "appropriate_zoom": true/false,
    "ruler_dialog_visible": true/false,
    "polygon_mode_active": true/false,
    "polygon_overlay_visible": true/false,
    "polygon_has_five_sides": true/false,
    "polygon_is_closed": true/false,
    "area_measurement_visible": true/false,
    "detected_area_value": "string value if visible, or null",
    "detected_area_unit": "m2/acres/sqft/unknown/null",
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observe"
}
"""


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_trajectory_frames(traj: Dict[str, Any], n_samples: int = 5) -> List[str]:
    """
    Sample frames from the trajectory for VLM analysis.
    Returns list of frame file paths.
    """
    frames = []
    
    # Try to get frames from trajectory
    if 'frames' in traj and traj['frames']:
        all_frames = traj['frames']
        if len(all_frames) <= n_samples:
            frames = all_frames
        else:
            # Sample evenly across trajectory
            indices = [int(i * (len(all_frames) - 1) / (n_samples - 1)) for i in range(n_samples)]
            frames = [all_frames[i] for i in indices]
    
    # Also try episode_dir for frame files
    episode_dir = traj.get('episode_dir', '')
    if episode_dir and os.path.isdir(episode_dir):
        frame_files = sorted([
            os.path.join(episode_dir, f) for f in os.listdir(episode_dir)
            if f.endswith('.png') and 'frame' in f.lower()
        ])
        if frame_files and not frames:
            if len(frame_files) <= n_samples:
                frames = frame_files
            else:
                indices = [int(i * (len(frame_files) - 1) / (n_samples - 1)) for i in range(n_samples)]
                frames = [frame_files[i] for i in indices]
    
    return frames


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the final screenshot from trajectory."""
    # Try direct final_screenshot field
    if 'final_screenshot' in traj:
        return traj['final_screenshot']
    
    # Try frames list
    if 'frames' in traj and traj['frames']:
        return traj['frames'][-1]
    
    # Try episode_dir
    episode_dir = traj.get('episode_dir', '')
    if episode_dir and os.path.isdir(episode_dir):
        frame_files = sorted([
            os.path.join(episode_dir, f) for f in os.listdir(episode_dir)
            if f.endswith('.png')
        ])
        if frame_files:
            return frame_files[-1]
    
    return None


def parse_area_value(detected_value: str, detected_unit: str) -> Optional[float]:
    """
    Parse detected area value and convert to square meters.
    Returns area in m² or None if parsing fails.
    """
    if not detected_value or detected_value == "null":
        return None
    
    try:
        # Clean the value string
        value_str = detected_value.replace(',', '').replace(' ', '')
        # Extract numeric part
        import re
        match = re.search(r'[\d.]+', value_str)
        if not match:
            return None
        
        value = float(match.group())
        
        # Convert to m² based on unit
        unit = (detected_unit or "").lower()
        if 'acre' in unit or unit == 'ac':
            return value * 4046.86  # 1 acre = 4046.86 m²
        elif 'sqft' in unit or 'sq ft' in unit or 'square feet' in unit:
            return value * 0.0929  # 1 sq ft = 0.0929 m²
        elif 'km' in unit:
            return value * 1000000  # 1 km² = 1,000,000 m²
        else:
            # Assume m²
            return value
    except (ValueError, TypeError):
        return None


def check_area_tolerance(area_m2: float) -> Dict[str, Any]:
    """Check if the measured area is within acceptable tolerance."""
    if area_m2 is None:
        return {"valid": False, "deviation_percent": None}
    
    expected = GROUND_TRUTH["expected_area_m2"]
    deviation = abs(area_m2 - expected) / expected * 100
    
    valid = GROUND_TRUTH["min_area_m2"] <= area_m2 <= GROUND_TRUTH["max_area_m2"]
    
    return {
        "valid": valid,
        "area_m2": area_m2,
        "expected_m2": expected,
        "deviation_percent": round(deviation, 2),
        "within_range": f"{GROUND_TRUTH['min_area_m2']}-{GROUND_TRUTH['max_area_m2']} m²"
    }


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def verify_pentagon_area_measurement(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the Pentagon area measurement task was completed correctly.
    
    Uses multi-signal verification:
    1. Trajectory VLM analysis (workflow verification)
    2. Final screenshot VLM analysis (state verification)
    3. Programmatic checks (timing, basic state)
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available",
            "details": {"error": "copy_from_env not provided"}
        }
    
    # Initialize scoring
    scores = {
        "navigation": 0,          # 20 points
        "tool_activation": 0,     # 15 points
        "polygon_vertices": 0,    # 20 points
        "polygon_closed": 0,      # 15 points
        "area_visible": 0,        # 15 points
        "area_tolerance": 0       # 15 points
    }
    feedback_parts = []
    details = {}
    
    # =========================================================================
    # STEP 1: Load task result from container
    # =========================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
        details["task_result"] = task_result
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
        details["task_result_error"] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # =========================================================================
    # STEP 2: Anti-gaming checks
    # =========================================================================
    task_duration = task_result.get("task_duration_seconds", 0)
    
    # Task should take at least 30 seconds for genuine completion
    if task_duration < 30:
        feedback_parts.append("⚠️ Task completed suspiciously fast")
        details["anti_gaming_warning"] = "Duration too short"
    else:
        details["task_duration_ok"] = True
    
    # Check if Google Earth was running
    ge_running = task_result.get("google_earth_running", False)
    if not ge_running:
        feedback_parts.append("❌ Google Earth not running at end")
    
    # =========================================================================
    # STEP 3: Copy screenshots for VLM analysis
    # =========================================================================
    temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    temp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    final_screenshot_path = None
    initial_screenshot_path = None
    
    try:
        copy_from_env("/tmp/task_final.png", temp_final.name)
        if os.path.exists(temp_final.name) and os.path.getsize(temp_final.name) > 1000:
            final_screenshot_path = temp_final.name
            details["final_screenshot_available"] = True
    except Exception as e:
        logger.warning(f"Could not copy final screenshot: {e}")
        details["final_screenshot_error"] = str(e)
    
    try:
        copy_from_env("/tmp/task_initial.png", temp_initial.name)
        if os.path.exists(temp_initial.name) and os.path.getsize(temp_initial.name) > 1000:
            initial_screenshot_path = temp_initial.name
            details["initial_screenshot_available"] = True
    except Exception as e:
        logger.warning(f"Could not copy initial screenshot: {e}")
    
    # =========================================================================
    # STEP 4: VLM Trajectory Analysis (if available)
    # =========================================================================
    trajectory_result = {}
    
    if query_vlm:
        # Get trajectory frames
        traj_frames = get_trajectory_frames(traj, n_samples=5)
        
        # If no trajectory frames, use initial + final screenshots
        if not traj_frames and initial_screenshot_path and final_screenshot_path:
            traj_frames = [initial_screenshot_path, final_screenshot_path]
        
        if traj_frames and len(traj_frames) >= 2:
            try:
                vlm_traj_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=traj_frames
                )
                if vlm_traj_result.get("success"):
                    trajectory_result = vlm_traj_result.get("parsed", {})
                    details["trajectory_vlm"] = trajectory_result
                    
                    # Score based on trajectory analysis
                    if trajectory_result.get("workflow_progression"):
                        feedback_parts.append("✅ Workflow progression verified")
                    
                    if trajectory_result.get("pentagon_reached"):
                        scores["navigation"] = 20
                        feedback_parts.append("✅ Pentagon location reached (trajectory)")
                    
                    if trajectory_result.get("tool_used"):
                        scores["tool_activation"] = 15
                        feedback_parts.append("✅ Measurement tool used (trajectory)")
                    
                    if trajectory_result.get("polygon_drawn"):
                        scores["polygon_vertices"] = 20
                        scores["polygon_closed"] = 15
                        feedback_parts.append("✅ Polygon drawn (trajectory)")
                    
                    if trajectory_result.get("area_shown"):
                        scores["area_visible"] = 15
                        feedback_parts.append("✅ Area measurement visible (trajectory)")
                else:
                    details["trajectory_vlm_error"] = vlm_traj_result.get("error", "Unknown")
            except Exception as e:
                logger.warning(f"Trajectory VLM failed: {e}")
                details["trajectory_vlm_exception"] = str(e)
    
    # =========================================================================
    # STEP 5: VLM Final State Analysis
    # =========================================================================
    final_state_result = {}
    
    if query_vlm and final_screenshot_path:
        try:
            vlm_final_result = query_vlm(
                prompt=FINAL_STATE_PROMPT,
                image=final_screenshot_path
            )
            if vlm_final_result.get("success"):
                final_state_result = vlm_final_result.get("parsed", {})
                details["final_state_vlm"] = final_state_result
                
                # Update scores based on final state (only if not already scored)
                if final_state_result.get("pentagon_visible") and scores["navigation"] == 0:
                    scores["navigation"] = 20
                    feedback_parts.append("✅ Pentagon visible in final state")
                elif not final_state_result.get("pentagon_visible") and scores["navigation"] == 0:
                    feedback_parts.append("❌ Pentagon not visible")
                
                if final_state_result.get("ruler_dialog_visible"):
                    if scores["tool_activation"] == 0:
                        scores["tool_activation"] = 15
                        feedback_parts.append("✅ Ruler dialog visible")
                else:
                    if scores["tool_activation"] == 0:
                        feedback_parts.append("❌ Ruler dialog not visible")
                
                if final_state_result.get("polygon_overlay_visible"):
                    if scores["polygon_vertices"] == 0:
                        scores["polygon_vertices"] = 20
                        feedback_parts.append("✅ Polygon overlay visible")
                    
                    if final_state_result.get("polygon_is_closed") and scores["polygon_closed"] == 0:
                        scores["polygon_closed"] = 15
                        feedback_parts.append("✅ Polygon is closed")
                
                if final_state_result.get("area_measurement_visible"):
                    if scores["area_visible"] == 0:
                        scores["area_visible"] = 15
                        feedback_parts.append("✅ Area measurement displayed")
                    
                    # Try to parse and validate area value
                    detected_value = final_state_result.get("detected_area_value")
                    detected_unit = final_state_result.get("detected_area_unit")
                    
                    if detected_value:
                        area_m2 = parse_area_value(detected_value, detected_unit)
                        if area_m2:
                            tolerance_check = check_area_tolerance(area_m2)
                            details["area_validation"] = tolerance_check
                            
                            if tolerance_check["valid"]:
                                scores["area_tolerance"] = 15
                                feedback_parts.append(f"✅ Area within tolerance ({tolerance_check['deviation_percent']}% deviation)")
                            else:
                                feedback_parts.append(f"⚠️ Area outside tolerance ({area_m2:.0f} m², expected ~{GROUND_TRUTH['expected_area_m2']} m²)")
            else:
                details["final_state_vlm_error"] = vlm_final_result.get("error", "Unknown")
        except Exception as e:
            logger.warning(f"Final state VLM failed: {e}")
            details["final_state_vlm_exception"] = str(e)
    
    # =========================================================================
    # STEP 6: Fallback programmatic checks
    # =========================================================================
    
    # If Ruler window was detected by wmctrl
    if task_result.get("ruler_window_visible") and scores["tool_activation"] == 0:
        scores["tool_activation"] = 10  # Partial credit
        feedback_parts.append("✅ Ruler window detected (wmctrl)")
    
    # =========================================================================
    # STEP 7: Calculate final score and determine pass/fail
    # =========================================================================
    
    total_score = sum(scores.values())
    
    # Mandatory criteria for passing:
    # - Tool must have been activated (score > 0)
    # - Area measurement must be visible (score > 0) OR polygon was drawn
    tool_used = scores["tool_activation"] > 0
    work_done = scores["area_visible"] > 0 or scores["polygon_vertices"] > 0
    
    passed = total_score >= 70 and tool_used and work_done
    
    # Cleanup temp files
    try:
        if os.path.exists(temp_final.name):
            os.unlink(temp_final.name)
        if os.path.exists(temp_initial.name):
            os.unlink(temp_initial.name)
    except:
        pass
    
    # =========================================================================
    # STEP 8: Build final result
    # =========================================================================
    
    details["scores_breakdown"] = scores
    details["ground_truth"] = GROUND_TRUTH
    
    feedback_summary = " | ".join(feedback_parts) if feedback_parts else "No verification details available"
    
    score_breakdown = f"""
Score Breakdown:
  Navigation to Pentagon:  {scores['navigation']}/20
  Tool Activation:         {scores['tool_activation']}/15
  Polygon Vertices:        {scores['polygon_vertices']}/20
  Polygon Closed:          {scores['polygon_closed']}/15
  Area Visible:            {scores['area_visible']}/15
  Area Tolerance:          {scores['area_tolerance']}/15
  ─────────────────────────────────
  TOTAL:                   {total_score}/100
  
  Mandatory Criteria Met: {'Yes' if (tool_used and work_done) else 'No'}
  PASSED: {'YES ✓' if passed else 'NO ✗'}
"""
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": f"{feedback_summary}\n{score_breakdown}",
        "details": details
    }