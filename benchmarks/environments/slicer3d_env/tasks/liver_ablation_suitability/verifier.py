#!/usr/bin/env python3
"""
Verifier for Liver Lesion Ablation Suitability Assessment task.

VERIFICATION STRATEGY:
1. Lesion dimension accuracy (20 pts) - all 3 dimensions within 10mm
2. Hepatic vein distance (15 pts) - within 8mm of ground truth
3. Portal vein distance (15 pts) - within 8mm of ground truth
4. Capsule distance (10 pts) - within 8mm of ground truth
5. Suitability classification (20 pts) - correct category
6. Liver segment (5 pts) - correct Couinaud segment
7. Report completeness (10 pts) - all required fields present
8. Entry point (5 pts) - valid coordinates if feasible/ideal

Total: 100 pts
Pass threshold: 60 pts with at least 2 accurate distance measurements
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_liver_ablation_suitability(traj, env_info, task_info):
    """
    Verify liver ablation suitability assessment task completion.
    
    Uses copy_from_env to read exported results from container.
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
    
    dim_error_max = thresholds.get('dimension_error_max_mm', 10.0)
    dist_error_max = thresholds.get('distance_error_max_mm', 8.0)
    
    w_dimensions = weights.get('lesion_dimensions', 20)
    w_hv_dist = weights.get('hepatic_vein_distance', 15)
    w_pv_dist = weights.get('portal_vein_distance', 15)
    w_cap_dist = weights.get('capsule_distance', 10)
    w_classification = weights.get('classification', 20)
    w_segment = weights.get('liver_segment', 5)
    w_report = weights.get('report_completeness', 10)
    w_entry = weights.get('entry_point', 5)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    accurate_distances = 0
    
    # Copy result JSON from container
    temp_dir = tempfile.mkdtemp()
    result_file = os.path.join(temp_dir, "result.json")
    
    try:
        copy_from_env("/tmp/ablation_task_result.json", result_file)
        with open(result_file, 'r') as f:
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
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        feedback_parts.append("FAIL: Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": "; ".join(feedback_parts)
        }
    
    if not result.get('report_exists', False):
        feedback_parts.append("FAIL: Ablation report not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "; ".join(feedback_parts)
        }
    
    # Anti-gaming: check if report was created during task
    if not result.get('report_created_after_start', False):
        feedback_parts.append("WARNING: Report may have been pre-existing")
    
    # Load agent's report
    agent_report = {}
    agent_report_file = os.path.join(temp_dir, "agent_report.json")
    try:
        copy_from_env("/tmp/agent_report.json", agent_report_file)
        with open(agent_report_file, 'r') as f:
            agent_report = json.load(f)
    except Exception as e:
        feedback_parts.append(f"FAIL: Could not read agent report: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "; ".join(feedback_parts)
        }
    
    details['agent_report'] = agent_report
    
    # Load ground truth
    ground_truth = {}
    gt_file = os.path.join(temp_dir, "ground_truth.json")
    try:
        copy_from_env("/tmp/ground_truth.json", gt_file)
        with open(gt_file, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        # Fall back to validation-only mode
        ground_truth = None
    
    if ground_truth:
        details['ground_truth'] = ground_truth
    
    # ============================================================
    # CRITERION 1: Lesion Dimensions (20 pts)
    # ============================================================
    if ground_truth:
        gt_dims = ground_truth.get('tumor_dimensions_mm', {})
        agent_dims = agent_report.get('lesion_dimensions_mm', {})
        
        if gt_dims and agent_dims:
            dim_errors = []
            for key in ['length', 'width', 'height']:
                gt_val = float(gt_dims.get(key, 0))
                agent_val = float(agent_dims.get(key, 0)) if agent_dims.get(key) else 0
                error = abs(gt_val - agent_val)
                dim_errors.append(error)
            
            details['dimension_errors_mm'] = dim_errors
            
            if all(e <= dim_error_max for e in dim_errors):
                score += w_dimensions
                feedback_parts.append(f"PASS: Lesion dimensions accurate ({w_dimensions} pts)")
            elif all(e <= dim_error_max * 1.5 for e in dim_errors):
                score += int(w_dimensions * 0.6)
                feedback_parts.append(f"PARTIAL: Dimensions approximately correct ({int(w_dimensions * 0.6)} pts)")
            else:
                feedback_parts.append(f"FAIL: Dimension errors too large: {[f'{e:.1f}mm' for e in dim_errors]}")
        else:
            feedback_parts.append("FAIL: Lesion dimensions missing or invalid")
    else:
        # Without ground truth, give points if dimensions are provided and reasonable
        agent_dims = agent_report.get('lesion_dimensions_mm', {})
        if agent_dims and all(agent_dims.get(k) for k in ['length', 'width', 'height']):
            try:
                dims = [float(agent_dims[k]) for k in ['length', 'width', 'height']]
                if all(1 < d < 200 for d in dims):  # Reasonable range for liver lesion
                    score += int(w_dimensions * 0.5)
                    feedback_parts.append(f"PARTIAL: Dimensions provided (no ground truth to verify)")
            except:
                pass
    
    # ============================================================
    # CRITERION 2: Hepatic Vein Distance (15 pts)
    # ============================================================
    if ground_truth:
        gt_hv_dist = ground_truth.get('distance_to_hepatic_vein_mm')
        agent_hv_dist_str = result.get('reported_hv_distance_mm', '')
        
        if gt_hv_dist is not None and agent_hv_dist_str:
            try:
                agent_hv_dist = float(agent_hv_dist_str)
                hv_error = abs(gt_hv_dist - agent_hv_dist)
                details['hepatic_vein_error_mm'] = hv_error
                
                if hv_error <= dist_error_max:
                    score += w_hv_dist
                    accurate_distances += 1
                    feedback_parts.append(f"PASS: Hepatic vein distance accurate (error: {hv_error:.1f}mm)")
                elif hv_error <= dist_error_max * 2:
                    score += int(w_hv_dist * 0.5)
                    feedback_parts.append(f"PARTIAL: Hepatic vein distance approximate (error: {hv_error:.1f}mm)")
                else:
                    feedback_parts.append(f"FAIL: Hepatic vein distance error: {hv_error:.1f}mm")
            except ValueError:
                feedback_parts.append("FAIL: Invalid hepatic vein distance value")
        else:
            feedback_parts.append("FAIL: Hepatic vein distance missing")
    else:
        # Partial credit for providing measurement
        if result.get('reported_hv_distance_mm'):
            score += int(w_hv_dist * 0.3)
            feedback_parts.append("PARTIAL: Hepatic vein distance provided (no verification)")
    
    # ============================================================
    # CRITERION 3: Portal Vein Distance (15 pts)
    # ============================================================
    if ground_truth:
        gt_pv_dist = ground_truth.get('distance_to_portal_vein_mm')
        agent_pv_dist_str = result.get('reported_pv_distance_mm', '')
        
        if gt_pv_dist is not None and agent_pv_dist_str:
            try:
                agent_pv_dist = float(agent_pv_dist_str)
                pv_error = abs(gt_pv_dist - agent_pv_dist)
                details['portal_vein_error_mm'] = pv_error
                
                if pv_error <= dist_error_max:
                    score += w_pv_dist
                    accurate_distances += 1
                    feedback_parts.append(f"PASS: Portal vein distance accurate (error: {pv_error:.1f}mm)")
                elif pv_error <= dist_error_max * 2:
                    score += int(w_pv_dist * 0.5)
                    feedback_parts.append(f"PARTIAL: Portal vein distance approximate (error: {pv_error:.1f}mm)")
                else:
                    feedback_parts.append(f"FAIL: Portal vein distance error: {pv_error:.1f}mm")
            except ValueError:
                feedback_parts.append("FAIL: Invalid portal vein distance value")
        else:
            feedback_parts.append("FAIL: Portal vein distance missing")
    else:
        if result.get('reported_pv_distance_mm'):
            score += int(w_pv_dist * 0.3)
            feedback_parts.append("PARTIAL: Portal vein distance provided (no verification)")
    
    # ============================================================
    # CRITERION 4: Capsule Distance (10 pts)
    # ============================================================
    if ground_truth:
        gt_cap_dist = ground_truth.get('distance_to_capsule_mm')
        agent_cap_dist_str = result.get('reported_capsule_distance_mm', '')
        
        if gt_cap_dist is not None and agent_cap_dist_str:
            try:
                agent_cap_dist = float(agent_cap_dist_str)
                cap_error = abs(gt_cap_dist - agent_cap_dist)
                details['capsule_error_mm'] = cap_error
                
                if cap_error <= dist_error_max:
                    score += w_cap_dist
                    accurate_distances += 1
                    feedback_parts.append(f"PASS: Capsule distance accurate (error: {cap_error:.1f}mm)")
                elif cap_error <= dist_error_max * 2:
                    score += int(w_cap_dist * 0.5)
                    feedback_parts.append(f"PARTIAL: Capsule distance approximate (error: {cap_error:.1f}mm)")
                else:
                    feedback_parts.append(f"FAIL: Capsule distance error: {cap_error:.1f}mm")
            except ValueError:
                feedback_parts.append("FAIL: Invalid capsule distance value")
        else:
            feedback_parts.append("FAIL: Capsule distance missing")
    else:
        if result.get('reported_capsule_distance_mm'):
            score += int(w_cap_dist * 0.3)
            feedback_parts.append("PARTIAL: Capsule distance provided (no verification)")
    
    # ============================================================
    # CRITERION 5: Suitability Classification (20 pts)
    # ============================================================
    classification_order = ['ideal', 'feasible', 'not_suitable']
    agent_class = result.get('reported_classification', '').lower().strip()
    
    if ground_truth:
        gt_class = ground_truth.get('expected_classification', '').lower()
        details['classification'] = {'expected': gt_class, 'agent': agent_class}
        
        if agent_class == gt_class:
            score += w_classification
            feedback_parts.append(f"PASS: Classification correct ({agent_class})")
        elif agent_class in classification_order and gt_class in classification_order:
            agent_idx = classification_order.index(agent_class)
            gt_idx = classification_order.index(gt_class)
            
            # Conservative classification gets partial credit
            if agent_idx > gt_idx:
                score += int(w_classification * 0.75)
                feedback_parts.append(f"PARTIAL: Classification conservative ({agent_class} vs {gt_class})")
            else:
                feedback_parts.append(f"FAIL: Classification too optimistic ({agent_class} vs {gt_class})")
        else:
            feedback_parts.append(f"FAIL: Invalid classification: {agent_class}")
    else:
        # Verify classification is self-consistent with measurements
        if agent_class in classification_order:
            score += int(w_classification * 0.4)
            feedback_parts.append(f"PARTIAL: Classification provided: {agent_class} (no verification)")
    
    # ============================================================
    # CRITERION 6: Liver Segment (5 pts)
    # ============================================================
    agent_segment = result.get('reported_segment', '').upper().replace('SEGMENT', '').strip()
    
    if ground_truth:
        gt_segment = ground_truth.get('expected_segment', '').upper()
        details['segment'] = {'expected': gt_segment, 'agent': agent_segment}
        
        if agent_segment == gt_segment:
            score += w_segment
            feedback_parts.append(f"PASS: Liver segment correct ({agent_segment})")
        else:
            # Adjacent segments get partial credit
            segment_neighbors = {
                'I': ['II', 'IV'],
                'II': ['I', 'III', 'IV'],
                'III': ['II', 'IV'],
                'IV': ['I', 'II', 'III', 'V', 'VIII'],
                'V': ['IV', 'VI', 'VIII'],
                'VI': ['V', 'VII'],
                'VII': ['VI', 'VIII'],
                'VIII': ['IV', 'V', 'VII']
            }
            if agent_segment in segment_neighbors.get(gt_segment, []):
                score += int(w_segment * 0.5)
                feedback_parts.append(f"PARTIAL: Adjacent segment ({agent_segment} vs {gt_segment})")
            else:
                feedback_parts.append(f"FAIL: Incorrect segment ({agent_segment} vs {gt_segment})")
    else:
        valid_segments = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII']
        if agent_segment in valid_segments:
            score += int(w_segment * 0.5)
            feedback_parts.append(f"PARTIAL: Segment provided: {agent_segment}")
    
    # ============================================================
    # CRITERION 7: Report Completeness (10 pts)
    # ============================================================
    required_fields = [
        'lesion_dimensions_mm',
        'max_dimension_mm',
        'distance_to_hepatic_vein_mm',
        'distance_to_portal_vein_mm',
        'distance_to_capsule_mm',
        'liver_segment',
        'subcapsular',
        'suitability_classification',
        'rationale'
    ]
    
    present_fields = sum(1 for f in required_fields if f in agent_report and agent_report[f] is not None)
    completeness_ratio = present_fields / len(required_fields)
    details['report_completeness'] = completeness_ratio
    
    if completeness_ratio >= 0.9:
        score += w_report
        feedback_parts.append(f"PASS: Report complete ({present_fields}/{len(required_fields)} fields)")
    elif completeness_ratio >= 0.7:
        score += int(w_report * 0.6)
        feedback_parts.append(f"PARTIAL: Report mostly complete ({present_fields}/{len(required_fields)} fields)")
    else:
        feedback_parts.append(f"FAIL: Report incomplete ({present_fields}/{len(required_fields)} fields)")
    
    # ============================================================
    # CRITERION 8: Entry Point (5 pts)
    # ============================================================
    entry_point_exists = result.get('entry_point_exists', False)
    
    if agent_class in ['ideal', 'feasible']:
        if entry_point_exists:
            # Verify entry point is reasonable (within plausible liver coordinates)
            entry_point = agent_report.get('proposed_entry_point', [])
            if isinstance(entry_point, list) and len(entry_point) == 3:
                try:
                    coords = [float(c) for c in entry_point]
                    if all(-500 < c < 500 for c in coords):  # Reasonable coordinate range
                        score += w_entry
                        feedback_parts.append(f"PASS: Entry point provided {coords}")
                    else:
                        feedback_parts.append("FAIL: Entry point coordinates out of range")
                except:
                    feedback_parts.append("FAIL: Invalid entry point format")
            else:
                feedback_parts.append("FAIL: Entry point missing or invalid format")
        else:
            feedback_parts.append("FAIL: Entry point required for feasible/ideal but missing")
    else:
        # For not_suitable, entry point should be null or absent
        entry_point = agent_report.get('proposed_entry_point')
        if entry_point is None:
            score += w_entry
            feedback_parts.append("PASS: No entry point (correct for not_suitable)")
        else:
            score += int(w_entry * 0.5)
            feedback_parts.append("PARTIAL: Entry point provided but classification is not_suitable")
    
    # ============================================================
    # FINAL ASSESSMENT
    # ============================================================
    details['accurate_distances'] = accurate_distances
    details['final_score'] = score
    
    # Pass requires 60 pts AND at least 2 accurate distance measurements (if ground truth available)
    if ground_truth:
        passed = score >= 60 and accurate_distances >= 2
        if score >= 60 and accurate_distances < 2:
            feedback_parts.append(f"NOTE: Score OK but only {accurate_distances}/3 distances accurate (need 2)")
    else:
        # Without ground truth, just check score
        passed = score >= 50
        feedback_parts.append("NOTE: Limited verification without ground truth")
    
    # Cleanup temp directory
    try:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)
    except:
        pass
    
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test mode
    result = verify_liver_ablation_suitability({}, {}, {})
    print(json.dumps(result, indent=2))
    sys.exit(0 if result.get("passed", False) else 1)