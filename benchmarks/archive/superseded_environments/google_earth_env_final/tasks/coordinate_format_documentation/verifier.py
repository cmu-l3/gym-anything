#!/usr/bin/env python3
"""
Verifier for Coordinate Format Documentation task.

Task: Navigate to Mont Blanc summit and document coordinates in three formats:
- Decimal Degrees
- Degrees-Minutes-Seconds (DMS)
- Universal Transverse Mercator (UTM)

VERIFICATION STRATEGY (Multi-Signal):
1. File exists at correct path (10 pts)
2. File created during task - anti-gaming (10 pts)
3. Decimal degrees parsed and correct (20 pts)
4. DMS format parsed and correct (20 pts)
5. UTM format parsed and correct (20 pts)
6. VLM trajectory verification - shows navigation and options dialog (20 pts)

Pass threshold: 60 points with file created during task
"""

import json
import tempfile
import os
import re
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth for Mont Blanc summit
GROUND_TRUTH = {
    "decimal": {
        "lat": 45.8326,
        "lon": 6.8652,
        "tolerance": 0.01  # Allow ~1km tolerance
    },
    "dms": {
        "lat_d": 45, "lat_m": 49, "lat_s": 57,
        "lon_d": 6, "lon_m": 51, "lon_s": 55,
        "tolerance_sec": 30  # Allow 30 arc-seconds tolerance
    },
    "utm": {
        "zone": "32T",
        "easting": 343500,
        "northing": 5078100,
        "tolerance_m": 500  # Allow 500m tolerance
    }
}


def parse_decimal_degrees(content: str) -> Tuple[Optional[float], Optional[float]]:
    """Extract decimal degree coordinates from file content."""
    lat = None
    lon = None
    
    # Pattern 1: Labeled latitude/longitude
    lat_match = re.search(r'[Ll]at(?:itude)?[:\s]+(-?\d+\.?\d*)', content)
    if lat_match:
        lat = float(lat_match.group(1))
    
    lon_match = re.search(r'[Ll]on(?:gitude)?[:\s]+(-?\d+\.?\d*)', content)
    if lon_match:
        lon = float(lon_match.group(1))
    
    # Pattern 2: Coordinate pair with degrees symbol
    if lat is None or lon is None:
        pair_match = re.search(r'(\d{1,2}\.\d{2,6})[°\s,]+(\d{1,2}\.\d{2,6})', content)
        if pair_match:
            val1, val2 = float(pair_match.group(1)), float(pair_match.group(2))
            # Assume larger value is latitude for Mont Blanc region
            if val1 > val2:
                lat, lon = val1, val2
            else:
                lat, lon = val2, val1
    
    # Pattern 3: N/E suffixed values
    if lat is None:
        n_match = re.search(r'(\d+\.?\d*)[°\s]*N', content, re.IGNORECASE)
        if n_match:
            lat = float(n_match.group(1))
    
    if lon is None:
        e_match = re.search(r'(\d+\.?\d*)[°\s]*E', content, re.IGNORECASE)
        if e_match:
            lon = float(e_match.group(1))
    
    return lat, lon


def parse_dms(content: str) -> Tuple[Optional[Tuple], Optional[Tuple]]:
    """Extract DMS coordinates from file content."""
    # Pattern: 45°49'57"N or 45 49 57 N or 45°49'57.5"N
    dms_pattern = r"(\d+)[°\s]+(\d+)['\s]+(\d+(?:\.\d+)?)[\"'\s]*([NSEW])"
    
    matches = re.findall(dms_pattern, content, re.IGNORECASE)
    
    lat = None
    lon = None
    
    for match in matches:
        deg, min_val, sec, direction = match
        value = (int(deg), int(min_val), float(sec))
        
        if direction.upper() in 'NS':
            lat = value
        elif direction.upper() in 'EW':
            lon = value
    
    return lat, lon


def parse_utm(content: str) -> Tuple[Optional[str], Optional[int], Optional[int]]:
    """Extract UTM coordinates from file content."""
    zone = None
    easting = None
    northing = None
    
    # Pattern 1: Zone Easting Northing (e.g., 32T 343500 5078100)
    utm_pattern = r'(\d{1,2}[A-Za-z])\s+(\d{5,7})[mE\s]+(\d{6,8})'
    match = re.search(utm_pattern, content)
    if match:
        return match.group(1).upper(), int(match.group(2)), int(match.group(3))
    
    # Pattern 2: Labeled components
    zone_match = re.search(r'[Zz]one[:\s]+(\d{1,2}[A-Za-z])', content)
    if zone_match:
        zone = zone_match.group(1).upper()
    
    east_match = re.search(r'[Ee]ast(?:ing)?[:\s]+(\d{5,7})', content)
    if east_match:
        easting = int(east_match.group(1))
    
    north_match = re.search(r'[Nn]orth(?:ing)?[:\s]+(\d{6,8})', content)
    if north_match:
        northing = int(north_match.group(1))
    
    # Pattern 3: E: and N: format
    if easting is None:
        e_match = re.search(r'E[:\s]+(\d{5,7})', content)
        if e_match:
            easting = int(e_match.group(1))
    
    if northing is None:
        n_match = re.search(r'N[:\s]+(\d{6,8})', content)
        if n_match:
            northing = int(n_match.group(1))
    
    return zone, easting, northing


def verify_decimal(content: str) -> Tuple[int, str]:
    """Verify decimal degree coordinates. Returns (score, feedback)."""
    lat, lon = parse_decimal_degrees(content)
    
    if lat is None or lon is None:
        return 0, "Could not parse decimal degree coordinates"
    
    gt = GROUND_TRUTH["decimal"]
    lat_diff = abs(lat - gt["lat"])
    lon_diff = abs(lon - gt["lon"])
    
    if lat_diff <= gt["tolerance"] and lon_diff <= gt["tolerance"]:
        return 20, f"Decimal degrees correct ({lat:.4f}, {lon:.4f})"
    elif lat_diff <= gt["tolerance"] * 2 and lon_diff <= gt["tolerance"] * 2:
        return 10, f"Decimal degrees close but not precise ({lat:.4f}, {lon:.4f})"
    else:
        return 0, f"Decimal degrees incorrect ({lat:.4f}, {lon:.4f}), expected ~({gt['lat']}, {gt['lon']})"


def dms_to_seconds(d: int, m: int, s: float) -> float:
    """Convert DMS to total arc-seconds."""
    return d * 3600 + m * 60 + s


def verify_dms(content: str) -> Tuple[int, str]:
    """Verify DMS coordinates. Returns (score, feedback)."""
    lat, lon = parse_dms(content)
    
    if lat is None or lon is None:
        return 0, "Could not parse DMS coordinates"
    
    gt = GROUND_TRUTH["dms"]
    
    # Convert to total seconds for comparison
    gt_lat_sec = dms_to_seconds(gt["lat_d"], gt["lat_m"], gt["lat_s"])
    gt_lon_sec = dms_to_seconds(gt["lon_d"], gt["lon_m"], gt["lon_s"])
    
    parsed_lat_sec = dms_to_seconds(*lat)
    parsed_lon_sec = dms_to_seconds(*lon)
    
    lat_diff = abs(parsed_lat_sec - gt_lat_sec)
    lon_diff = abs(parsed_lon_sec - gt_lon_sec)
    
    lat_str = f"{lat[0]}°{lat[1]}'{lat[2]}\""
    lon_str = f"{lon[0]}°{lon[1]}'{lon[2]}\""
    
    if lat_diff <= gt["tolerance_sec"] and lon_diff <= gt["tolerance_sec"]:
        return 20, f"DMS coordinates correct ({lat_str}N, {lon_str}E)"
    elif lat_diff <= gt["tolerance_sec"] * 2 and lon_diff <= gt["tolerance_sec"] * 2:
        return 10, f"DMS coordinates close ({lat_str}N, {lon_str}E)"
    else:
        return 0, f"DMS coordinates incorrect, error: lat={lat_diff:.0f}s, lon={lon_diff:.0f}s"


def verify_utm(content: str) -> Tuple[int, str]:
    """Verify UTM coordinates. Returns (score, feedback)."""
    zone, easting, northing = parse_utm(content)
    
    if zone is None or easting is None or northing is None:
        return 0, f"Could not parse complete UTM coordinates (zone={zone}, E={easting}, N={northing})"
    
    gt = GROUND_TRUTH["utm"]
    
    # Check zone (must match exactly or be adjacent)
    zone_correct = zone.upper() == gt["zone"]
    
    if not zone_correct:
        return 0, f"UTM zone incorrect ({zone}), expected {gt['zone']}"
    
    # Check coordinates with tolerance
    east_diff = abs(easting - gt["easting"])
    north_diff = abs(northing - gt["northing"])
    
    if east_diff <= gt["tolerance_m"] and north_diff <= gt["tolerance_m"]:
        return 20, f"UTM coordinates correct ({zone} {easting}E {northing}N)"
    elif east_diff <= gt["tolerance_m"] * 2 and north_diff <= gt["tolerance_m"] * 2:
        return 10, f"UTM coordinates close ({zone} {easting}E {northing}N)"
    else:
        return 0, f"UTM coordinates too far off (E:{east_diff:.0f}m, N:{north_diff:.0f}m error)"


