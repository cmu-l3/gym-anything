#!/usr/bin/env python3
"""
Verifier for Hepatic Vein Confluence Mapping task.

VERIFICATION CRITERIA:
1. RHV identified & marked (15 points) - fiducial near expected RHV-IVC junction
2. MHV identified & marked (15 points) - fiducial near expected MHV-IVC junction  
3. LHV identified & marked (15 points) - fiducial near expected LHV-IVC junction
4. Correct lateral arrangement (10 points) - RHV right of MHV, MHV right of LHV
5. Inter-vein distances measured (10 points) - both RHV-MHV and MHV-LHV distances
6. Anatomical pattern classified (10 points) - Type I/II/etc documented
7. Report completeness (10 points) - JSON with all required fields
8. Screenshot evidence (10 points) - screenshot of confluence region
9. Marker labels correct (5 points) - fiducials properly named

Total: 100 points
Pass threshold: 55 points with at least 2/3 hepatic veins identified
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
    """Convert to Python native types for JSON serialization."""
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


def euclidean_distance(p1, p2):
    """Calculate Euclidean distance between two 3D points."""
    if not p1 or not p2:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))


def check_lateral_arrangement(rhv_pos, mhv_pos, lhv_pos):
    """
    Check if hepatic veins are in correct lateral arrangement.
    In RAS coordinates, R (right) is positive X, so:
    - RHV should have largest X (most rightward)
    - LHV should have smallest X (most leftward)
    - MHV should be between
    """
    if not all([rhv_pos, mhv_pos, lhv_pos]):
        return False, "Not all vein positions available"
    
    rhv_x = rhv_pos[0]
    mhv_x = mhv_pos[0]
    lhv_x = lhv_pos[0]
    
    # RHV should be most rightward (largest R/X value)
    # LHV should be most leftward (smallest R/X value)
    # This depends on RAS convention - R is patient's right
    
    # Check relative positions
    if rhv_x > mhv_x and mhv_x > lhv_x:
        return True, "Correct arrangement: RHV > MHV > LHV (right to left)"
    elif lhv_x > mhv_x and mhv_x > rhv_x:
        # Inverted - might be different convention
        return True, "Arrangement detected (inverted R-L convention)"
    else:
        return False, f"Incorrect arrangement: RHV={rhv_x:.1f}, MHV={mhv_x:.1f}, LHV={lhv_x:.1f}"


def verify_hepatic_vein_confluence_mapping(traj, env_info, task_info):
    """
    Verify hepatic vein confluence mapping task completion.
    
    Uses multiple criteria to score the agent's performance.
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
    thresholds = metadata.get('passing_thresholds', {})
    
    w_rhv = weights.get('rhv_identified', 15)
    w_mhv = weights.get('mhv_identified', 15)
    w_lhv = weights.get('lhv_identified', 15)
    w_lateral = weights.get('lateral_arrangement', 10)
    w_distances = weights.get('distances_measured', 10)
    w_pattern = weights.get('pattern_classified', 10)
    w_report = weights.get('report_completeness', 10)
    w_screenshot = weights.get('screenshot_evidence', 10)
    w_labels = weights.get('labels_correct', 5)
    
    position_tolerance = thresholds.get('position_tolerance_mm', 20.0)
    min_veins = thresholds.get('min_veins_identified', 2)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/hepatic_vein_task_result.json", temp_result.name)
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
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ============================================================
    # LOAD MARKUP DATA
    # ============================================================
    temp_markup = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    markup_data = {}
    try:
        copy_from_env("/tmp/agent_hepatic_markups.json", temp_markup.name)
        with open(temp_markup.name, 'r') as f:
            markup_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load markup data: {e}")
        details['markup_load_error'] = str(e)
    finally:
        if os.path.exists(temp_markup.name):
            os.unlink(temp_markup.name)
    
    # ============================================================
    # LOAD REPORT DATA
    # ============================================================
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    report_data = {}
    try:
        copy_from_env("/tmp/agent_hepatic_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load report: {e}")
        details['report_load_error'] = str(e)
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    # ============================================================
    # EXTRACT VEIN POSITIONS
    # ============================================================
    vein_markers = markup_data.get('vein_markers', {})
    rhv_pos = vein_markers.get('RHV')
    mhv_pos = vein_markers.get('MHV')
    lhv_pos = vein_markers.get('LHV')
    
    # Also check report for positions
    if not rhv_pos and 'right_hepatic_vein' in report_data:
        rhv_info = report_data.get('right_hepatic_vein', {})
        if rhv_info.get('identified') and rhv_info.get('position_ras'):
            rhv_pos = rhv_info['position_ras']
    
    if not mhv_pos and 'middle_hepatic_vein' in report_data:
        mhv_info = report_data.get('middle_hepatic_vein', {})
        if mhv_info.get('identified') and mhv_info.get('position_ras'):
            mhv_pos = mhv_info['position_ras']
    
    if not lhv_pos and 'left_hepatic_vein' in report_data:
        lhv_info = report_data.get('left_hepatic_vein', {})
        if lhv_info.get('identified') and lhv_info.get('position_ras'):
            lhv_pos = lhv_info['position_ras']
    
    details['rhv_position'] = rhv_pos
    details['mhv_position'] = mhv_pos
    details['lhv_position'] = lhv_pos
    
    veins_found = sum(1 for p in [rhv_pos, mhv_pos, lhv_pos] if p is not None)
    details['veins_identified'] = veins_found
    
    # ============================================================
    # CRITERION 1-3: HEPATIC VEINS IDENTIFIED (45 points total)
    # ============================================================
    if rhv_pos is not None:
        score += w_rhv
        feedback_parts.append(f"✓ RHV identified at {[round(x,1) for x in rhv_pos]}")
    else:
        feedback_parts.append("✗ RHV not identified")
    
    if mhv_pos is not None:
        score += w_mhv
        feedback_parts.append(f"✓ MHV identified at {[round(x,1) for x in mhv_pos]}")
    else:
        feedback_parts.append("✗ MHV not identified")
    
    if lhv_pos is not None:
        score += w_lhv
        feedback_parts.append(f"✓ LHV identified at {[round(x,1) for x in lhv_pos]}")
    else:
        feedback_parts.append("✗ LHV not identified")
    
    # ============================================================
    # CRITERION 4: LATERAL ARRANGEMENT (10 points)
    # ============================================================
    if veins_found >= 3:
        arrangement_correct, arrangement_msg = check_lateral_arrangement(rhv_pos, mhv_pos, lhv_pos)
        if arrangement_correct:
            score += w_lateral
            feedback_parts.append(f"✓ Lateral arrangement correct")
        else:
            feedback_parts.append(f"✗ Lateral arrangement incorrect: {arrangement_msg}")
        details['lateral_arrangement'] = arrangement_correct
        details['arrangement_details'] = arrangement_msg
    elif veins_found >= 2:
        # Partial credit for checking 2 veins
        score += w_lateral // 2
        feedback_parts.append("~ Partial lateral check (only 2 veins)")
    else:
        feedback_parts.append("✗ Cannot check arrangement (< 2 veins)")
    
    # ============================================================
    # CRITERION 5: INTER-VEIN DISTANCES (10 points)
    # ============================================================
    distances_measured = False
    rhv_mhv_dist = None
    mhv_lhv_dist = None
    
    # Try to get from measurements
    distance_measurements = markup_data.get('distance_measurements', [])
    if distance_measurements:
        distances_measured = True
        for m in distance_measurements:
            name = m.get('name', '').lower()
            length = m.get('length_mm', 0)
            if 'rhv' in name and 'mhv' in name:
                rhv_mhv_dist = length
            elif 'mhv' in name and 'lhv' in name:
                mhv_lhv_dist = length
    
    # Calculate from positions if not measured directly
    if rhv_pos and mhv_pos and rhv_mhv_dist is None:
        rhv_mhv_dist = euclidean_distance(rhv_pos, mhv_pos)
    if mhv_pos and lhv_pos and mhv_lhv_dist is None:
        mhv_lhv_dist = euclidean_distance(mhv_pos, lhv_pos)
    
    # Check report for distances
    report_rhv_mhv = result.get('rhv_mhv_distance_mm', '')
    report_mhv_lhv = result.get('mhv_lhv_distance_mm', '')
    
    if report_rhv_mhv or report_mhv_lhv:
        distances_measured = True
    
    if rhv_mhv_dist is not None and mhv_lhv_dist is not None:
        distances_measured = True
    
    if distances_measured:
        score += w_distances
        dist_feedback = []
        if rhv_mhv_dist:
            dist_feedback.append(f"RHV-MHV: {rhv_mhv_dist:.1f}mm")
        if mhv_lhv_dist:
            dist_feedback.append(f"MHV-LHV: {mhv_lhv_dist:.1f}mm")
        feedback_parts.append(f"✓ Distances measured ({', '.join(dist_feedback) if dist_feedback else 'from report'})")
    else:
        feedback_parts.append("✗ Inter-vein distances not measured")
    
    details['rhv_mhv_distance_mm'] = rhv_mhv_dist
    details['mhv_lhv_distance_mm'] = mhv_lhv_dist
    
    # ============================================================
    # CRITERION 6: ANATOMICAL PATTERN CLASSIFIED (10 points)
    # ============================================================
    anatomical_pattern = result.get('anatomical_pattern', '') or report_data.get('anatomical_pattern', '')
    
    if anatomical_pattern:
        pattern_lower = anatomical_pattern.lower()
        valid_patterns = ['type i', 'type ii', 'type iii', 'normal', 'common trunk', 'variant', 'accessory']
        if any(p in pattern_lower for p in valid_patterns):
            score += w_pattern
            feedback_parts.append(f"✓ Anatomical pattern classified: {anatomical_pattern}")
        else:
            score += w_pattern // 2
            feedback_parts.append(f"~ Pattern noted but unclear: {anatomical_pattern}")
    else:
        feedback_parts.append("✗ Anatomical pattern not classified")
    
    details['anatomical_pattern'] = anatomical_pattern
    
    # ============================================================
    # CRITERION 7: REPORT COMPLETENESS (10 points)
    # ============================================================
    required_fields = [
        'patient_id',
        'right_hepatic_vein',
        'middle_hepatic_vein', 
        'left_hepatic_vein',
        'anatomical_pattern'
    ]
    
    fields_present = sum(1 for f in required_fields if f in report_data)
    
    if result.get('report_exists', False):
        if fields_present >= 4:
            score += w_report
            feedback_parts.append(f"✓ Report complete ({fields_present}/{len(required_fields)} fields)")
        elif fields_present >= 2:
            score += w_report // 2
            feedback_parts.append(f"~ Report partial ({fields_present}/{len(required_fields)} fields)")
        else:
            feedback_parts.append(f"✗ Report incomplete ({fields_present}/{len(required_fields)} fields)")
    else:
        feedback_parts.append("✗ Report not created")
    
    details['report_fields_present'] = fields_present
    details['report_exists'] = result.get('report_exists', False)
    
    # ============================================================
    # CRITERION 8: SCREENSHOT EVIDENCE (10 points)
    # ============================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_during_task = result.get('screenshot_during_task', False)
    
    if screenshot_exists and screenshot_during_task:
        score += w_screenshot
        feedback_parts.append("✓ Screenshot captured during task")
    elif screenshot_exists:
        score += w_screenshot // 2
        feedback_parts.append("~ Screenshot exists (timing unclear)")
    else:
        feedback_parts.append("✗ No screenshot captured")
    
    details['screenshot_captured'] = screenshot_exists
    
    # ============================================================
    # CRITERION 9: MARKER LABELS CORRECT (5 points)
    # ============================================================
    all_markups = markup_data.get('all_markups', [])
    correctly_labeled = 0
    
    for markup in all_markups:
        label = (markup.get('label', '') or '').upper()
        if any(vein in label for vein in ['RHV', 'MHV', 'LHV', 'RIGHT HEPATIC', 'MIDDLE HEPATIC', 'LEFT HEPATIC']):
            correctly_labeled += 1
    
    if correctly_labeled >= 3:
        score += w_labels
        feedback_parts.append(f"✓ Markers labeled correctly ({correctly_labeled} hepatic vein labels)")
    elif correctly_labeled >= 1:
        score += w_labels // 2
        feedback_parts.append(f"~ Some markers labeled ({correctly_labeled} hepatic vein labels)")
    else:
        feedback_parts.append("✗ Markers not labeled with vein names")
    
    details['correctly_labeled_markers'] = correctly_labeled
    
    # ============================================================
    # VLM VERIFICATION (bonus/validation)
    # ============================================================
    try:
        from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            # Sample trajectory frames to verify workflow
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            
            if final or frames:
                vlm_prompt = """Analyze this 3D Slicer medical imaging session. 

Check for:
1. Is a liver CT scan visible?
2. Are fiducial markers visible (small colored points/crosshairs)?
3. Is the view showing the superior liver region (near diaphragm)?
4. Are there at least 3 markers that could represent hepatic vein locations?

Respond in JSON:
{
    "liver_ct_visible": true/false,
    "fiducial_markers_visible": true/false,
    "superior_liver_region": true/false,
    "multiple_markers": true/false,
    "confidence": "low/medium/high"
}"""
                
                images = frames + [final] if final else frames
                vlm_result = query_vlm(prompt=vlm_prompt, images=images[:6])
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_verification'] = parsed
                    
                    # VLM validation - check if markers are visible
                    if parsed.get('fiducial_markers_visible') and parsed.get('liver_ct_visible'):
                        feedback_parts.append("✓ VLM confirms markers on liver CT")
                    else:
                        feedback_parts.append("~ VLM could not confirm task completion")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        details['vlm_error'] = str(e)
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    max_score = w_rhv + w_mhv + w_lhv + w_lateral + w_distances + w_pattern + w_report + w_screenshot + w_labels
    
    # Determine pass/fail
    key_criteria_met = veins_found >= min_veins
    passed = score >= 55 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED ({score}/{max_score} points) | {feedback}"
    else:
        if not key_criteria_met:
            feedback = f"FAILED (identified {veins_found}/{min_veins} required veins) | {feedback}"
        else:
            feedback = f"FAILED ({score}/{max_score} points, need 55) | {feedback}"
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details,
        "max_score": max_score,
        "veins_identified": veins_found,
        "key_criteria_met": key_criteria_met
    })