#!/usr/bin/env python3
"""
Verifier for image_date_extraction task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Output file exists (10 points)
2. File was created/modified during task - anti-gaming (15 points)
3. File contains location reference (Colosseum/Rome) (15 points)
4. File contains valid coordinates near target (15 points)
5. File contains a valid date format (15 points)
6. Date is plausible (between 2000 and current year) (10 points)
7. VLM: Trajectory shows navigation to Colosseum (10 points)
8. VLM: Imagery date visible in final screenshot (10 points)

Pass threshold: 65 points with file existence and plausible date
"""

import json
import tempfile
import os
import re
import logging
from datetime import datetime
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def extract_year_from_date(date_str: str) -> Optional[int]:
    """Extract year from various date formats."""
    if not date_str:
        return None
    
    # Try YYYY-MM-DD or YYYY/MM/DD
    match = re.search(r'(19\d{2}|20\d{2})[-/]\d{1,2}[-/]\d{1,2}', date_str)
    if match:
        return int(match.group(1))
    
    # Try DD-MM-YYYY or DD/MM/YYYY or MM/DD/YYYY
    match = re.search(r'\d{1,2}[-/]\d{1,2}[-/](19\d{2}|20\d{2})', date_str)
    if match:
        return int(match.group(1))
    
    # Try Month DD, YYYY
    match = re.search(r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+\d{1,2},?\s+(19\d{2}|20\d{2})', date_str, re.IGNORECASE)
    if match:
        return int(match.group(2))
    
    # Try standalone year
    match = re.search(r'\b(19\d{2}|20\d{2})\b', date_str)
    if match:
        return int(match.group(1))
    
    return None


def check_coordinates_valid(lat_str: str, lon_str: str, target_lat: float, target_lon: float, tolerance: float) -> Tuple[bool, str]:
    """Check if extracted coordinates are near the target location."""
    try:
        if not lat_str or not lon_str:
            return False, "No coordinates extracted"
        
        lat = float(lat_str)
        lon = float(lon_str)
        
        lat_diff = abs(lat - target_lat)
        lon_diff = abs(lon - target_lon)
        
        if lat_diff <= tolerance and lon_diff <= tolerance:
            return True, f"Coordinates ({lat}, {lon}) within tolerance of target"
        else:
            return False, f"Coordinates ({lat}, {lon}) too far from target ({target_lat}, {target_lon})"
    except (ValueError, TypeError) as e:
        return False, f"Could not parse coordinates: {e}"


# ================================================================
# VLM VERIFICATION PROMPTS
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a navigation task in Google Earth Pro.

TASK: Navigate to the Colosseum in Rome, Italy and document the satellite imagery capture date.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful task completion, the agent should:
1. Have Google Earth Pro open and visible
2. Navigate to Rome/Colosseum area (via search or manual navigation)
3. Show the Colosseum structure visible in the satellite imagery
4. The imagery date should be visible somewhere (usually in status bar at bottom)

Assess:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro clearly visible in the screenshots?
2. NAVIGATION_TO_ROME: Do the screenshots show navigation toward Rome/Italy/Colosseum?
3. COLOSSEUM_VISIBLE: Is the Colosseum (oval amphitheater structure) visible in any frame?
4. MEANINGFUL_PROGRESSION: Do the frames show real navigation progression (not static)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "navigation_to_rome": true/false,
    "colosseum_visible": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_STATE_VERIFICATION_PROMPT = """You are verifying the final state of a Google Earth Pro navigation task.

TASK: The agent was asked to navigate to the Colosseum in Rome and find the imagery date.

Look at this screenshot and determine:
1. IS_GOOGLE_EARTH: Is this Google Earth Pro (satellite/aerial imagery interface)?
2. SHOWS_COLOSSEUM_AREA: Does this show the Colosseum in Rome? The Colosseum is a large oval/elliptical amphitheater structure in the center of Rome. It should be recognizable from aerial view.
3. IMAGERY_DATE_VISIBLE: Is there an imagery date displayed? This typically appears:
   - In the status bar at the bottom of the window
   - As text like "Image © 2023 Maxar" or "Imagery Date: MM/DD/YYYY"
   - Sometimes shown when hovering or in the corner

Note: The Colosseum is unmistakable from above - an oval amphitheater with visible internal structure.

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_colosseum_area": true/false,
    "imagery_date_visible": true/false,
    "colosseum_identifiable": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_image_date_extraction(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent navigated to the Colosseum and documented imagery date.
    
    Uses MULTIPLE INDEPENDENT SIGNALS:
    - Programmatic checks on output file
    - Timestamp validation (anti-gaming)
    - VLM verification on trajectory frames
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task metadata
    
    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', 41.8902)
    target_lon = metadata.get('target_longitude', 12.4922)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.05)
    min_year = metadata.get('min_year', 2000)
    max_year = metadata.get('max_year', datetime.now().year)
    
    feedback_parts = []
    score = 0
    max_score = 100
    result_details = {}
    
    # ================================================================
    # COPY RESULT FILE FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read task result: {e}",
            "details": result_details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists (10 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and output_size > 0:
        score += 10
        feedback_parts.append(f"✅ Output file exists ({output_size} bytes)")
    else:
        feedback_parts.append("❌ Output file not found or empty")
        # Early exit if no output
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (15 points) - ANTI-GAMING
    # ================================================================
    file_created = result.get('file_created_during_task', False)
    file_modified = result.get('file_modified_during_task', False)
    
    if file_created or file_modified:
        score += 15
        feedback_parts.append("✅ File created/modified during task")
        result_details['timestamp_valid'] = True
    else:
        feedback_parts.append("⚠️ File may have existed before task")
        result_details['timestamp_valid'] = False
    
    # ================================================================
    # CRITERION 3: Contains location reference (15 points)
    # ================================================================
    contains_location = result.get('contains_location', False)
    output_content = result.get('output_content', '')
    
    if contains_location:
        score += 15
        feedback_parts.append("✅ Location (Colosseum/Rome) mentioned")
    else:
        # Double-check by examining content ourselves
        content_lower = output_content.lower()
        if any(term in content_lower for term in ['colosseum', 'coliseum', 'colosseo', 'rome', 'roma', 'italy', 'italia']):
            score += 15
            feedback_parts.append("✅ Location reference found in content")
        else:
            feedback_parts.append("❌ No location reference (Colosseum/Rome)")
    
    # ================================================================
    # CRITERION 4: Contains valid coordinates (15 points)
    # ================================================================
    extracted_lat = result.get('extracted_lat', '')
    extracted_lon = result.get('extracted_lon', '')
    contains_coords = result.get('contains_coordinates', False)
    
    coords_valid, coords_msg = check_coordinates_valid(
        extracted_lat, extracted_lon, target_lat, target_lon, coord_tolerance
    )
    
    if coords_valid:
        score += 15
        feedback_parts.append(f"✅ Coordinates valid: ~({extracted_lat}, {extracted_lon})")
    elif contains_coords:
        score += 8
        feedback_parts.append(f"⚠️ Coordinates present but not verified: {coords_msg}")
    else:
        feedback_parts.append("❌ No valid coordinates found")
    
    # ================================================================
    # CRITERION 5: Contains valid date format (15 points)
    # ================================================================
    contains_date = result.get('contains_date', False)
    extracted_date = result.get('extracted_date', '')
    
    if contains_date and extracted_date:
        score += 15
        feedback_parts.append(f"✅ Date format found: {extracted_date}")
    elif contains_date:
        score += 10
        feedback_parts.append("✅ Date pattern detected in content")
    else:
        # Try to find any date pattern ourselves
        date_patterns = [
            r'\d{4}[-/]\d{1,2}[-/]\d{1,2}',
            r'\d{1,2}[-/]\d{1,2}[-/]\d{4}',
            r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w*\s+\d{1,2},?\s+\d{4}',
        ]
        date_found = any(re.search(p, output_content, re.IGNORECASE) for p in date_patterns)
        if date_found:
            score += 10
            feedback_parts.append("✅ Date pattern found in content")
        else:
            feedback_parts.append("❌ No valid date format found")
    
    # ================================================================
    # CRITERION 6: Date is plausible (10 points)
    # ================================================================
    year = extract_year_from_date(extracted_date) or extract_year_from_date(output_content)
    
    if year and min_year <= year <= max_year:
        score += 10
        feedback_parts.append(f"✅ Plausible year: {year}")
        result_details['extracted_year'] = year
    elif year:
        feedback_parts.append(f"⚠️ Year {year} outside expected range ({min_year}-{max_year})")
    else:
        feedback_parts.append("⚠️ Could not extract year for validation")
    
    # ================================================================
    # CRITERION 7 & 8: VLM Verification (20 points total)
    # ================================================================
    vlm_trajectory_score = 0
    vlm_final_score = 0
    
    if query_vlm:
        # Import trajectory frame sampling utility
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        except ImportError:
            # Fallback: try to get frames from traj directly
            sample_trajectory_frames = None
            get_final_screenshot = None
        
        # VLM on trajectory frames (10 points)
        trajectory_frames = None
        if sample_trajectory_frames:
            try:
                trajectory_frames = sample_trajectory_frames(traj, n=5)
            except Exception as e:
                logger.warning(f"Could not sample trajectory frames: {e}")
        
        if trajectory_frames and len(trajectory_frames) > 0:
            try:
                traj_vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                result_details['trajectory_vlm_result'] = traj_vlm_result
                
                if traj_vlm_result.get('success'):
                    parsed = traj_vlm_result.get('parsed', {})
                    
                    traj_criteria = sum([
                        parsed.get('google_earth_visible', False),
                        parsed.get('navigation_to_rome', False),
                        parsed.get('colosseum_visible', False),
                        parsed.get('meaningful_progression', False)
                    ])
                    
                    if traj_criteria >= 3:
                        vlm_trajectory_score = 10
                        feedback_parts.append("✅ VLM: Trajectory shows valid navigation")
                    elif traj_criteria >= 2:
                        vlm_trajectory_score = 6
                        feedback_parts.append("⚠️ VLM: Partial navigation evidence")
                    else:
                        feedback_parts.append("❌ VLM: Trajectory doesn't show navigation to Colosseum")
            except Exception as e:
                logger.warning(f"Trajectory VLM query failed: {e}")
                feedback_parts.append(f"⚠️ VLM trajectory check failed: {e}")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for VLM")
        
        # VLM on final screenshot (10 points)
        final_screenshot = None
        if get_final_screenshot:
            try:
                final_screenshot = get_final_screenshot(traj)
            except Exception as e:
                logger.warning(f"Could not get final screenshot: {e}")
        
        if not final_screenshot:
            # Try to copy from container
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/task_final.png", temp_screenshot.name)
                final_screenshot = temp_screenshot.name
            except Exception as e:
                logger.warning(f"Could not copy final screenshot: {e}")
            finally:
                # Don't delete yet if we need to use it
                pass
        
        if final_screenshot:
            try:
                final_vlm_result = query_vlm(
                    prompt=FINAL_STATE_VERIFICATION_PROMPT,
                    image=final_screenshot
                )
                result_details['final_vlm_result'] = final_vlm_result
                
                if final_vlm_result.get('success'):
                    parsed = final_vlm_result.get('parsed', {})
                    
                    is_ge = parsed.get('is_google_earth', False)
                    shows_colosseum = parsed.get('shows_colosseum_area', False) or parsed.get('colosseum_identifiable', False)
                    date_visible = parsed.get('imagery_date_visible', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    final_criteria = sum([is_ge, shows_colosseum, date_visible])
                    
                    if final_criteria >= 2 and confidence in ['medium', 'high']:
                        vlm_final_score = 10
                        feedback_parts.append("✅ VLM: Final state shows Colosseum area")
                    elif final_criteria >= 2:
                        vlm_final_score = 7
                        feedback_parts.append("⚠️ VLM: Colosseum area likely visible")
                    elif is_ge:
                        vlm_final_score = 3
                        feedback_parts.append("⚠️ VLM: Google Earth visible but Colosseum unclear")
                    else:
                        feedback_parts.append("❌ VLM: Final state doesn't show expected location")
            except Exception as e:
                logger.warning(f"Final screenshot VLM query failed: {e}")
                feedback_parts.append(f"⚠️ VLM final check failed: {e}")
            finally:
                # Clean up temp file if we created it
                if isinstance(final_screenshot, str) and final_screenshot.startswith('/tmp/') and os.path.exists(final_screenshot):
                    try:
                        os.unlink(final_screenshot)
                    except:
                        pass
        else:
            feedback_parts.append("⚠️ No final screenshot available for VLM")
    else:
        feedback_parts.append("⚠️ VLM not available for visual verification")
    
    score += vlm_trajectory_score + vlm_final_score
    
    # ================================================================
    # FINAL SCORING AND PASS/FAIL DETERMINATION
    # ================================================================
    
    # Key criteria for passing:
    # - File must exist and have been created during task
    # - Must have either valid date OR VLM confirmation
    
    key_criteria_met = (
        output_exists and
        (file_created or file_modified) and
        (contains_date or vlm_final_score >= 7)
    )
    
    passed = score >= 65 and key_criteria_met
    
    result_details['score_breakdown'] = {
        'file_exists': 10 if output_exists else 0,
        'timestamp_valid': 15 if (file_created or file_modified) else 0,
        'location_present': 15 if contains_location else 0,
        'coordinates_valid': 15 if coords_valid else (8 if contains_coords else 0),
        'date_format_valid': 15 if (contains_date and extracted_date) else (10 if contains_date else 0),
        'date_plausible': 10 if (year and min_year <= year <= max_year) else 0,
        'vlm_trajectory': vlm_trajectory_score,
        'vlm_final': vlm_final_score
    }
    
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback_parts),
        "message": f"Score: {score}/{max_score}" + (" - PASSED" if passed else " - FAILED"),
        "details": result_details
    }