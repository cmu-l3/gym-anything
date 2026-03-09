#!/usr/bin/env python3
"""
Verifier for HU Tissue Characterization task.

VERIFICATION STRATEGY:
1. Check if report file exists and was created during task (anti-gaming)
2. Validate HU measurements against physiological ranges
3. Check for ROI/markup creation
4. Score based on correct tissue characterization

HU Expected Ranges:
- Subcutaneous fat: -150 to -30 HU
- Skeletal muscle: 10 to 70 HU
- Liver parenchyma: 40 to 150 HU (contrast-enhanced)
- Aortic blood: 100 to 350 HU (contrast-enhanced)
- Vertebral bone: 100 to 500 HU (cancellous)

Scoring (100 points total):
- Fat HU correct: 15 points
- Muscle HU correct: 15 points
- Liver HU correct: 15 points
- Blood HU correct: 15 points
- Bone HU correct: 15 points
- All ROIs created: 10 points
- Report complete: 10 points
- ROI size adequate: 5 points
"""

import json
import os
import sys
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# HU ranges for each tissue type
HU_RANGES = {
    "subcutaneous_fat": {"min": -150, "max": -30, "typical": -100},
    "fat": {"min": -150, "max": -30, "typical": -100},
    "skeletal_muscle": {"min": 10, "max": 70, "typical": 45},
    "muscle": {"min": 10, "max": 70, "typical": 45},
    "psoas": {"min": 10, "max": 70, "typical": 45},
    "paraspinal": {"min": 10, "max": 70, "typical": 45},
    "liver_parenchyma": {"min": 40, "max": 150, "typical": 70},
    "liver": {"min": 40, "max": 150, "typical": 70},
    "aortic_blood": {"min": 100, "max": 350, "typical": 200},
    "aorta": {"min": 100, "max": 350, "typical": 200},
    "blood": {"min": 100, "max": 350, "typical": 200},
    "vertebral_bone": {"min": 100, "max": 500, "typical": 250},
    "bone": {"min": 100, "max": 500, "typical": 250},
    "vertebra": {"min": 100, "max": 500, "typical": 250},
    "spine": {"min": 100, "max": 500, "typical": 250},
}

# Mapping of tissue categories
TISSUE_CATEGORIES = {
    "fat": ["subcutaneous_fat", "fat", "adipose", "subcutaneous"],
    "muscle": ["skeletal_muscle", "muscle", "psoas", "paraspinal", "rectus"],
    "liver": ["liver_parenchyma", "liver", "hepatic"],
    "blood": ["aortic_blood", "aorta", "blood", "vessel", "arterial"],
    "bone": ["vertebral_bone", "bone", "vertebra", "spine", "vertebral", "cancellous"],
}


def normalize_tissue_name(name):
    """Normalize tissue name for matching."""
    if not name:
        return ""
    name = name.lower().strip()
    name = re.sub(r'[_\-\s]+', '_', name)
    return name


def classify_tissue(name):
    """
    Classify a tissue name into one of the 5 categories.
    Returns: 'fat', 'muscle', 'liver', 'blood', 'bone', or None
    """
    name = normalize_tissue_name(name)
    
    for category, keywords in TISSUE_CATEGORIES.items():
        for keyword in keywords:
            if keyword in name or name in keyword:
                return category
    
    return None


def get_hu_range_for_tissue(tissue_name):
    """Get the expected HU range for a tissue name."""
    name = normalize_tissue_name(tissue_name)
    
    # Direct match
    if name in HU_RANGES:
        return HU_RANGES[name]
    
    # Try partial match
    for key, ranges in HU_RANGES.items():
        if key in name or name in key:
            return ranges
    
    # Try category match
    category = classify_tissue(tissue_name)
    if category:
        category_map = {
            "fat": "subcutaneous_fat",
            "muscle": "skeletal_muscle",
            "liver": "liver_parenchyma",
            "blood": "aortic_blood",
            "bone": "vertebral_bone",
        }
        return HU_RANGES.get(category_map.get(category, ""), None)
    
    return None


def is_hu_in_range(hu_value, tissue_name):
    """
    Check if a HU value is within the expected range for a tissue.
    Returns: (is_correct, expected_range_dict or None)
    """
    if hu_value is None:
        return False, None
    
    try:
        hu = float(hu_value)
    except (ValueError, TypeError):
        return False, None
    
    expected = get_hu_range_for_tissue(tissue_name)
    if not expected:
        return False, None
    
    is_correct = expected["min"] <= hu <= expected["max"]
    return is_correct, expected


def verify_hu_tissue_characterization(traj, env_info, task_info):
    """
    Verify HU tissue characterization task completion.
    
    Scoring (100 points total):
    - Fat HU correct: 15 points
    - Muscle HU correct: 15 points
    - Liver HU correct: 15 points
    - Blood HU correct: 15 points
    - Bone HU correct: 15 points
    - All ROIs created: 10 points
    - Report complete: 10 points
    - ROI size adequate: 5 points
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
    
    w_fat = weights.get('fat_hu_correct', 15)
    w_muscle = weights.get('muscle_hu_correct', 15)
    w_liver = weights.get('liver_hu_correct', 15)
    w_blood = weights.get('blood_hu_correct', 15)
    w_bone = weights.get('bone_hu_correct', 15)
    w_rois = weights.get('all_rois_created', 10)
    w_report = weights.get('report_complete', 10)
    w_roi_size = weights.get('roi_size_adequate', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/hu_task_result.json", temp_result.name)
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
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer was not running")
        # Continue anyway to check files
    
    # ================================================================
    # ANTI-GAMING: Check if files were created during task
    # ================================================================
    report_created = result.get('report_created_during_task', False)
    rois_created = result.get('rois_created_during_task', False)
    
    if not report_created and not rois_created:
        details['anti_gaming'] = "No files created during task"
        # Could be files existed before - still check content
    
    # ================================================================
    # LOAD AGENT'S REPORT
    # ================================================================
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_report = {}
    try:
        copy_from_env("/tmp/agent_hu_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load agent report: {e}")
        details['report_load_error'] = str(e)
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    # ================================================================
    # CHECK ROIs
    # ================================================================
    rois_count = result.get('rois_count', 0)
    details['rois_count'] = rois_count
    
    if rois_count >= 5:
        score += w_rois
        feedback_parts.append(f"✓ All 5 ROIs created ({rois_count} found)")
    elif rois_count > 0:
        partial = int(w_rois * (rois_count / 5))
        score += partial
        feedback_parts.append(f"△ Partial ROIs ({rois_count}/5)")
    else:
        feedback_parts.append("✗ No ROIs found")
    
    # ================================================================
    # CHECK REPORT COMPLETENESS
    # ================================================================
    measurements = agent_report.get('measurements', [])
    measurements_count = len(measurements)
    details['measurements_count'] = measurements_count
    
    if measurements_count >= 5:
        score += w_report
        feedback_parts.append(f"✓ Report complete ({measurements_count} measurements)")
    elif measurements_count > 0:
        partial = int(w_report * (measurements_count / 5))
        score += partial
        feedback_parts.append(f"△ Partial report ({measurements_count}/5)")
    else:
        feedback_parts.append("✗ No measurements in report")
        # Early return if no report
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # VERIFY HU VALUES FOR EACH TISSUE
    # ================================================================
    tissue_results = {
        "fat": {"found": False, "correct": False, "hu": None, "expected": None},
        "muscle": {"found": False, "correct": False, "hu": None, "expected": None},
        "liver": {"found": False, "correct": False, "hu": None, "expected": None},
        "blood": {"found": False, "correct": False, "hu": None, "expected": None},
        "bone": {"found": False, "correct": False, "hu": None, "expected": None},
    }
    
    for measurement in measurements:
        tissue_name = measurement.get('tissue', '')
        hu_value = measurement.get('mean_hu', measurement.get('hu', measurement.get('hu_value')))
        
        if hu_value is None:
            continue
        
        try:
            hu = float(hu_value)
        except (ValueError, TypeError):
            continue
        
        # Classify this measurement
        category = classify_tissue(tissue_name)
        
        if category and category in tissue_results:
            tissue_results[category]['found'] = True
            tissue_results[category]['hu'] = hu
            
            # Check if HU is in expected range
            is_correct, expected = is_hu_in_range(hu, tissue_name)
            tissue_results[category]['correct'] = is_correct
            tissue_results[category]['expected'] = expected
    
    details['tissue_results'] = tissue_results
    
    # Score each tissue
    weight_map = {
        "fat": w_fat,
        "muscle": w_muscle,
        "liver": w_liver,
        "blood": w_blood,
        "bone": w_bone,
    }
    
    correct_count = 0
    for tissue, result_data in tissue_results.items():
        weight = weight_map.get(tissue, 15)
        
        if result_data['correct']:
            score += weight
            correct_count += 1
            hu = result_data['hu']
            expected = result_data['expected']
            feedback_parts.append(f"✓ {tissue.capitalize()} HU correct ({hu:.0f} in [{expected['min']}, {expected['max']}])")
        elif result_data['found']:
            hu = result_data['hu']
            expected = result_data['expected']
            if expected:
                feedback_parts.append(f"✗ {tissue.capitalize()} HU incorrect ({hu:.0f}, expected [{expected['min']}, {expected['max']}])")
            else:
                feedback_parts.append(f"? {tissue.capitalize()} HU could not verify ({hu:.0f})")
        else:
            feedback_parts.append(f"✗ {tissue.capitalize()} not measured")
    
    details['correct_tissues'] = correct_count
    
    # ================================================================
    # ROI SIZE CHECK (bonus)
    # ================================================================
    # If we have ROI data with size info, check adequacy
    temp_rois = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    rois_data = {}
    try:
        copy_from_env("/tmp/agent_tissue_rois.json", temp_rois.name)
        with open(temp_rois.name, 'r') as f:
            rois_data = json.load(f)
        
        markups = rois_data.get('markups', [])
        roi_sizes_adequate = True
        
        for markup in markups:
            if markup.get('type') == 'roi':
                size = markup.get('size_mm', [0, 0, 0])
                if isinstance(size, list) and len(size) >= 2:
                    area = size[0] * size[1]
                    if area < 50:  # 50 mm² minimum
                        roi_sizes_adequate = False
        
        if roi_sizes_adequate and len(markups) >= 5:
            score += w_roi_size
            feedback_parts.append("✓ ROI sizes adequate")
        elif len(markups) > 0:
            score += w_roi_size // 2
            feedback_parts.append("△ Some ROIs may be too small")
    except Exception as e:
        logger.debug(f"Could not check ROI sizes: {e}")
        # Give benefit of doubt if we can't check
        if rois_count >= 5:
            score += w_roi_size // 2
    finally:
        if os.path.exists(temp_rois.name):
            os.unlink(temp_rois.name)
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    min_correct = metadata.get('passing_thresholds', {}).get('min_correct_tissues', 3)
    min_score = metadata.get('passing_thresholds', {}).get('min_score', 60)
    
    passed = (correct_count >= min_correct) and (score >= min_score)
    
    # Final feedback
    summary = f"Score: {score}/100 | Correct tissues: {correct_count}/5"
    if passed:
        summary = f"PASSED - {summary}"
    else:
        summary = f"FAILED - {summary}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": summary + " | " + " | ".join(feedback_parts),
        "details": details
    }