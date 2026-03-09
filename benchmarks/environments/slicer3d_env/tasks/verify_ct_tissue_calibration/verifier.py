#!/usr/bin/env python3
"""
Verifier for CT Tissue Calibration Verification task.

VERIFICATION CRITERIA:
1. Air sample correct (20 points) - fiducial named 'air' at location with HU in [-1050, -950]
2. Fat sample correct (20 points) - fiducial named 'fat' at location with HU in [-150, -50]
3. Liver sample correct (25 points) - fiducial named 'liver' at location with HU in [30, 80]
4. Bone sample correct (25 points) - fiducial named 'bone' at location with HU in [300, 1500]
5. Fiducial spatial spread (5 points) - all fiducials are >20mm apart from each other
6. Screenshot evidence (5 points) - final screenshot shows fiducials in Slicer

Pass threshold: 70 points (at least 3 of 4 tissue samples correct)
"""

import json
import os
import tempfile
import logging
import math
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected HU ranges for each tissue type
EXPECTED_RANGES = {
    "air": {"min": -1050, "max": -950},
    "fat": {"min": -150, "max": -50},
    "liver": {"min": 30, "max": 80},
    "bone": {"min": 300, "max": 1500}
}

# Keywords to identify tissue types in fiducial names
TISSUE_KEYWORDS = {
    "air": ["air", "lung"],
    "fat": ["fat", "adipose", "subcutaneous"],
    "liver": ["liver", "hepat"],
    "bone": ["bone", "spine", "vertebr", "cortical"]
}


def identify_tissue_type(label: str) -> Optional[str]:
    """
    Identify the tissue type from a fiducial label.
    
    Args:
        label: The fiducial label/name
        
    Returns:
        Tissue type string or None if not identified
    """
    label_lower = label.lower()
    
    for tissue, keywords in TISSUE_KEYWORDS.items():
        for keyword in keywords:
            if keyword in label_lower:
                return tissue
    
    return None


def check_hu_in_range(hu_value: float, tissue_type: str) -> Tuple[bool, str]:
    """
    Check if a HU value is within the expected range for a tissue type.
    
    Args:
        hu_value: The sampled Hounsfield unit value
        tissue_type: The tissue type to check against
        
    Returns:
        Tuple of (is_valid, feedback_message)
    """
    if tissue_type not in EXPECTED_RANGES:
        return False, f"Unknown tissue type: {tissue_type}"
    
    range_def = EXPECTED_RANGES[tissue_type]
    min_hu = range_def["min"]
    max_hu = range_def["max"]
    
    if min_hu <= hu_value <= max_hu:
        return True, f"{tissue_type}: HU={hu_value:.1f} ✓ (expected {min_hu} to {max_hu})"
    else:
        return False, f"{tissue_type}: HU={hu_value:.1f} ✗ (expected {min_hu} to {max_hu})"


def calculate_distance(pos1: List[float], pos2: List[float]) -> float:
    """Calculate Euclidean distance between two 3D points."""
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(pos1, pos2)))


def check_spatial_spread(fiducials: List[Dict], min_separation: float = 20.0) -> Tuple[bool, str]:
    """
    Check if all fiducials are sufficiently spread apart.
    
    Args:
        fiducials: List of fiducial data with position_ras
        min_separation: Minimum required separation in mm
        
    Returns:
        Tuple of (all_spread, feedback_message)
    """
    positions = []
    for fid in fiducials:
        pos = fid.get("position_ras")
        if pos and len(pos) == 3:
            positions.append(pos)
    
    if len(positions) < 2:
        return True, "Less than 2 fiducials - spread check N/A"
    
    min_distance = float('inf')
    for i in range(len(positions)):
        for j in range(i + 1, len(positions)):
            dist = calculate_distance(positions[i], positions[j])
            min_distance = min(min_distance, dist)
    
    if min_distance >= min_separation:
        return True, f"Fiducials well spread (min distance: {min_distance:.1f}mm)"
    else:
        return False, f"Fiducials too close (min distance: {min_distance:.1f}mm < {min_separation}mm)"