def check_format_labels(content: str) -> Tuple[int, str]:
    """Check if coordinate formats are labeled. Returns (score, feedback)."""
    labels_found = []
    
    if re.search(r'[Dd]ecimal|[Dd]eg.*[Dd]ecimal|DD', content):
        labels_found.append("Decimal")
    if re.search(r'DMS|[Dd]egrees.*[Mm]inutes.*[Ss]econds?|D.*M.*S', content):
        labels_found.append("DMS")
    if re.search(r'UTM|[Uu]niversal.*[Tt]ransverse|[Mm]ercator', content):
        labels_found.append("UTM")
    
    if len(labels_found) >= 2:
        return 5, f"Format labels present: {', '.join(labels_found)}"
    elif len(labels_found) == 1:
        return 2, f"Partial labels: {', '.join(labels_found)}"
    else:
        return 0, "No format labels found"


# VLM verification prompt for trajectory analysis
VLM_TRAJECTORY_PROMPT = """You are analyzing screenshots from an agent performing a coordinate documentation task in Google Earth Pro.

The agent was asked to:
1. Navigate to Mont Blanc summit (Alps mountain)
2. Open Tools → Options → 3D View to change coordinate format display
3. Record coordinates in multiple formats (Decimal, DMS, UTM)

Analyze these trajectory screenshots and determine:

1. NAVIGATION: Did the agent navigate to a mountainous/alpine region? Is Mont Blanc or Alps visible?
2. OPTIONS_DIALOG: Did the agent open the Options/Preferences dialog? Is the 3D View tab visible?
3. COORDINATE_CHANGES: Did the coordinate display format change between screenshots (visible in status bar)?
4. TEXT_EDITING: Did the agent create or edit a text file to save coordinates?

Look for:
- Google Earth showing mountainous terrain (snow-capped peaks)
- Options dialog with coordinate format dropdown
- Status bar showing coordinates in different formats
- Text editor window with coordinate information

Respond in JSON format:
{
    "navigation_to_alps": true/false,
    "options_dialog_opened": true/false,
    "coordinate_formats_changed": true/false,
    "text_file_interaction": true/false,
    "google_earth_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}
"""


def verify_via_vlm(traj: Dict[str, Any], env_info: Dict[str, Any]) -> Tuple[int, str, Dict]:
    """Verify task completion using VLM on trajectory frames."""
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return 0, "VLM not available", {}
    
    # Get trajectory frames (use framework's trajectory sampling)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            return 0, "No trajectory frames available", {}
        
    except ImportError:
        # Fallback: try to get frames from traj dict directly
        frames = traj.get('frames', [])
        if not frames:
            return 0, "Could not access trajectory frames", {}
        # Sample evenly
        if len(frames) > 5:
            indices = [int(i * len(frames) / 5) for i in range(5)]
            frames = [frames[i] for i in indices]
    
    # Query VLM with trajectory frames
    try:
        vlm_result = query_vlm(
            prompt=VLM_TRAJECTORY_PROMPT,
            images=frames
        )
        
        if not vlm_result.get("success"):
            return 0, f"VLM query failed: {vlm_result.get('error', 'unknown')}", {}
        
        parsed = vlm_result.get("parsed", {})
        
        # Score based on VLM findings
        vlm_score = 0
        vlm_feedback = []
        
        if parsed.get("google_earth_visible", False):
            vlm_score += 4
            vlm_feedback.append("Google Earth visible")
        
        if parsed.get("navigation_to_alps", False):
            vlm_score += 4
            vlm_feedback.append("Navigation to Alps region")
        
        if parsed.get("options_dialog_opened", False):
            vlm_score += 6
            vlm_feedback.append("Options dialog accessed")
        
        if parsed.get("coordinate_formats_changed", False):
            vlm_score += 4
            vlm_feedback.append("Coordinate formats changed")
        
        if parsed.get("text_file_interaction", False):
            vlm_score += 2
            vlm_feedback.append("Text file interaction")
        
        confidence = parsed.get("confidence", "low")
        if confidence == "low":
            vlm_score = int(vlm_score * 0.7)
        elif confidence == "medium":
            vlm_score = int(vlm_score * 0.85)
        
        feedback_str = "; ".join(vlm_feedback) if vlm_feedback else "No workflow evidence found"
        return vlm_score, feedback_str, parsed
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return 0, f"VLM error: {str(e)}", {}


