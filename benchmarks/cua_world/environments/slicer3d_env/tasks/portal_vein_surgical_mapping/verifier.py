#!/usr/bin/env python3
"""
Verifier for Portal Vein Surgical Mapping task.

VERIFICATION STRATEGY:
1. Check landmark placement accuracy against ground truth
2. Verify portal vein diameter measurement
3. Assess tumor-vessel distance measurement
4. Evaluate relationship and resectability classification
5. Check report completeness

ANTI-GAMING:
- File timestamps checked to ensure work was done during task
- Landmark positions validated to be within anatomical bounds
- Multiple independent criteria required for passing

SCORING (100 points):
- Bifurcation identified: 15 points
- RPV identified: 10 points
- LPV identified: 10 points
- MPV identified: 10 points
- Diameter accurate: 15 points
- Distance measured: 10 points
- Relationship correct: 10 points
- Resectability correct: 10 points
- Report complete: 10 points
"""

import json
import os
import sys
import tempfile
import math
import logging
from typing import Tuple, Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def euclidean_distance(p1: List[float], p2: List[float]) -> float:
    """Calculate 3D Euclidean distance between two points."""
    if not p1 or not p2 or len(p1) < 3 or len(p2) < 3:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1[:3], p2[:3])))


def extract_landmarks_from_markup(markup_data: Dict) -> List[Dict]:
    """Extract landmark points from Slicer markup JSON format."""
    landmarks = []
    
    if not markup_data:
        return landmarks
    
    # Slicer 5.x format
    if 'markups' in markup_data:
        for markup in markup_data.get('markups', []):
            for cp in markup.get('controlPoints', []):
                landmarks.append({
                    'label': cp.get('label', '').strip(),
                    'position': cp.get('position', [0, 0, 0])
                })
    
    # Slicer 4.x format
    elif 'controlPoints' in markup_data:
        for cp in markup_data.get('controlPoints', []):
            landmarks.append({
                'label': cp.get('label', '').strip(),
                'position': cp.get('position', [0, 0, 0])
            })
    
    # Custom format from our export
    if 'fiducials' in markup_data:
        for fid in markup_data.get('fiducials', []):
            landmarks.append({
                'label': fid.get('label', '').strip(),
                'position': fid.get('position', [0, 0, 0])
            })
    
    return landmarks


def find_landmark_by_name(landmarks: List[Dict], name_patterns: List[str]) -> Optional[Dict]:
    """Find a landmark matching any of the name patterns (case-insensitive)."""
    for lm in landmarks:
        label = lm.get('label', '').lower()
        for pattern in name_patterns:
            if pattern.lower() in label:
                return lm
    return None


def find_closest_landmark(target_pos: List[float], landmarks: List[Dict]) -> Tuple[float, Optional[Dict]]:
    """Find the landmark closest to a target position."""
    min_dist = float('inf')
    closest = None
    
    for lm in landmarks:
        pos = lm.get('position', [0, 0, 0])
        dist = euclidean_distance(target_pos, pos)
        if dist < min_dist:
            min_dist = dist
            closest = lm
    
    return min_dist, closest


def verify_portal_vein_mapping(traj: Dict[str, Any], 
                                env_info: Dict[str, Any], 
                                task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the portal vein surgical mapping task.
    
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details'
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
    
    bifurcation_threshold = thresholds.get('bifurcation_distance_max_mm', 15.0)
    branch_threshold = thresholds.get('branch_distance_max_mm', 20.0)
    diameter_threshold = thresholds.get('diameter_error_max_mm', 4.0)
    distance_threshold = thresholds.get('distance_error_max_mm', 5.0)
    
    valid_relationships = metadata.get('valid_relationships', ['Clear', 'Close', 'Abutting', 'Involved'])
    valid_resectability = metadata.get('valid_resectability', ['Resectable', 'Potentially Resectable', 'Likely Unresectable'])
    
    # Initialize results
    results = {
        'total_score': 0,
        'max_score': 100,
        'criteria': {},
        'errors': [],
        'details': {}
    }
    feedback_parts = []
    
    # ================================================================
    # Copy result files from container
    # ================================================================
    result_data = {}
    gt_data = {}
    landmarks_data = {}
    report_data = {}
    
    # Copy main result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/portal_mapping_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        results['errors'].append(f"Failed to read result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load result data: {e}",
            "details": results
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Copy ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/portal_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        results['errors'].append(f"Ground truth load warning: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Copy agent landmarks
    temp_landmarks = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_landmarks.json", temp_landmarks.name)
        with open(temp_landmarks.name, 'r') as f:
            landmarks_data = json.load(f)
    except Exception as e:
        logger.info(f"Could not load agent landmarks: {e}")
    finally:
        if os.path.exists(temp_landmarks.name):
            os.unlink(temp_landmarks.name)
    
    # Copy agent report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
    except Exception as e:
        logger.info(f"Could not load agent report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    # Use embedded data if direct copy failed
    if not landmarks_data:
        landmarks_data = result_data.get('landmarks_data', {})
    if not report_data:
        report_data = result_data.get('report_data', {})
    
    results['details']['result_data'] = result_data
    results['details']['gt_available'] = bool(gt_data)
    
    # ================================================================
    # Anti-gaming checks
    # ================================================================
    if not result_data.get('slicer_was_running', False):
        feedback_parts.append("✗ Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion",
            "details": results
        }
    
    files_modified = result_data.get('files_modified_after_start', False)
    if not files_modified:
        if result_data.get('landmarks_file_exists') or result_data.get('report_file_exists'):
            feedback_parts.append("⚠ Warning: Output files may have existed before task")
            results['details']['anti_gaming_warning'] = True
    
    # Extract agent landmarks
    agent_landmarks = extract_landmarks_from_markup(landmarks_data)
    results['details']['agent_landmarks_count'] = len(agent_landmarks)
    
    # Get ground truth landmarks
    gt_landmarks = gt_data.get('portal_landmarks', {})
    gt_bifurcation = gt_landmarks.get('bifurcation')
    gt_rpv = gt_landmarks.get('rpv_origin')
    gt_lpv = gt_landmarks.get('lpv_origin')
    gt_mpv = gt_landmarks.get('mpv_proximal')
    gt_diameter = gt_landmarks.get('portal_vein_diameter_mm', 0)
    gt_distance = gt_data.get('tumor_vessel_distance_mm', 0)
    gt_relationship = gt_data.get('tumor_vessel_relationship', '')
    gt_resectability = gt_data.get('resectability', '')
    
    # ================================================================
    # CRITERION 1: Bifurcation Identified (15 points)
    # ================================================================
    bifurcation_score = 0
    
    if agent_landmarks:
        # Try to find bifurcation by name first
        bif_landmark = find_landmark_by_name(agent_landmarks, ['bifurcation', 'bif', 'portal'])
        
        if bif_landmark and gt_bifurcation:
            dist = euclidean_distance(bif_landmark['position'], gt_bifurcation)
            results['details']['bifurcation_distance_mm'] = dist
            
            if dist <= bifurcation_threshold:
                bifurcation_score = 15
                feedback_parts.append(f"✓ Bifurcation identified ({dist:.1f}mm from GT)")
            elif dist <= bifurcation_threshold * 2:
                bifurcation_score = 8
                feedback_parts.append(f"~ Bifurcation partially accurate ({dist:.1f}mm)")
            else:
                feedback_parts.append(f"✗ Bifurcation placement inaccurate ({dist:.1f}mm)")
        elif gt_bifurcation:
            # Try closest landmark
            dist, closest = find_closest_landmark(gt_bifurcation, agent_landmarks)
            results['details']['bifurcation_distance_mm'] = dist
            
            if dist <= bifurcation_threshold:
                bifurcation_score = 12
                feedback_parts.append(f"✓ Likely bifurcation found ({dist:.1f}mm)")
            elif dist <= bifurcation_threshold * 2:
                bifurcation_score = 6
                feedback_parts.append(f"~ Possible bifurcation ({dist:.1f}mm)")
            else:
                feedback_parts.append(f"✗ No landmark near bifurcation")
        elif agent_landmarks:
            # No GT available, give partial credit for having landmarks
            bifurcation_score = 5
            feedback_parts.append("? Landmarks placed (GT not available)")
    else:
        feedback_parts.append("✗ No landmarks found")
    
    results['criteria']['bifurcation_identified'] = {
        'score': bifurcation_score,
        'max': 15
    }
    
    # ================================================================
    # CRITERION 2: RPV Identified (10 points)
    # ================================================================
    rpv_score = 0
    
    if agent_landmarks and gt_rpv:
        rpv_landmark = find_landmark_by_name(agent_landmarks, ['rpv', 'right portal', 'right'])
        
        if rpv_landmark:
            dist = euclidean_distance(rpv_landmark['position'], gt_rpv)
            if dist <= branch_threshold:
                rpv_score = 10
                feedback_parts.append(f"✓ RPV identified ({dist:.1f}mm)")
            elif dist <= branch_threshold * 2:
                rpv_score = 5
                feedback_parts.append(f"~ RPV partially identified ({dist:.1f}mm)")
        elif len(agent_landmarks) >= 2:
            dist, _ = find_closest_landmark(gt_rpv, agent_landmarks)
            if dist <= branch_threshold:
                rpv_score = 7
                feedback_parts.append(f"✓ Likely RPV found ({dist:.1f}mm)")
    elif agent_landmarks and len(agent_landmarks) >= 2:
        rpv_score = 3
        feedback_parts.append("? RPV landmark may be present")
    else:
        feedback_parts.append("✗ RPV not identified")
    
    results['criteria']['rpv_identified'] = {
        'score': rpv_score,
        'max': 10
    }
    
    # ================================================================
    # CRITERION 3: LPV Identified (10 points)
    # ================================================================
    lpv_score = 0
    
    if agent_landmarks and gt_lpv:
        lpv_landmark = find_landmark_by_name(agent_landmarks, ['lpv', 'left portal', 'left'])
        
        if lpv_landmark:
            dist = euclidean_distance(lpv_landmark['position'], gt_lpv)
            if dist <= branch_threshold:
                lpv_score = 10
                feedback_parts.append(f"✓ LPV identified ({dist:.1f}mm)")
            elif dist <= branch_threshold * 2:
                lpv_score = 5
                feedback_parts.append(f"~ LPV partially identified ({dist:.1f}mm)")
        elif len(agent_landmarks) >= 3:
            dist, _ = find_closest_landmark(gt_lpv, agent_landmarks)
            if dist <= branch_threshold:
                lpv_score = 7
                feedback_parts.append(f"✓ Likely LPV found ({dist:.1f}mm)")
    elif agent_landmarks and len(agent_landmarks) >= 3:
        lpv_score = 3
        feedback_parts.append("? LPV landmark may be present")
    else:
        feedback_parts.append("✗ LPV not identified")
    
    results['criteria']['lpv_identified'] = {
        'score': lpv_score,
        'max': 10
    }
    
    # ================================================================
    # CRITERION 4: MPV Identified (10 points)
    # ================================================================
    mpv_score = 0
    
    if agent_landmarks and gt_mpv:
        mpv_landmark = find_landmark_by_name(agent_landmarks, ['mpv', 'main portal', 'main', 'proximal'])
        
        if mpv_landmark:
            dist = euclidean_distance(mpv_landmark['position'], gt_mpv)
            if dist <= branch_threshold:
                mpv_score = 10
                feedback_parts.append(f"✓ MPV identified ({dist:.1f}mm)")
            elif dist <= branch_threshold * 2:
                mpv_score = 5
                feedback_parts.append(f"~ MPV partially identified ({dist:.1f}mm)")
        elif len(agent_landmarks) >= 4:
            dist, _ = find_closest_landmark(gt_mpv, agent_landmarks)
            if dist <= branch_threshold:
                mpv_score = 7
                feedback_parts.append(f"✓ Likely MPV found ({dist:.1f}mm)")
    elif agent_landmarks and len(agent_landmarks) >= 4:
        mpv_score = 3
        feedback_parts.append("? MPV landmark may be present")
    else:
        feedback_parts.append("✗ MPV not identified")
    
    results['criteria']['mpv_identified'] = {
        'score': mpv_score,
        'max': 10
    }
    
    # ================================================================
    # CRITERION 5: Diameter Accurate (15 points)
    # ================================================================
    diameter_score = 0
    
    agent_diameter_str = result_data.get('reported_diameter_mm', '') or report_data.get('portal_vein_diameter_mm', '')
    
    if agent_diameter_str and gt_diameter:
        try:
            agent_diameter = float(agent_diameter_str)
            diff = abs(agent_diameter - gt_diameter)
            results['details']['diameter_agent'] = agent_diameter
            results['details']['diameter_gt'] = gt_diameter
            results['details']['diameter_diff'] = diff
            
            if diff <= diameter_threshold:
                diameter_score = 15
                feedback_parts.append(f"✓ Diameter accurate ({agent_diameter:.1f}mm, GT: {gt_diameter:.1f}mm)")
            elif diff <= diameter_threshold * 2:
                diameter_score = 8
                feedback_parts.append(f"~ Diameter partially accurate ({agent_diameter:.1f}mm)")
            else:
                feedback_parts.append(f"✗ Diameter inaccurate ({agent_diameter:.1f}mm, GT: {gt_diameter:.1f}mm)")
        except (TypeError, ValueError) as e:
            feedback_parts.append(f"✗ Invalid diameter value: {agent_diameter_str}")
    elif agent_diameter_str:
        diameter_score = 5
        feedback_parts.append(f"? Diameter measured ({agent_diameter_str}mm) - cannot verify")
    else:
        feedback_parts.append("✗ No diameter measurement in report")
    
    results['criteria']['diameter_accurate'] = {
        'score': diameter_score,
        'max': 15
    }
    
    # ================================================================
    # CRITERION 6: Distance Measured (10 points)
    # ================================================================
    distance_score = 0
    
    agent_distance_str = result_data.get('reported_distance_mm', '') or report_data.get('min_tumor_vessel_distance_mm', '')
    
    if agent_distance_str and gt_distance:
        try:
            agent_distance = float(agent_distance_str)
            diff = abs(agent_distance - gt_distance)
            results['details']['distance_agent'] = agent_distance
            results['details']['distance_gt'] = gt_distance
            
            if diff <= distance_threshold:
                distance_score = 10
                feedback_parts.append(f"✓ Tumor-vessel distance accurate ({agent_distance:.1f}mm)")
            elif diff <= distance_threshold * 2:
                distance_score = 5
                feedback_parts.append(f"~ Distance partially accurate ({agent_distance:.1f}mm)")
            else:
                feedback_parts.append(f"✗ Distance inaccurate ({agent_distance:.1f}mm, GT: {gt_distance:.1f}mm)")
        except (TypeError, ValueError):
            feedback_parts.append(f"✗ Invalid distance value")
    elif agent_distance_str:
        distance_score = 5
        feedback_parts.append(f"? Distance measured ({agent_distance_str}mm)")
    else:
        feedback_parts.append("✗ No tumor-vessel distance in report")
    
    results['criteria']['distance_measured'] = {
        'score': distance_score,
        'max': 10
    }
    
    # ================================================================
    # CRITERION 7: Relationship Correct (10 points)
    # ================================================================
    relationship_score = 0
    
    agent_rel = (result_data.get('reported_relationship', '') or 
                 report_data.get('tumor_vessel_relationship', '')).strip()
    
    if agent_rel and gt_relationship:
        if agent_rel in valid_relationships:
            if agent_rel == gt_relationship:
                relationship_score = 10
                feedback_parts.append(f"✓ Relationship correct: '{agent_rel}'")
            else:
                # Check for adjacent categories (partial credit)
                rel_order = ['Involved', 'Abutting', 'Close', 'Clear']
                try:
                    agent_idx = rel_order.index(agent_rel)
                    gt_idx = rel_order.index(gt_relationship)
                    if abs(agent_idx - gt_idx) == 1:
                        relationship_score = 5
                        feedback_parts.append(f"~ Relationship close: '{agent_rel}' (GT: '{gt_relationship}')")
                    else:
                        feedback_parts.append(f"✗ Relationship incorrect: '{agent_rel}' (GT: '{gt_relationship}')")
                except ValueError:
                    feedback_parts.append(f"✗ Relationship mismatch")
        else:
            feedback_parts.append(f"✗ Invalid relationship: '{agent_rel}'")
    elif agent_rel:
        relationship_score = 3
        feedback_parts.append(f"? Relationship provided: '{agent_rel}'")
    else:
        feedback_parts.append("✗ No relationship classification")
    
    results['criteria']['relationship_correct'] = {
        'score': relationship_score,
        'max': 10
    }
    
    # ================================================================
    # CRITERION 8: Resectability Correct (10 points)
    # ================================================================
    resectability_score = 0
    
    agent_res = (result_data.get('reported_resectability', '') or
                 report_data.get('resectability_assessment', '')).strip()
    
    if agent_res and gt_resectability:
        if agent_res in valid_resectability:
            if agent_res == gt_resectability:
                resectability_score = 10
                feedback_parts.append(f"✓ Resectability correct: '{agent_res}'")
            else:
                res_order = ['Likely Unresectable', 'Potentially Resectable', 'Resectable']
                try:
                    agent_idx = res_order.index(agent_res)
                    gt_idx = res_order.index(gt_resectability)
                    if abs(agent_idx - gt_idx) == 1:
                        resectability_score = 5
                        feedback_parts.append(f"~ Resectability close: '{agent_res}' (GT: '{gt_resectability}')")
                    else:
                        feedback_parts.append(f"✗ Resectability incorrect: '{agent_res}' (GT: '{gt_resectability}')")
                except ValueError:
                    feedback_parts.append(f"✗ Resectability mismatch")
        else:
            feedback_parts.append(f"✗ Invalid resectability: '{agent_res}'")
    elif agent_res:
        resectability_score = 3
        feedback_parts.append(f"? Resectability provided: '{agent_res}'")
    else:
        feedback_parts.append("✗ No resectability assessment")
    
    results['criteria']['resectability_correct'] = {
        'score': resectability_score,
        'max': 10
    }
    
    # ================================================================
    # CRITERION 9: Report Complete (10 points)
    # ================================================================
    report_score = 0
    
    required_fields = [
        'portal_vein_diameter_mm',
        'bifurcation_identified',
        'rpv_identified',
        'lpv_identified',
        'min_tumor_vessel_distance_mm',
        'tumor_vessel_relationship',
        'resectability_assessment'
    ]
    
    if report_data:
        present_fields = sum(1 for f in required_fields if f in report_data and report_data[f] is not None)
        completeness = present_fields / len(required_fields)
        results['details']['report_completeness'] = completeness
        results['details']['report_fields_present'] = present_fields
        
        if completeness >= 1.0:
            report_score = 10
            feedback_parts.append(f"✓ Report complete ({present_fields}/{len(required_fields)} fields)")
        elif completeness >= 0.7:
            report_score = 7
            feedback_parts.append(f"~ Report mostly complete ({present_fields}/{len(required_fields)} fields)")
        elif completeness >= 0.4:
            report_score = 4
            feedback_parts.append(f"~ Report partial ({present_fields}/{len(required_fields)} fields)")
        else:
            feedback_parts.append(f"✗ Report incomplete ({present_fields}/{len(required_fields)} fields)")
    elif result_data.get('report_file_exists'):
        report_score = 2
        feedback_parts.append("✗ Report file exists but could not parse")
    else:
        feedback_parts.append("✗ No surgical planning report created")
    
    results['criteria']['report_complete'] = {
        'score': report_score,
        'max': 10
    }
    
    # ================================================================
    # Calculate total score
    # ================================================================
    total_score = sum(c['score'] for c in results['criteria'].values())
    results['total_score'] = total_score
    
    # Determine pass/fail
    # Requirements: 60+ points, bifurcation identified, report exists
    key_criteria_met = (
        bifurcation_score > 0 and
        result_data.get('report_file_exists', False)
    )
    
    passed = total_score >= 60 and key_criteria_met
    results['passed'] = passed
    results['key_criteria_met'] = key_criteria_met
    
    # Build feedback string
    feedback = f"Portal Vein Surgical Mapping Score: {total_score}/100\n"
    feedback += "=" * 55 + "\n"
    feedback += "\n".join(feedback_parts)
    feedback += "\n" + "=" * 55 + "\n"
    
    if passed:
        feedback += "Result: PASS ✓"
    else:
        feedback += "Result: FAIL ✗"
        reasons = []
        if total_score < 60:
            reasons.append(f"score {total_score} < 60")
        if bifurcation_score == 0:
            reasons.append("bifurcation not identified")
        if not result_data.get('report_file_exists', False):
            reasons.append("report not created")
        if reasons:
            feedback += f" ({', '.join(reasons)})"
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": results
    }


if __name__ == "__main__":
    # For testing
    result = verify_portal_vein_mapping({}, {}, {})
    print(result['feedback'])
    print(f"\nDetails: {json.dumps(result.get('details', {}), indent=2)}")
    sys.exit(0 if result.get('passed', False) else 1)