def verify_ct_tissue_calibration(traj, env_info, task_info):
    """
    Verify CT tissue calibration task completion.
    
    Multi-criteria scoring based on:
    - Correct identification and sampling of each tissue type
    - HU values within expected clinical ranges
    - Proper spatial distribution of fiducials
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    min_separation = metadata.get('min_fiducial_separation_mm', 20)
    
    w_air = weights.get('air_sample_correct', 20)
    w_fat = weights.get('fat_sample_correct', 20)
    w_liver = weights.get('liver_sample_correct', 25)
    w_bone = weights.get('bone_sample_correct', 25)
    w_spread = weights.get('fiducial_spatial_spread', 5)
    w_screenshot = weights.get('screenshot_evidence', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/ct_calibration_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Try to copy detailed fiducials data
    temp_fiducials = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    fiducials_data = {"fiducials": []}
    try:
        copy_from_env("/tmp/sampled_fiducials.json", temp_fiducials.name)
        with open(temp_fiducials.name, 'r') as f:
            fiducials_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load detailed fiducials: {e}")
    finally:
        if os.path.exists(temp_fiducials.name):
            os.unlink(temp_fiducials.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    fiducial_count = result.get('fiducial_count', 0)
    details['fiducial_count'] = fiducial_count
    
    if fiducial_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No fiducials found - agent did not place any tissue markers"
        }
    
    # ================================================================
    # CRITERION 1: Air sample correct (20 points)
    # ================================================================
    air_valid = False
    air_found = result.get('air_found', False)
    air_hu_str = result.get('air_hu', '')
    
    if air_found and air_hu_str:
        try:
            air_hu = float(air_hu_str)
            air_valid, air_feedback = check_hu_in_range(air_hu, "air")
            details['air_hu'] = air_hu
            details['air_valid'] = air_valid
            
            if air_valid:
                score += w_air
                feedback_parts.append(f"Air: {air_hu:.0f} HU ✓")
            else:
                feedback_parts.append(f"Air: {air_hu:.0f} HU ✗ (expected -1050 to -950)")
        except ValueError:
            feedback_parts.append("Air: Invalid HU value")
    else:
        feedback_parts.append("Air: Not sampled")
        details['air_valid'] = False
    
    # ================================================================
    # CRITERION 2: Fat sample correct (20 points)
    # ================================================================
    fat_valid = False
    fat_found = result.get('fat_found', False)
    fat_hu_str = result.get('fat_hu', '')
    
    if fat_found and fat_hu_str:
        try:
            fat_hu = float(fat_hu_str)
            fat_valid, fat_feedback = check_hu_in_range(fat_hu, "fat")
            details['fat_hu'] = fat_hu
            details['fat_valid'] = fat_valid
            
            if fat_valid:
                score += w_fat
                feedback_parts.append(f"Fat: {fat_hu:.0f} HU ✓")
            else:
                feedback_parts.append(f"Fat: {fat_hu:.0f} HU ✗ (expected -150 to -50)")
        except ValueError:
            feedback_parts.append("Fat: Invalid HU value")
    else:
        feedback_parts.append("Fat: Not sampled")
        details['fat_valid'] = False
    
    # ================================================================
    # CRITERION 3: Liver sample correct (25 points)
    # ================================================================
    liver_valid = False
    liver_found = result.get('liver_found', False)
    liver_hu_str = result.get('liver_hu', '')
    
    if liver_found and liver_hu_str:
        try:
            liver_hu = float(liver_hu_str)
            liver_valid, liver_feedback = check_hu_in_range(liver_hu, "liver")
            details['liver_hu'] = liver_hu
            details['liver_valid'] = liver_valid
            
            if liver_valid:
                score += w_liver
                feedback_parts.append(f"Liver: {liver_hu:.0f} HU ✓")
            else:
                feedback_parts.append(f"Liver: {liver_hu:.0f} HU ✗ (expected 30 to 80)")
        except ValueError:
            feedback_parts.append("Liver: Invalid HU value")
    else:
        feedback_parts.append("Liver: Not sampled")
        details['liver_valid'] = False
    
    # ================================================================
    # CRITERION 4: Bone sample correct (25 points)
    # ================================================================
    bone_valid = False
    bone_found = result.get('bone_found', False)
    bone_hu_str = result.get('bone_hu', '')
    
    if bone_found and bone_hu_str:
        try:
            bone_hu = float(bone_hu_str)
            bone_valid, bone_feedback = check_hu_in_range(bone_hu, "bone")
            details['bone_hu'] = bone_hu
            details['bone_valid'] = bone_valid
            
            if bone_valid:
                score += w_bone
                feedback_parts.append(f"Bone: {bone_hu:.0f} HU ✓")
            else:
                feedback_parts.append(f"Bone: {bone_hu:.0f} HU ✗ (expected 300 to 1500)")
        except ValueError:
            feedback_parts.append("Bone: Invalid HU value")
    else:
        feedback_parts.append("Bone: Not sampled")
        details['bone_valid'] = False
    
    # ================================================================
    # CRITERION 5: Fiducial spatial spread (5 points)
    # ================================================================
    fiducials_list = fiducials_data.get('fiducials', [])
    if len(fiducials_list) >= 2:
        spread_valid, spread_feedback = check_spatial_spread(fiducials_list, min_separation)
        details['spread_valid'] = spread_valid
        
        if spread_valid:
            score += w_spread
            feedback_parts.append("Spread: OK")
        else:
            feedback_parts.append(f"Spread: Too close")
    else:
        # If we couldn't get detailed fiducials but have count >= 4, give partial credit
        if fiducial_count >= 4:
            score += w_spread // 2
            feedback_parts.append("Spread: Assumed OK")
        details['spread_valid'] = None
    
    # ================================================================
    # CRITERION 6: Screenshot evidence (5 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size', 0)
    
    if screenshot_exists and screenshot_size > 50000:  # >50KB
        score += w_screenshot
        feedback_parts.append("Screenshot: OK")
        details['screenshot_valid'] = True
    elif screenshot_exists:
        score += w_screenshot // 2
        feedback_parts.append("Screenshot: Small")
        details['screenshot_valid'] = True
    else:
        feedback_parts.append("Screenshot: Missing")
        details['screenshot_valid'] = False
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Count correct tissue samples
    correct_samples = sum([air_valid, fat_valid, liver_valid, bone_valid])
    details['correct_samples'] = correct_samples
    details['total_samples'] = 4
    
    # Pass threshold: at least 3 of 4 correct AND score >= 70
    key_criteria_met = correct_samples >= 3
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback = f"{correct_samples}/4 tissues correct | " + " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED ({score}/100): " + feedback
    else:
        if not key_criteria_met:
            feedback = f"FAILED ({score}/100): Need 3+ correct samples - " + feedback
        else:
            feedback = f"FAILED ({score}/100): Score below threshold - " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }