#!/usr/bin/env python3
"""
Verifier for lung lobar volume assessment task.

VERIFICATION CRITERIA:
1. Five lobes exist (20 points)
2. Correct laterality - right lobes on right, left on left (15 points)
3. Correct lobe count per side - 3 right, 2 left (15 points)
4. Spatial relationships - upper lobes superior to lower (10 points)
5. Total volume plausible - 3000-7000 mL (10 points)
6. R/L ratio correct - 1.0-1.5 (10 points)
7. Individual lobe proportions reasonable (10 points)
8. Report complete with all required fields (10 points)

Pass threshold: 60 points with at least criteria 1 and 3 met
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    if isinstance(val, (np.integer, np.int32, np.int64)):
        return int(val)
    elif isinstance(val, (np.floating, np.float32, np.float64)):
        return float(val)
    elif isinstance(val, np.ndarray):
        return val.tolist()
    elif isinstance(val, np.bool_):
        return bool(val)
    elif isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def verify_lung_lobar_volume(traj, env_info, task_info):
    """
    Verify lung lobar volume assessment task completion.
    
    Scoring (100 points total):
    - Five lobes exist: 20 points
    - Correct laterality: 15 points
    - Correct lobe count per side: 15 points
    - Spatial relationships: 10 points
    - Total volume plausible: 10 points
    - R/L ratio correct: 10 points
    - Lobe proportions: 10 points
    - Report complete: 10 points
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
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    # Thresholds
    total_vol_min = thresholds.get('total_volume_min_ml', 3000)
    total_vol_max = thresholds.get('total_volume_max_ml', 7000)
    rl_ratio_min = thresholds.get('right_left_ratio_min', 1.0)
    rl_ratio_max = thresholds.get('right_left_ratio_max', 1.5)
    
    # Weights
    w_five_lobes = weights.get('five_lobes_exist', 20)
    w_laterality = weights.get('correct_laterality', 15)
    w_lobe_count = weights.get('correct_lobe_count_per_side', 15)
    w_spatial = weights.get('spatial_relationships', 10)
    w_total_vol = weights.get('total_volume_plausible', 10)
    w_rl_ratio = weights.get('rl_ratio_correct', 10)
    w_proportions = weights.get('lobe_proportions', 10)
    w_report = weights.get('report_complete', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/lung_lobar_task_result.json", temp_result.name)
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
    criteria_met = {
        "five_lobes": False,
        "correct_laterality": False,
        "correct_lobe_count": False,
        "spatial_relationships": False,
        "total_volume_plausible": False,
        "rl_ratio_correct": False,
        "lobe_proportions": False,
        "report_complete": False
    }
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer was not running")
    
    # Check if segmentation exists
    if not result.get('segmentation_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No segmentation file found - task not attempted",
            "details": {"segmentation_exists": False}
        }
    
    # Check if file was created during task (anti-gaming)
    if not result.get('segmentation_modified_during_task', False):
        feedback_parts.append("WARNING: Segmentation may not have been created during task")
    
    # Get lobe analysis from export
    lobe_analysis = result.get('lobe_analysis', {})
    if isinstance(lobe_analysis, str):
        try:
            lobe_analysis = json.loads(lobe_analysis)
        except:
            lobe_analysis = {}
    
    if 'error' in lobe_analysis:
        feedback_parts.append(f"Segmentation analysis error: {lobe_analysis['error']}")
        lobe_analysis = {}
    
    details['lobe_analysis'] = lobe_analysis
    
    # Load ground truth if available
    gt_data = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/lung_lobar_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    details['ground_truth'] = gt_data
    
    # ============================================================
    # CRITERION 1: Five lobes exist (20 points)
    # ============================================================
    num_lobes = lobe_analysis.get('num_lobes', 0)
    details['num_lobes_found'] = num_lobes
    
    if num_lobes == 5:
        score += w_five_lobes
        feedback_parts.append(f"✓ Five lobes identified ({num_lobes})")
        criteria_met["five_lobes"] = True
    elif num_lobes >= 4:
        score += int(w_five_lobes * 0.7)
        feedback_parts.append(f"~ {num_lobes} lobes identified (expected 5)")
    elif num_lobes >= 2:
        score += int(w_five_lobes * 0.3)
        feedback_parts.append(f"✗ Only {num_lobes} lobes identified (expected 5)")
    else:
        feedback_parts.append(f"✗ Insufficient lobes identified ({num_lobes})")
    
    # ============================================================
    # CRITERION 2: Correct laterality (15 points)
    # ============================================================
    right_count = lobe_analysis.get('right_lobe_count', 0)
    left_count = lobe_analysis.get('left_lobe_count', 0)
    
    details['right_lobe_count'] = right_count
    details['left_lobe_count'] = left_count
    
    # Check if we have lobes on both sides
    if right_count > 0 and left_count > 0:
        # Basic laterality - lobes exist on both sides
        score += int(w_laterality * 0.7)
        feedback_parts.append(f"✓ Lobes on both sides (R:{right_count}, L:{left_count})")
        
        # Check if centroids are actually on correct sides
        lobes = lobe_analysis.get('lobes', {})
        right_labels = lobe_analysis.get('right_lobe_labels', [])
        left_labels = lobe_analysis.get('left_lobe_labels', [])
        
        if len(right_labels) > 0 and len(left_labels) > 0:
            score += int(w_laterality * 0.3)
            criteria_met["correct_laterality"] = True
    elif right_count > 0 or left_count > 0:
        score += int(w_laterality * 0.3)
        feedback_parts.append(f"~ Lobes only on one side (R:{right_count}, L:{left_count})")
    else:
        feedback_parts.append("✗ Could not determine lobe laterality")
    
    # ============================================================
    # CRITERION 3: Correct lobe count per side (15 points)
    # ============================================================
    expected_right = 3
    expected_left = 2
    
    right_correct = (right_count == expected_right)
    left_correct = (left_count == expected_left)
    
    if right_correct and left_correct:
        score += w_lobe_count
        feedback_parts.append(f"✓ Correct lobe count (R:{right_count}/3, L:{left_count}/2)")
        criteria_met["correct_lobe_count"] = True
    elif right_correct or left_correct:
        score += int(w_lobe_count * 0.5)
        feedback_parts.append(f"~ Partial lobe count correct (R:{right_count}/3, L:{left_count}/2)")
    else:
        # Give partial credit for having approximately correct total
        if num_lobes >= 4:
            score += int(w_lobe_count * 0.3)
        feedback_parts.append(f"✗ Incorrect lobe count (R:{right_count}/3, L:{left_count}/2)")
    
    # ============================================================
    # CRITERION 4: Spatial relationships (10 points)
    # ============================================================
    # Check if upper lobes are superior to lower lobes (higher z-coordinate)
    lobes = lobe_analysis.get('lobes', {})
    spatial_correct = False
    
    if len(lobes) >= 4:
        # Try to identify upper vs lower based on z-coordinate
        centroids = {k: v.get('centroid_mm', [0, 0, 0]) for k, v in lobes.items()}
        
        if centroids:
            z_coords = [c[2] for c in centroids.values()]
            z_range = max(z_coords) - min(z_coords) if z_coords else 0
            
            if z_range > 50:  # Reasonable spread in z
                score += int(w_spatial * 0.7)
                spatial_correct = True
                feedback_parts.append("✓ Lobes have reasonable spatial distribution")
                criteria_met["spatial_relationships"] = True
            else:
                score += int(w_spatial * 0.3)
                feedback_parts.append("~ Limited spatial distribution of lobes")
        else:
            feedback_parts.append("~ Could not verify spatial relationships")
    else:
        feedback_parts.append("✗ Insufficient lobes for spatial analysis")
    
    # ============================================================
    # CRITERION 5: Total volume plausible (10 points)
    # ============================================================
    total_volume = lobe_analysis.get('total_volume_ml', 0)
    details['total_volume_ml'] = total_volume
    
    if total_vol_min <= total_volume <= total_vol_max:
        score += w_total_vol
        feedback_parts.append(f"✓ Total volume plausible ({total_volume:.0f} mL)")
        criteria_met["total_volume_plausible"] = True
    elif total_volume > 1000:  # At least some volume
        score += int(w_total_vol * 0.5)
        feedback_parts.append(f"~ Total volume outside normal range ({total_volume:.0f} mL)")
    else:
        feedback_parts.append(f"✗ Total volume implausible ({total_volume:.0f} mL)")
    
    # ============================================================
    # CRITERION 6: R/L ratio correct (10 points)
    # ============================================================
    rl_ratio = lobe_analysis.get('rl_ratio', 0)
    details['rl_ratio'] = rl_ratio
    
    if rl_ratio > 0:
        if rl_ratio_min <= rl_ratio <= rl_ratio_max:
            score += w_rl_ratio
            feedback_parts.append(f"✓ R/L ratio correct ({rl_ratio:.2f})")
            criteria_met["rl_ratio_correct"] = True
        elif 0.8 <= rl_ratio <= 2.0:
            score += int(w_rl_ratio * 0.5)
            feedback_parts.append(f"~ R/L ratio outside expected range ({rl_ratio:.2f})")
        else:
            feedback_parts.append(f"✗ R/L ratio implausible ({rl_ratio:.2f})")
    else:
        feedback_parts.append("✗ Could not calculate R/L ratio")
    
    # ============================================================
    # CRITERION 7: Lobe proportions reasonable (10 points)
    # ============================================================
    expected_proportions = metadata.get('expected_lobe_proportions', {
        "RUL": 0.20, "RML": 0.08, "RLL": 0.25, "LUL": 0.25, "LLL": 0.22
    })
    tolerance = thresholds.get('lobe_proportion_tolerance', 0.15)
    
    if total_volume > 0 and len(lobes) >= 4:
        proportions_ok = 0
        for label, info in lobes.items():
            vol = info.get('volume_ml', 0)
            prop = vol / total_volume if total_volume > 0 else 0
            
            # Check if proportion is in reasonable range (5-35%)
            if 0.05 <= prop <= 0.35:
                proportions_ok += 1
        
        if proportions_ok >= 4:
            score += w_proportions
            feedback_parts.append(f"✓ Lobe proportions reasonable ({proportions_ok}/5 within range)")
            criteria_met["lobe_proportions"] = True
        elif proportions_ok >= 2:
            score += int(w_proportions * 0.5)
            feedback_parts.append(f"~ Some lobe proportions reasonable ({proportions_ok}/5)")
        else:
            feedback_parts.append(f"✗ Lobe proportions unreasonable ({proportions_ok}/5)")
    else:
        feedback_parts.append("~ Could not verify lobe proportions")
    
    # ============================================================
    # CRITERION 8: Report complete (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    reported_total = result.get('reported_total_volume_ml', '')
    reported_ratio = result.get('reported_rl_ratio', '')
    reported_lobe_count = result.get('reported_lobe_count', 0)
    
    details['report_exists'] = report_exists
    details['reported_values'] = {
        'total_volume': reported_total,
        'rl_ratio': reported_ratio,
        'lobe_count': reported_lobe_count
    }
    
    if report_exists:
        report_score = 0
        
        # Check for total volume
        if reported_total:
            try:
                rtv = float(reported_total)
                if rtv > 0:
                    report_score += 3
            except:
                pass
        
        # Check for R/L ratio
        if reported_ratio:
            try:
                rr = float(reported_ratio)
                if rr > 0:
                    report_score += 3
            except:
                pass
        
        # Check for individual lobe volumes
        if reported_lobe_count >= 5:
            report_score += 4
        elif reported_lobe_count >= 2:
            report_score += 2
        
        if report_score >= 8:
            score += w_report
            feedback_parts.append("✓ Report complete with all values")
            criteria_met["report_complete"] = True
        elif report_score >= 4:
            score += int(w_report * 0.6)
            feedback_parts.append("~ Report partially complete")
        else:
            score += int(w_report * 0.3)
            feedback_parts.append("~ Report exists but missing values")
    else:
        feedback_parts.append("✗ No volume report file found")
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Key criteria: five lobes AND correct lobe count per side
    key_criteria_met = criteria_met["five_lobes"] and criteria_met["correct_lobe_count"]
    
    # Alternative pass: good overall score even if not perfect structure
    alternative_pass = score >= 70 and num_lobes >= 4
    
    passed = (score >= 60 and key_criteria_met) or alternative_pass
    
    # Build feedback string
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    summary_parts = []
    if passed:
        summary_parts.append(f"PASSED ({score}/100)")
    else:
        summary_parts.append(f"FAILED ({score}/100)")
    
    summary_parts.append(f"Lobes: {num_lobes}/5")
    summary_parts.append(f"R/L: {right_count}/{left_count}")
    if total_volume > 0:
        summary_parts.append(f"Vol: {total_volume:.0f}mL")
    
    feedback = " | ".join(summary_parts) + " || " + feedback
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": feedback,
        "details": to_python_type(details),
        "criteria_met": to_python_type(criteria_met)
    }