def verify_coordinate_format_documentation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main verification function for Coordinate Format Documentation task.
    
    Uses multiple independent signals:
    1. File existence and timestamp (anti-gaming)
    2. Coordinate parsing and validation
    3. VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    feedback_parts = []
    details = {}
    score = 0
    max_score = 100
    
    # ================================================================
    # STEP 1: Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists (10 points)
    # ================================================================
    output_info = result.get('output_file', {})
    output_exists = output_info.get('exists', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ Output file exists (+10)")
    else:
        feedback_parts.append("❌ Output file NOT found")
        # Can still get partial credit from VLM
        vlm_score, vlm_feedback, vlm_details = verify_via_vlm(traj, env_info)
        score += vlm_score
        feedback_parts.append(f"VLM: {vlm_feedback} (+{vlm_score})")
        
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = output_info.get('created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task (+10)")
    else:
        feedback_parts.append("⚠️ File may predate task (timestamp issue)")
        # Don't add points but don't fail entirely
    
    # ================================================================
    # Get file content for parsing
    # ================================================================
    file_content = output_info.get('content', '')
    if isinstance(file_content, str):
        # Content was JSON-escaped in export, should be fine
        pass
    else:
        file_content = str(file_content)
    
    details['file_content_length'] = len(file_content)
    
    if len(file_content) < 20:
        feedback_parts.append("❌ File content too short")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 3: Decimal degrees correct (20 points)
    # ================================================================
    decimal_score, decimal_feedback = verify_decimal(file_content)
    score += decimal_score
    if decimal_score > 0:
        feedback_parts.append(f"✅ {decimal_feedback} (+{decimal_score})")
    else:
        feedback_parts.append(f"❌ {decimal_feedback}")
    details['decimal_verification'] = decimal_feedback
    
    # ================================================================
    # CRITERION 4: DMS format correct (20 points)
    # ================================================================
    dms_score, dms_feedback = verify_dms(file_content)
    score += dms_score
    if dms_score > 0:
        feedback_parts.append(f"✅ {dms_feedback} (+{dms_score})")
    else:
        feedback_parts.append(f"❌ {dms_feedback}")
    details['dms_verification'] = dms_feedback
    
    # ================================================================
    # CRITERION 5: UTM format correct (20 points)
    # ================================================================
    utm_score, utm_feedback = verify_utm(file_content)
    score += utm_score
    if utm_score > 0:
        feedback_parts.append(f"✅ {utm_feedback} (+{utm_score})")
    else:
        feedback_parts.append(f"❌ {utm_feedback}")
    details['utm_verification'] = utm_feedback
    
    # ================================================================
    # CRITERION 6: Format labels present (5 points bonus)
    # ================================================================
    label_score, label_feedback = check_format_labels(file_content)
    score += label_score
    if label_score > 0:
        feedback_parts.append(f"✅ {label_feedback} (+{label_score})")
    details['labels_verification'] = label_feedback
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (15 points)
    # ================================================================
    vlm_score, vlm_feedback, vlm_details = verify_via_vlm(traj, env_info)
    # Cap VLM contribution
    vlm_score = min(vlm_score, 15)
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"✅ VLM trajectory: {vlm_feedback} (+{vlm_score})")
    else:
        feedback_parts.append(f"⚠️ VLM: {vlm_feedback}")
    details['vlm_verification'] = vlm_details
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Count how many coordinate formats were correct
    formats_correct = sum([
        1 if decimal_score >= 10 else 0,
        1 if dms_score >= 10 else 0,
        1 if utm_score >= 10 else 0
    ])
    
    # Pass criteria: 60+ points AND (file created during task OR 2+ formats correct)
    key_criteria_met = file_created_during_task or formats_correct >= 2
    passed = score >= 60 and key_criteria_met
    
    # Cap score at 100
    score = min(score, 100)
    
    details['formats_correct'] = formats_correct
    details['key_criteria_met'] = key_criteria_met
    details['final_score'] = score
    
    feedback_parts.append(f"Final: {score}/100, formats correct: {formats_correct}/3")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }