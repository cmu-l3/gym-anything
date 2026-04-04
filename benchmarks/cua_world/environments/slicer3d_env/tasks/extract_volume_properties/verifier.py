#!/usr/bin/env python3
"""
Verifier for extract_volume_properties task.

VERIFICATION STRATEGY (Multi-criteria with anti-gaming):

Programmatic checks (100 points total):
1. File exists (15 pts) - Output JSON file was created
2. Valid JSON format (10 pts) - File parses as valid JSON with required keys
3. Volume name correct (10 pts) - Recorded name matches "MRHead"
4. Dimensions correct (25 pts) - All three dimension values match exactly
5. Spacing correct (25 pts) - All three spacing values within tolerance
6. Scalar type correct (10 pts) - Data type matches actual volume type
7. Number of components correct (5 pts) - Component count matches

Anti-gaming measures:
- File must be created AFTER task start (timestamp check)
- Values must match actual volume properties (can't guess)
- All three dimension/spacing values must be correct together

Pass threshold: 70 points (requires dimensions AND spacing correct)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_volume_properties(traj, env_info, task_info):
    """
    Verify that volume properties were correctly extracted and saved.
    
    Uses multi-criteria scoring with anti-gaming timestamp checks.
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
    spacing_tolerance = metadata.get('spacing_tolerance_mm', 0.01)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('file_exists', 15)
    w_valid_json = weights.get('valid_json', 10)
    w_volume_name = weights.get('volume_name_correct', 10)
    w_dimensions = weights.get('dimensions_correct', 25)
    w_spacing = weights.get('spacing_correct', 25)
    w_scalar_type = weights.get('scalar_type_correct', 10)
    w_num_components = weights.get('num_components_correct', 5)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/volume_properties_task_result.json", temp_result.name)
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

    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists:
        if file_created_during_task:
            score += w_file_exists
            feedback_parts.append("Output file created during task")
        else:
            # File exists but wasn't created during task - possible gaming
            score += w_file_exists // 2
            feedback_parts.append("Output file exists (pre-existing)")
        details['file_exists'] = True
        details['file_created_during_task'] = file_created_during_task
    else:
        feedback_parts.append("Output file NOT found")
        details['file_exists'] = False
        # Can't proceed without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Valid JSON format (10 points)
    # ================================================================
    output_valid = result.get('output_valid_json', False)
    
    if output_valid:
        score += w_valid_json
        feedback_parts.append("Valid JSON format")
        details['valid_json'] = True
    else:
        feedback_parts.append("Invalid JSON format")
        details['valid_json'] = False
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # Get ground truth and reported values
    # ================================================================
    gt_dimensions = result.get('gt_dimensions', [])
    gt_spacing = result.get('gt_spacing', [])
    gt_scalar_type = result.get('gt_scalar_type', '').lower()
    gt_num_components = result.get('gt_num_components', 1)
    
    reported_dimensions = result.get('reported_dimensions', [])
    reported_spacing = result.get('reported_spacing', [])
    reported_scalar_type = result.get('reported_scalar_type', '').lower()
    reported_num_components = result.get('reported_num_components', 0)
    reported_volume_name = result.get('reported_volume_name', '').lower()
    
    details['gt_dimensions'] = gt_dimensions
    details['gt_spacing'] = gt_spacing
    details['gt_scalar_type'] = gt_scalar_type
    details['gt_num_components'] = gt_num_components
    details['reported_dimensions'] = reported_dimensions
    details['reported_spacing'] = reported_spacing
    details['reported_scalar_type'] = reported_scalar_type
    details['reported_num_components'] = reported_num_components
    details['reported_volume_name'] = reported_volume_name

    # ================================================================
    # CRITERION 3: Volume name correct (10 points)
    # ================================================================
    if 'mrhead' in reported_volume_name:
        score += w_volume_name
        feedback_parts.append("Volume name correct")
        details['volume_name_match'] = True
    else:
        feedback_parts.append(f"Volume name incorrect: '{reported_volume_name}'")
        details['volume_name_match'] = False

    # ================================================================
    # CRITERION 4: Dimensions correct (25 points)
    # All three values must match exactly
    # ================================================================
    dimensions_correct = False
    
    if isinstance(reported_dimensions, list) and len(reported_dimensions) >= 3:
        if isinstance(gt_dimensions, list) and len(gt_dimensions) >= 3:
            try:
                match_count = sum(
                    int(reported_dimensions[i]) == int(gt_dimensions[i])
                    for i in range(3)
                )
                
                if match_count == 3:
                    score += w_dimensions
                    feedback_parts.append(f"Dimensions correct: {reported_dimensions[:3]}")
                    dimensions_correct = True
                elif match_count >= 2:
                    # Partial credit for 2/3 correct
                    score += w_dimensions * 2 // 3
                    feedback_parts.append(f"Dimensions partially correct ({match_count}/3)")
                else:
                    feedback_parts.append(f"Dimensions incorrect: {reported_dimensions[:3]} vs {gt_dimensions[:3]}")
                    
                details['dimensions_match_count'] = match_count
            except (ValueError, TypeError) as e:
                feedback_parts.append(f"Dimensions format error: {e}")
                details['dimensions_error'] = str(e)
        else:
            feedback_parts.append("Ground truth dimensions not available")
    else:
        feedback_parts.append("Dimensions not reported or invalid format")
    
    details['dimensions_correct'] = dimensions_correct

    # ================================================================
    # CRITERION 5: Spacing correct (25 points)
    # All three values must be within tolerance
    # ================================================================
    spacing_correct = False
    
    if isinstance(reported_spacing, list) and len(reported_spacing) >= 3:
        if isinstance(gt_spacing, list) and len(gt_spacing) >= 3:
            try:
                match_count = 0
                for i in range(3):
                    diff = abs(float(reported_spacing[i]) - float(gt_spacing[i]))
                    if diff <= spacing_tolerance:
                        match_count += 1
                
                if match_count == 3:
                    score += w_spacing
                    feedback_parts.append(f"Spacing correct: {reported_spacing[:3]}")
                    spacing_correct = True
                elif match_count >= 2:
                    score += w_spacing * 2 // 3
                    feedback_parts.append(f"Spacing partially correct ({match_count}/3)")
                else:
                    feedback_parts.append(f"Spacing incorrect: {reported_spacing[:3]} vs {gt_spacing[:3]}")
                
                details['spacing_match_count'] = match_count
            except (ValueError, TypeError) as e:
                feedback_parts.append(f"Spacing format error: {e}")
                details['spacing_error'] = str(e)
        else:
            feedback_parts.append("Ground truth spacing not available")
    else:
        feedback_parts.append("Spacing not reported or invalid format")
    
    details['spacing_correct'] = spacing_correct

    # ================================================================
    # CRITERION 6: Scalar type correct (10 points)
    # ================================================================
    # Normalize type names for comparison
    type_equivalents = {
        'short': ['short', 'int16', 'signed short'],
        'unsigned short': ['unsigned short', 'uint16', 'ushort'],
        'int': ['int', 'int32', 'signed int'],
        'unsigned int': ['unsigned int', 'uint32', 'uint'],
        'float': ['float', 'float32'],
        'double': ['double', 'float64'],
        'char': ['char', 'int8', 'signed char'],
        'unsigned char': ['unsigned char', 'uint8', 'uchar'],
    }
    
    def normalize_type(t):
        t = t.lower().strip()
        for canonical, variants in type_equivalents.items():
            if t in variants or t == canonical:
                return canonical
        return t
    
    normalized_reported = normalize_type(reported_scalar_type)
    normalized_gt = normalize_type(gt_scalar_type)
    
    if normalized_reported and normalized_gt:
        if normalized_reported == normalized_gt:
            score += w_scalar_type
            feedback_parts.append(f"Scalar type correct: {reported_scalar_type}")
            details['scalar_type_match'] = True
        else:
            feedback_parts.append(f"Scalar type incorrect: '{reported_scalar_type}' vs '{gt_scalar_type}'")
            details['scalar_type_match'] = False
    else:
        feedback_parts.append("Scalar type not reported")
        details['scalar_type_match'] = False

    # ================================================================
    # CRITERION 7: Number of components correct (5 points)
    # ================================================================
    try:
        if int(reported_num_components) == int(gt_num_components):
            score += w_num_components
            feedback_parts.append(f"Num components correct: {reported_num_components}")
            details['num_components_match'] = True
        else:
            feedback_parts.append(f"Num components incorrect: {reported_num_components} vs {gt_num_components}")
            details['num_components_match'] = False
    except (ValueError, TypeError):
        feedback_parts.append("Num components not reported or invalid")
        details['num_components_match'] = False

    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Pass requires: file created during task + dimensions correct + spacing correct
    key_criteria_met = (
        file_created_during_task and
        dimensions_correct and
        spacing_correct
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Bonus feedback
    if passed:
        feedback_parts.append("PASSED - All key criteria met")
    elif score >= 70:
        feedback_parts.append("Score >= 70 but key criteria not met")
    else:
        feedback_parts.append(f"Score {score}/100 below threshold")

    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }