#!/usr/bin/env python3
"""
Verifier for Tumor Enhancement Pattern Characterization task.

VERIFICATION CRITERIA:
1. Enhancement Ratio Accuracy (25 points) - within ±0.3 of ground truth
2. Relative Enhancement Accuracy (20 points) - within ±25% of ground truth
3. Tumor ROI Placement (15 points) - ROI within enhancing tumor region
4. Reference ROI Placement (10 points) - white matter reference measured
5. Classification Correctness (15 points) - correct or adjacent category
6. Pattern Description (5 points) - valid pattern description
7. Report Completeness (10 points) - all required fields present

Pass Threshold: 60 points with Enhancement Ratio accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    try:
        import numpy as np
        if isinstance(val, (np.integer, np.int32, np.int64)):
            return int(val)
        elif isinstance(val, (np.floating, np.float32, np.float64)):
            return float(val)
        elif isinstance(val, np.ndarray):
            return val.tolist()
        elif isinstance(val, np.bool_):
            return bool(val)
    except ImportError:
        pass
    
    if isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def verify_tumor_enhancement_pattern(traj, env_info, task_info):
    """
    Verify the tumor enhancement pattern characterization task.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback' keys
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
    
    er_error_max = thresholds.get('enhancement_ratio_error_max', 0.3)
    re_error_max = thresholds.get('relative_enhancement_error_max_percent', 25)
    
    w_er = weights.get('enhancement_ratio_accuracy', 25)
    w_re = weights.get('relative_enhancement_accuracy', 20)
    w_tumor_roi = weights.get('tumor_roi_placement', 15)
    w_ref_roi = weights.get('reference_roi_placement', 10)
    w_class = weights.get('classification_correct', 15)
    w_pattern = weights.get('pattern_description', 5)
    w_report = weights.get('report_completeness', 10)
    
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # Load task result from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/enhancement_task_result.json", temp_result.name)
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
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # Load ground truth
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/enhancement_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    if not gt_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Ground truth not available - setup may have failed"
        }
    
    gt_er = gt_data.get('enhancement_ratio', 1.0)
    gt_re = gt_data.get('relative_enhancement_percent', 0)
    gt_class = gt_data.get('classification', '')
    gt_pattern = gt_data.get('pattern', '')
    gt_centroid = gt_data.get('enhancing_centroid_ijk', [0, 0, 0])
    gt_bbox_min = gt_data.get('enhancing_bbox_min', [0, 0, 0])
    gt_bbox_max = gt_data.get('enhancing_bbox_max', [255, 255, 255])
    
    details['ground_truth'] = {
        'enhancement_ratio': gt_er,
        'relative_enhancement_percent': gt_re,
        'classification': gt_class,
        'pattern': gt_pattern
    }
    
    feedback_parts.append(f"GT: ER={gt_er:.3f}, RE={gt_re:.1f}%, Class={gt_class}")
    
    # ================================================================
    # Load agent's report
    # ================================================================
    agent_report = {}
    temp_agent = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_enhancement_report.json", temp_agent.name)
        with open(temp_agent.name, 'r') as f:
            agent_report = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load agent report: {e}")
        # Try to extract from result's agent_values
        agent_values = result.get('agent_values', {})
        if agent_values:
            agent_report = {
                'enhancement_ratio': agent_values.get('enhancement_ratio', ''),
                'relative_enhancement_percent': agent_values.get('relative_enhancement', ''),
                'classification': agent_values.get('classification', ''),
                'pattern': agent_values.get('pattern', ''),
                't1_tumor_mean': agent_values.get('t1_tumor_mean', ''),
                't1ce_tumor_mean': agent_values.get('t1ce_tumor_mean', '')
            }
    finally:
        if os.path.exists(temp_agent.name):
            os.unlink(temp_agent.name)
    
    if not agent_report and not result.get('report_exists', False):
        feedback_parts.append("Agent report not found - task not completed")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    details['agent_report'] = agent_report
    score_breakdown = {}
    
    # ================================================================
    # CRITERION 1: Enhancement Ratio Accuracy (25 points)
    # ================================================================
    agent_er_raw = agent_report.get('enhancement_ratio', None)
    agent_er = None
    
    if agent_er_raw is not None and agent_er_raw != '':
        try:
            agent_er = float(agent_er_raw)
        except (ValueError, TypeError):
            pass
    
    if agent_er is not None:
        er_diff = abs(agent_er - gt_er)
        if er_diff <= er_error_max:
            score += w_er
            score_breakdown['enhancement_ratio_accuracy'] = w_er
            feedback_parts.append(f"ER: {agent_er:.3f} (diff: {er_diff:.3f}) - PASS")
        elif er_diff <= er_error_max * 1.5:
            partial = w_er * 0.6
            score += partial
            score_breakdown['enhancement_ratio_accuracy'] = partial
            feedback_parts.append(f"ER: {agent_er:.3f} (diff: {er_diff:.3f}) - PARTIAL")
        else:
            score_breakdown['enhancement_ratio_accuracy'] = 0
            feedback_parts.append(f"ER: {agent_er:.3f} (diff: {er_diff:.3f}) - FAIL")
    else:
        score_breakdown['enhancement_ratio_accuracy'] = 0
        feedback_parts.append("Enhancement Ratio not reported")
    
    # ================================================================
    # CRITERION 2: Relative Enhancement Accuracy (20 points)
    # ================================================================
    agent_re_raw = agent_report.get('relative_enhancement_percent', 
                                     agent_report.get('relative_enhancement', None))
    agent_re = None
    
    if agent_re_raw is not None and agent_re_raw != '':
        try:
            agent_re = float(agent_re_raw)
        except (ValueError, TypeError):
            pass
    
    if agent_re is not None:
        re_diff = abs(agent_re - gt_re)
        if re_diff <= re_error_max:
            score += w_re
            score_breakdown['relative_enhancement_accuracy'] = w_re
            feedback_parts.append(f"RE: {agent_re:.1f}% (diff: {re_diff:.1f}%) - PASS")
        elif re_diff <= re_error_max * 1.6:
            partial = w_re * 0.5
            score += partial
            score_breakdown['relative_enhancement_accuracy'] = partial
            feedback_parts.append(f"RE: {agent_re:.1f}% (diff: {re_diff:.1f}%) - PARTIAL")
        else:
            score_breakdown['relative_enhancement_accuracy'] = 0
            feedback_parts.append(f"RE: {agent_re:.1f}% (diff: {re_diff:.1f}%) - FAIL")
    else:
        score_breakdown['relative_enhancement_accuracy'] = 0
        feedback_parts.append("Relative Enhancement not reported")
    
    # ================================================================
    # CRITERION 3: Tumor ROI Placement (15 points)
    # ================================================================
    tumor_roi = agent_report.get('tumor_roi_position', None)
    has_tumor_measurement = (
        agent_report.get('t1_tumor_mean') or 
        agent_report.get('t1ce_tumor_mean')
    )
    
    if tumor_roi and isinstance(tumor_roi, list) and len(tumor_roi) >= 3:
        # Check if ROI is within enhancing tumor bounding box
        in_bbox = all(
            gt_bbox_min[i] <= tumor_roi[i] <= gt_bbox_max[i]
            for i in range(3)
        )
        if in_bbox:
            score += w_tumor_roi
            score_breakdown['tumor_roi_placement'] = w_tumor_roi
            feedback_parts.append("Tumor ROI within enhancing region - PASS")
        else:
            # Check distance to centroid
            dist = math.sqrt(sum((tumor_roi[i] - gt_centroid[i])**2 for i in range(3)))
            if dist < 40:
                partial = w_tumor_roi * 0.6
                score += partial
                score_breakdown['tumor_roi_placement'] = partial
                feedback_parts.append(f"Tumor ROI near region (dist: {dist:.1f}) - PARTIAL")
            else:
                score_breakdown['tumor_roi_placement'] = 0
                feedback_parts.append(f"Tumor ROI too far (dist: {dist:.1f}) - FAIL")
    elif has_tumor_measurement:
        # Measurements exist but no position - give partial credit
        partial = w_tumor_roi * 0.5
        score += partial
        score_breakdown['tumor_roi_placement'] = partial
        feedback_parts.append("Tumor measurements present (no position) - PARTIAL")
    else:
        score_breakdown['tumor_roi_placement'] = 0
        feedback_parts.append("Tumor ROI position not reported")
    
    # ================================================================
    # CRITERION 4: Reference ROI Placement (10 points)
    # ================================================================
    has_wm_measurement = (
        agent_report.get('t1_wm_mean') or 
        agent_report.get('t1ce_wm_mean') or
        agent_report.get('white_matter_roi_position')
    )
    
    if has_wm_measurement:
        try:
            wm_val = float(agent_report.get('t1_wm_mean', 0) or agent_report.get('t1ce_wm_mean', 0) or 0)
            if wm_val > 0:
                score += w_ref_roi
                score_breakdown['reference_roi_placement'] = w_ref_roi
                feedback_parts.append("Reference ROI measurements present - PASS")
            else:
                partial = w_ref_roi * 0.5
                score += partial
                score_breakdown['reference_roi_placement'] = partial
                feedback_parts.append("Reference ROI partially reported - PARTIAL")
        except (ValueError, TypeError):
            partial = w_ref_roi * 0.5
            score += partial
            score_breakdown['reference_roi_placement'] = partial
            feedback_parts.append("Reference ROI partially reported - PARTIAL")
    else:
        score_breakdown['reference_roi_placement'] = 0
        feedback_parts.append("Reference ROI not reported")
    
    # ================================================================
    # CRITERION 5: Classification Accuracy (15 points)
    # ================================================================
    agent_class = str(agent_report.get('classification', '')).lower().replace('_', '-').replace(' ', '-')
    gt_class_norm = gt_class.lower().replace('_', '-').replace(' ', '-')
    
    class_order = ['non-enhancing', 'minimally-enhancing', 'moderately-enhancing', 'strongly-enhancing']
    
    if agent_class:
        # Find indices in classification order
        agent_idx = -1
        gt_idx = -1
        for i, c in enumerate(class_order):
            if agent_class in c or c in agent_class:
                agent_idx = i
            if gt_class_norm in c or c in gt_class_norm:
                gt_idx = i
        
        if agent_class == gt_class_norm or (agent_idx >= 0 and agent_idx == gt_idx):
            score += w_class
            score_breakdown['classification_correct'] = w_class
            feedback_parts.append(f"Classification: {agent_class} - EXACT MATCH")
        elif agent_idx >= 0 and gt_idx >= 0 and abs(agent_idx - gt_idx) == 1:
            partial = w_class * 0.6
            score += partial
            score_breakdown['classification_correct'] = partial
            feedback_parts.append(f"Classification: {agent_class} (expected: {gt_class}) - ADJACENT")
        else:
            score_breakdown['classification_correct'] = 0
            feedback_parts.append(f"Classification: {agent_class} (expected: {gt_class}) - WRONG")
    else:
        score_breakdown['classification_correct'] = 0
        feedback_parts.append("Classification not reported")
    
    # ================================================================
    # CRITERION 6: Pattern Description (5 points)
    # ================================================================
    agent_pattern = str(agent_report.get('pattern', '')).lower()
    gt_pattern_norm = gt_pattern.lower()
    
    valid_patterns = ['homogeneous', 'heterogeneous', 'ring-enhancing', 'ring', 'nodular', 'patchy', 'diffuse', 'minimal']
    
    if agent_pattern:
        if agent_pattern == gt_pattern_norm or agent_pattern in gt_pattern_norm or gt_pattern_norm in agent_pattern:
            score += w_pattern
            score_breakdown['pattern_description'] = w_pattern
            feedback_parts.append(f"Pattern: {agent_pattern} - MATCH")
        elif any(p in agent_pattern for p in valid_patterns):
            partial = w_pattern * 0.5
            score += partial
            score_breakdown['pattern_description'] = partial
            feedback_parts.append(f"Pattern: {agent_pattern} (expected: {gt_pattern}) - PLAUSIBLE")
        else:
            score_breakdown['pattern_description'] = 0
            feedback_parts.append(f"Pattern: {agent_pattern} - INVALID")
    else:
        score_breakdown['pattern_description'] = 0
        feedback_parts.append("Pattern not reported")
    
    # ================================================================
    # CRITERION 7: Report Completeness (10 points)
    # ================================================================
    report_keys = [str(k).lower() for k in agent_report.keys()]
    
    has_required = any('enhancement' in k or 'ratio' in k for k in report_keys)
    has_classification = 'classification' in report_keys or any('class' in k for k in report_keys)
    has_measurements = any('tumor' in k for k in report_keys) or any('signal' in k for k in report_keys)
    has_pattern = 'pattern' in report_keys
    
    completeness_score = 0
    if has_required:
        completeness_score += 4
    if has_classification:
        completeness_score += 3
    if has_measurements:
        completeness_score += 2
    if has_pattern:
        completeness_score += 1
    
    completeness_score = min(completeness_score, w_report)
    score += completeness_score
    score_breakdown['report_completeness'] = completeness_score
    feedback_parts.append(f"Report completeness: {completeness_score}/{w_report}")
    
    # ================================================================
    # Anti-gaming: Check file timestamps
    # ================================================================
    report_created_during_task = result.get('report_created_during_task', False)
    if not report_created_during_task and result.get('report_exists', False):
        # Penalize if report existed before task
        penalty = 10
        score = max(0, score - penalty)
        feedback_parts.append(f"WARNING: Report may have pre-existed (penalty: -{penalty})")
        details['anti_gaming_penalty'] = penalty
    
    # ================================================================
    # Final scoring
    # ================================================================
    # Normalize to 0-1 scale (max 100 points)
    final_score = min(score / 100.0, 1.0)
    
    # Check pass threshold (60 points with ER accuracy)
    er_accuracy_achieved = score_breakdown.get('enhancement_ratio_accuracy', 0) >= w_er * 0.6
    passed = score >= 60 and er_accuracy_achieved
    
    details['score_breakdown'] = to_python_type(score_breakdown)
    details['total_score'] = to_python_type(score)
    
    return {
        "passed": passed,
        "score": int(round(score)),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }


if __name__ == "__main__":
    # Test verification
    result = verify_tumor_enhancement_pattern({}, {}, {})
    print(f"Result: {json.dumps(result, indent=2)}")