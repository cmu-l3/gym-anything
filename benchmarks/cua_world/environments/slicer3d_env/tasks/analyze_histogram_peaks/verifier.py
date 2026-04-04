#!/usr/bin/env python3
"""
Verifier for Analyze Histogram Peaks task.

VERIFICATION STRATEGY:
1. JSON file exists at correct location (15 points)
2. Valid JSON structure with required fields (10 points)
3. MRHead volume loaded in Slicer (15 points)
4. Background peak in valid range [0, 100] (15 points)
5. Low tissue peak in valid range [200, 600], > background (15 points)
6. High tissue peak in valid range [400, 1000], > low (15 points)
7. Proper ordering: background < low < high (10 points)
8. VLM evidence of histogram visualization (5 points)

Pass threshold: 70 points with JSON file exists and volume loaded
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_analyze_histogram_peaks(traj, env_info, task_info):
    """
    Verify histogram analysis task completion.
    
    Uses multi-criteria scoring with plausibility checks for peak values.
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
    bg_range = metadata.get('background_peak_range', {"min": 0, "max": 100})
    low_range = metadata.get('low_tissue_peak_range', {"min": 200, "max": 600})
    high_range = metadata.get('high_tissue_peak_range', {"min": 400, "max": 1000})
    
    weights = metadata.get('scoring_weights', {})
    w_json_exists = weights.get('json_exists', 15)
    w_valid_structure = weights.get('valid_structure', 10)
    w_volume_loaded = weights.get('volume_loaded', 15)
    w_background = weights.get('background_valid', 15)
    w_low_tissue = weights.get('low_tissue_valid', 15)
    w_high_tissue = weights.get('high_tissue_valid', 15)
    w_ordering = weights.get('proper_ordering', 10)
    w_vlm = weights.get('vlm_evidence', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/histogram_task_result.json", temp_result.name)
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
    
    # ============================================================
    # CRITERION 1: JSON File Exists (15 points)
    # ============================================================
    json_exists = result.get('output_json_exists', False)
    created_after_start = result.get('output_created_after_start', False)
    
    if json_exists:
        if created_after_start:
            score += w_json_exists
            feedback_parts.append(f"✓ Output JSON file exists and created during task (+{w_json_exists})")
        else:
            # Partial credit - file exists but may have pre-existed
            score += w_json_exists // 2
            feedback_parts.append(f"△ Output JSON exists but timestamp suspicious (+{w_json_exists // 2})")
        details['json_exists'] = True
        details['created_during_task'] = created_after_start
    else:
        feedback_parts.append("✗ Output JSON file not found at expected location")
        details['json_exists'] = False
        # Early termination - can't verify without output
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ============================================================
    # CRITERION 2: Valid JSON Structure (10 points)
    # ============================================================
    valid_json = result.get('valid_json', False)
    valid_structure = result.get('valid_structure', False)
    
    if valid_json and valid_structure:
        score += w_valid_structure
        feedback_parts.append(f"✓ Valid JSON with all required fields (+{w_valid_structure})")
        details['valid_structure'] = True
    elif valid_json:
        score += w_valid_structure // 2
        feedback_parts.append(f"△ Valid JSON but missing some fields (+{w_valid_structure // 2})")
        details['valid_structure'] = False
    else:
        feedback_parts.append("✗ Invalid JSON format")
        details['valid_structure'] = False
    
    # ============================================================
    # CRITERION 3: Volume Loaded (15 points)
    # ============================================================
    slicer_running = result.get('slicer_running', False)
    volume_loaded = result.get('volume_loaded', False)
    mrhead_loaded = result.get('mrhead_loaded', False)
    
    if mrhead_loaded:
        score += w_volume_loaded
        feedback_parts.append(f"✓ MRHead volume loaded in Slicer (+{w_volume_loaded})")
        details['volume_loaded'] = True
    elif volume_loaded:
        score += w_volume_loaded * 3 // 4
        feedback_parts.append(f"△ A volume is loaded (may not be MRHead) (+{w_volume_loaded * 3 // 4})")
        details['volume_loaded'] = True
    elif slicer_running:
        score += w_volume_loaded // 4
        feedback_parts.append(f"△ Slicer running but no volume detected (+{w_volume_loaded // 4})")
        details['volume_loaded'] = False
    else:
        feedback_parts.append("✗ Slicer not running or no volume loaded")
        details['volume_loaded'] = False
    
    # ============================================================
    # EXTRACT AND VALIDATE PEAK VALUES
    # ============================================================
    bg_peak = None
    low_peak = None
    high_peak = None
    
    try:
        bg_str = result.get('background_peak', '')
        low_str = result.get('low_tissue_peak', '')
        high_str = result.get('high_tissue_peak', '')
        
        if bg_str:
            bg_peak = float(bg_str)
        if low_str:
            low_peak = float(low_str)
        if high_str:
            high_peak = float(high_str)
            
        details['extracted_values'] = {
            'background': bg_peak,
            'low_tissue': low_peak,
            'high_tissue': high_peak
        }
    except (ValueError, TypeError) as e:
        feedback_parts.append(f"✗ Could not parse peak values: {e}")
        details['parse_error'] = str(e)
    
    # ============================================================
    # CRITERION 4: Background Peak Valid (15 points)
    # ============================================================
    if bg_peak is not None:
        bg_min = bg_range.get('min', 0)
        bg_max = bg_range.get('max', 100)
        
        if bg_min <= bg_peak <= bg_max:
            score += w_background
            feedback_parts.append(f"✓ Background peak ({bg_peak:.1f}) in valid range [{bg_min}, {bg_max}] (+{w_background})")
            details['background_valid'] = True
        elif 0 <= bg_peak <= 150:
            # Slightly outside but plausible
            score += w_background // 2
            feedback_parts.append(f"△ Background peak ({bg_peak:.1f}) slightly outside expected range (+{w_background // 2})")
            details['background_valid'] = False
        else:
            feedback_parts.append(f"✗ Background peak ({bg_peak:.1f}) outside expected range [{bg_min}, {bg_max}]")
            details['background_valid'] = False
    else:
        feedback_parts.append("✗ Background peak value missing or invalid")
        details['background_valid'] = False
    
    # ============================================================
    # CRITERION 5: Low Tissue Peak Valid (15 points)
    # ============================================================
    if low_peak is not None:
        low_min = low_range.get('min', 200)
        low_max = low_range.get('max', 600)
        
        # Check range and ordering relative to background
        in_range = low_min <= low_peak <= low_max
        greater_than_bg = bg_peak is not None and low_peak > bg_peak
        
        if in_range and greater_than_bg:
            score += w_low_tissue
            feedback_parts.append(f"✓ Low tissue peak ({low_peak:.1f}) valid, > background (+{w_low_tissue})")
            details['low_tissue_valid'] = True
        elif in_range:
            score += w_low_tissue * 2 // 3
            feedback_parts.append(f"△ Low tissue peak ({low_peak:.1f}) in range but ordering issue (+{w_low_tissue * 2 // 3})")
            details['low_tissue_valid'] = False
        elif 100 <= low_peak <= 800 and greater_than_bg:
            score += w_low_tissue // 2
            feedback_parts.append(f"△ Low tissue peak ({low_peak:.1f}) plausible but outside expected range (+{w_low_tissue // 2})")
            details['low_tissue_valid'] = False
        else:
            feedback_parts.append(f"✗ Low tissue peak ({low_peak:.1f}) invalid or not > background")
            details['low_tissue_valid'] = False
    else:
        feedback_parts.append("✗ Low tissue peak value missing or invalid")
        details['low_tissue_valid'] = False
    
    # ============================================================
    # CRITERION 6: High Tissue Peak Valid (15 points)
    # ============================================================
    if high_peak is not None:
        high_min = high_range.get('min', 400)
        high_max = high_range.get('max', 1000)
        
        # Check range and ordering relative to low peak
        in_range = high_min <= high_peak <= high_max
        greater_than_low = low_peak is not None and high_peak > low_peak
        
        if in_range and greater_than_low:
            score += w_high_tissue
            feedback_parts.append(f"✓ High tissue peak ({high_peak:.1f}) valid, > low tissue (+{w_high_tissue})")
            details['high_tissue_valid'] = True
        elif in_range:
            score += w_high_tissue * 2 // 3
            feedback_parts.append(f"△ High tissue peak ({high_peak:.1f}) in range but ordering issue (+{w_high_tissue * 2 // 3})")
            details['high_tissue_valid'] = False
        elif 300 <= high_peak <= 1200 and greater_than_low:
            score += w_high_tissue // 2
            feedback_parts.append(f"△ High tissue peak ({high_peak:.1f}) plausible but outside expected range (+{w_high_tissue // 2})")
            details['high_tissue_valid'] = False
        else:
            feedback_parts.append(f"✗ High tissue peak ({high_peak:.1f}) invalid or not > low tissue")
            details['high_tissue_valid'] = False
    else:
        feedback_parts.append("✗ High tissue peak value missing or invalid")
        details['high_tissue_valid'] = False
    
    # ============================================================
    # CRITERION 7: Proper Ordering (10 points)
    # ============================================================
    proper_ordering = result.get('proper_ordering', False)
    
    # Double-check ordering ourselves
    if bg_peak is not None and low_peak is not None and high_peak is not None:
        calculated_ordering = bg_peak < low_peak < high_peak
        if calculated_ordering and proper_ordering:
            score += w_ordering
            feedback_parts.append(f"✓ Peaks properly ordered: {bg_peak:.1f} < {low_peak:.1f} < {high_peak:.1f} (+{w_ordering})")
            details['proper_ordering'] = True
        elif calculated_ordering:
            score += w_ordering
            feedback_parts.append(f"✓ Peaks properly ordered (+{w_ordering})")
            details['proper_ordering'] = True
        else:
            feedback_parts.append(f"✗ Peaks NOT in proper ascending order")
            details['proper_ordering'] = False
    else:
        feedback_parts.append("✗ Cannot verify ordering - missing peak values")
        details['proper_ordering'] = False
    
    # ============================================================
    # CRITERION 8: VLM Evidence (5 points) - Optional
    # ============================================================
    # Check if Volumes module was accessed (heuristic)
    volumes_module_visible = result.get('volumes_module_visible', False)
    
    if volumes_module_visible:
        score += w_vlm
        feedback_parts.append(f"✓ Evidence of Volumes module usage (+{w_vlm})")
        details['vlm_evidence'] = True
    else:
        feedback_parts.append("○ No direct evidence of histogram visualization (no penalty)")
        details['vlm_evidence'] = False
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Key criteria: JSON exists AND (volume loaded OR valid structure with correct ordering)
    key_criteria_met = (
        json_exists and 
        (volume_loaded or mrhead_loaded or (valid_structure and details.get('proper_ordering', False)))
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Cap score at 100
    score = min(score, 100)
    
    # Summary
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }