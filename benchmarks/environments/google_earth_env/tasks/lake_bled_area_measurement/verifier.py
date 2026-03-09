#!/usr/bin/env python3
"""
Verifier for Lake Bled Area Measurement task.

VERIFICATION STRATEGY:
This task uses hybrid verification combining:
1. Programmatic checks (file existence, timestamps, size)
2. VLM trajectory verification (process verification across multiple frames)
3. VLM content verification (Lake Bled identification, polygon presence)

SCORING BREAKDOWN (100 points total):
- Screenshot file exists: 10 points
- File created during task (anti-gaming): 15 points  
- File size reasonable: 10 points
- Lake Bled visible in trajectory/final (VLM): 25 points
- Polygon measurement visible (VLM): 20 points
- Meaningful workflow progression (VLM): 20 points

PASS THRESHOLD: 60 points AND (file_created OR file_exists) AND lake_visible

Uses copy_from_env (NOT exec_in_env) per framework requirements.
Uses trajectory frames for VLM verification, not just final screenshot.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ============================================================
# VLM PROMPTS
# ============================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a lake surface area measurement task in Google Earth Pro.

The images are sampled chronologically from the agent's interaction (earliest to latest).

TASK: Measure the surface area of Lake Bled in Slovenia using the polygon measurement tool.

For successful completion, the agent should progress through these stages:
1. Google Earth Pro open - the application with satellite imagery is visible
2. Navigation to Lake Bled - a lake with a distinctive small island in the center becomes visible
3. Polygon tool usage - the Ruler dialog is open with Polygon tab selected
4. Lake tracing - polygon points/lines are visible around the lake shoreline
5. Area measurement - an area value is displayed in the Ruler dialog

Lake Bled identification features:
- Distinctive small island (Bled Island) near the center of the lake
- Oval/elongated shape
- Surrounded by mountains and green forest
- Located in Alpine region

Assess:
1. LAKE_BLED_VISIBLE: Is Lake Bled clearly visible in any frame? (look for the island)
2. POLYGON_TOOL_VISIBLE: Is the Ruler/measurement dialog visible with Polygon mode?
3. POLYGON_DRAWN: Are polygon lines visible tracing around the lake?
4. AREA_MEASUREMENT_VISIBLE: Is an area value displayed?
5. WORKFLOW_PROGRESSION: Do the frames show meaningful state changes?

Respond in JSON format:
{
    "lake_bled_visible": true/false,
    "polygon_tool_visible": true/false,
    "polygon_drawn_on_lake": true/false,
    "area_measurement_visible": true/false,
    "workflow_progression": true/false,
    "island_visible": true/false,
    "stages_observed": ["list of stages you observed"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_SCREENSHOT_PROMPT = """You are verifying a screenshot showing the result of a lake surface area measurement in Google Earth Pro.

TASK: Measure the surface area of Lake Bled, Slovenia.

Look at this screenshot and determine:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro (satellite imagery application)?

2. LAKE_BLED_IDENTIFIED: Does this show Lake Bled, Slovenia? Key features:
   - A lake with a small island in the center (Bled Island with a church)
   - Oval/elongated lake shape
   - Alpine mountain surroundings with green forest
   - NOT any random lake - must have the distinctive island

3. POLYGON_MEASUREMENT_PRESENT: Is there a polygon measurement on the lake?
   - Polygon lines tracing the lake shoreline
   - The Ruler dialog showing area calculation
   - Any visible area value (in km², hectares, sq mi, etc.)

4. AREA_VALUE: If an area measurement is visible, what is the approximate value?
   - Expected: around 1.45 km² (or ~145 hectares, ~0.56 sq mi)
   - Acceptable range: 1.0 - 2.0 km²

Respond in JSON format:
{
    "is_google_earth": true/false,
    "lake_bled_identified": true/false,
    "island_visible": true/false,
    "polygon_visible": true/false,
    "ruler_dialog_visible": true/false,
    "area_value_visible": true/false,
    "area_value_if_readable": "value with units or null",
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


# ============================================================
# HELPER FUNCTIONS
# ============================================================

def _safe_vlm_query(query_vlm, prompt: str, image=None, images=None) -> Optional[Dict]:
    """Safely execute VLM query with error handling."""
    if not query_vlm:
        logger.warning("VLM query function not available")
        return None
    
    try:
        if images:
            result = query_vlm(prompt=prompt, images=images)
        elif image:
            result = query_vlm(prompt=prompt, image=image)
        else:
            logger.warning("No image provided for VLM query")
            return None
        
        if result.get("success"):
            return result.get("parsed", {})
        else:
            logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
            return None
    except Exception as e:
        logger.error(f"VLM query exception: {e}")
        return None


def _parse_area_value(area_string: str) -> Optional[float]:
    """Try to parse an area value from a string to km²."""
    if not area_string or area_string == "null":
        return None
    
    try:
        area_string = area_string.lower().strip()
        
        # Try to extract numeric value
        import re
        numbers = re.findall(r'[\d.]+', area_string)
        if not numbers:
            return None
        
        value = float(numbers[0])
        
        # Convert to km² based on units
        if 'hectare' in area_string or 'ha' in area_string:
            return value / 100  # hectares to km²
        elif 'sq mi' in area_string or 'square mile' in area_string:
            return value * 2.59  # sq mi to km²
        elif 'acre' in area_string:
            return value / 247.105  # acres to km²
        elif 'm²' in area_string or 'sq m' in area_string or 'square meter' in area_string:
            return value / 1000000  # m² to km²
        else:
            # Assume km² if no unit or km² specified
            return value
            
    except Exception as e:
        logger.warning(f"Could not parse area value '{area_string}': {e}")
        return None


# ============================================================
# MAIN VERIFICATION FUNCTION  
# ============================================================

def verify_lake_bled_area_measurement(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent successfully measured Lake Bled's surface area.
    
    Uses:
    - copy_from_env for file retrieval (NOT exec_in_env)
    - Trajectory frames for process verification
    - Multi-criteria scoring with anti-gaming checks
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env, query_vlm
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ copy_from_env function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/lake_bled_measurement.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    
    score = 0
    feedback_parts = []
    details = {}
    
    # ============================================================
    # STEP 1: Copy and parse task result JSON
    # ============================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_json'] = result
    except Exception as e:
        logger.warning(f"Could not read task result JSON: {e}")
        details['result_json_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ============================================================
    # CRITERION 1: Screenshot file exists (10 points)
    # ============================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and output_size > 0:
        score += 10
        feedback_parts.append("✅ Screenshot file exists")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ Screenshot file NOT found")
        details['file_exists'] = False
    
    # ============================================================
    # CRITERION 2: File created during task - ANTI-GAMING (15 points)
    # ============================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task")
        details['file_created_during_task'] = True
    else:
        if output_exists:
            feedback_parts.append("⚠️ File exists but may predate task")
        details['file_created_during_task'] = False
    
    # ============================================================
    # CRITERION 3: File size reasonable (10 points)
    # ============================================================
    file_size_kb = output_size / 1024 if output_size else 0
    
    if file_size_kb >= min_file_size_kb:
        score += 10
        feedback_parts.append(f"✅ Good file size ({file_size_kb:.1f} KB)")
        details['file_size_ok'] = True
    elif file_size_kb >= 50:
        score += 5
        feedback_parts.append(f"⚠️ Small file size ({file_size_kb:.1f} KB)")
        details['file_size_ok'] = 'partial'
    else:
        feedback_parts.append(f"❌ File too small ({file_size_kb:.1f} KB)")
        details['file_size_ok'] = False
    
    # ============================================================
    # VLM VERIFICATION (if available)
    # ============================================================
    vlm_trajectory_result = None
    vlm_final_result = None
    lake_visible = False
    polygon_visible = False
    
    if query_vlm:
        # ============================================================
        # CRITERION 4: Trajectory verification (20 points)
        # Sample frames across the trajectory to verify workflow
        # ============================================================
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            if trajectory_frames and len(trajectory_frames) > 0:
                vlm_trajectory_result = _safe_vlm_query(
                    query_vlm,
                    TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                details['vlm_trajectory'] = vlm_trajectory_result
                
                if vlm_trajectory_result:
                    workflow_ok = vlm_trajectory_result.get('workflow_progression', False)
                    lake_in_traj = vlm_trajectory_result.get('lake_bled_visible', False)
                    polygon_in_traj = vlm_trajectory_result.get('polygon_drawn_on_lake', False)
                    
                    if workflow_ok and lake_in_traj:
                        score += 20
                        feedback_parts.append("✅ Workflow progression verified")
                    elif lake_in_traj or polygon_in_traj:
                        score += 12
                        feedback_parts.append("⚠️ Partial workflow verified")
                    else:
                        feedback_parts.append("❌ Workflow not clearly verified")
                    
                    # Track for pass criteria
                    if lake_in_traj:
                        lake_visible = True
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
                
        except ImportError:
            logger.warning("Could not import VLM trajectory helpers")
            feedback_parts.append("⚠️ Trajectory verification unavailable")
        except Exception as e:
            logger.warning(f"Trajectory verification error: {e}")
            details['trajectory_error'] = str(e)
        
        # ============================================================
        # CRITERION 5: Final screenshot content verification (25 points)
        # ============================================================
        try:
            # Copy the output screenshot for VLM analysis
            if output_exists:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env(expected_output_path, temp_screenshot.name)
                    
                    # Verify file is valid image
                    if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                        vlm_final_result = _safe_vlm_query(
                            query_vlm,
                            FINAL_SCREENSHOT_PROMPT,
                            image=temp_screenshot.name
                        )
                        details['vlm_final'] = vlm_final_result
                        
                        if vlm_final_result:
                            is_ge = vlm_final_result.get('is_google_earth', False)
                            lake_id = vlm_final_result.get('lake_bled_identified', False)
                            island_vis = vlm_final_result.get('island_visible', False)
                            polygon_vis = vlm_final_result.get('polygon_visible', False)
                            area_vis = vlm_final_result.get('area_value_visible', False)
                            confidence = vlm_final_result.get('confidence', 'low')
                            
                            content_score = 0
                            if is_ge:
                                content_score += 5
                            if lake_id or island_vis:
                                content_score += 10
                                lake_visible = True
                            if polygon_vis:
                                content_score += 5
                                polygon_visible = True
                            if area_vis:
                                content_score += 5
                            
                            # Confidence bonus
                            if confidence == 'high' and content_score >= 15:
                                content_score = min(25, content_score + 3)
                            
                            score += content_score
                            
                            if lake_id and polygon_vis:
                                feedback_parts.append("✅ Lake Bled with polygon measurement visible")
                            elif lake_id:
                                feedback_parts.append("⚠️ Lake Bled visible, polygon unclear")
                            elif polygon_vis:
                                feedback_parts.append("⚠️ Polygon visible, lake identity unclear")
                            else:
                                feedback_parts.append("❌ Content verification inconclusive")
                            
                            # Parse area value if visible
                            area_str = vlm_final_result.get('area_value_if_readable')
                            if area_str:
                                parsed_area = _parse_area_value(area_str)
                                if parsed_area:
                                    details['measured_area_km2'] = parsed_area
                                    area_range = metadata.get('expected_area_km2', {})
                                    min_area = area_range.get('min', 1.0)
                                    max_area = area_range.get('max', 2.0)
                                    if min_area <= parsed_area <= max_area:
                                        feedback_parts.append(f"✅ Area {parsed_area:.2f} km² in valid range")
                                    else:
                                        feedback_parts.append(f"⚠️ Area {parsed_area:.2f} km² outside expected range")
                                        
                except Exception as e:
                    logger.warning(f"Could not analyze output screenshot: {e}")
                    details['screenshot_analysis_error'] = str(e)
                finally:
                    if os.path.exists(temp_screenshot.name):
                        os.unlink(temp_screenshot.name)
            else:
                feedback_parts.append("❌ No output file to analyze")
                
        except Exception as e:
            logger.warning(f"Final screenshot verification error: {e}")
            details['final_verification_error'] = str(e)
            
        # ============================================================
        # CRITERION 6: Polygon measurement specifically visible (20 points)
        # ============================================================
        if polygon_visible or (vlm_trajectory_result and vlm_trajectory_result.get('polygon_tool_visible')):
            score += 20
            feedback_parts.append("✅ Polygon measurement tool usage confirmed")
            details['polygon_verified'] = True
        elif vlm_trajectory_result and vlm_trajectory_result.get('area_measurement_visible'):
            score += 15
            feedback_parts.append("⚠️ Area measurement visible")
            details['polygon_verified'] = 'partial'
        else:
            feedback_parts.append("❌ Polygon measurement not clearly verified")
            details['polygon_verified'] = False
            
    else:
        # No VLM available - give partial credit based on file checks
        feedback_parts.append("⚠️ VLM not available for content verification")
        if output_exists and file_created_during_task:
            score += 25  # Partial credit for file evidence
            feedback_parts.append("⚠️ Partial credit based on file creation")
    
    # ============================================================
    # Check Google Earth was running
    # ============================================================
    ge_running = result.get('google_earth_running', False)
    if ge_running:
        details['google_earth_running'] = True
    else:
        details['google_earth_running'] = False
        feedback_parts.append("⚠️ Google Earth not detected running at end")
    
    # ============================================================
    # PASS/FAIL DETERMINATION
    # ============================================================
    # Pass requires: score >= 60 AND (file created during task) AND (lake visible OR file exists with good size)
    key_criteria_met = (
        (file_created_during_task or (output_exists and file_size_kb >= min_file_size_kb)) and
        (lake_visible or (output_exists and not query_vlm))  # If no VLM, trust file evidence
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Bonus feedback
    if passed:
        feedback_parts.insert(0, f"🎉 PASSED (Score: {score}/100)")
    else:
        reasons = []
        if score < 60:
            reasons.append(f"score {score} < 60")
        if not (file_created_during_task or output_exists):
            reasons.append("no valid output file")
        if not lake_visible and query_vlm:
            reasons.append("Lake Bled not confirmed")
        feedback_parts.insert(0, f"❌ FAILED ({', '.join(reasons)})")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }