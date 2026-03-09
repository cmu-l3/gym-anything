#!/usr/bin/env python3
"""
Verifier for Thoracic Inlet Assessment task.

Verification Criteria:
1. Measurements exist and were created during task (anti-gaming)
2. Measurements are at correct anatomical level (T1)
3. AP diameter accuracy (within tolerance)
4. Transverse diameter accuracy (within tolerance)
5. Index calculated correctly
6. Classification is consistent with measurements
7. Report completeness

Scoring (100 points total):
- Correct level identified: 20 points
- AP diameter accuracy: 20 points
- Transverse diameter accuracy: 20 points
- Index calculated correctly: 10 points
- Classification correct: 15 points
- Cervical rib assessment: 5 points
- Report completeness: 10 points
"""

import json
import math
import os
import tempfile
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_slicer_markup(markup_data: Dict) -> Tuple[Optional[float], Optional[float], Optional[list]]:
    """
    Parse Slicer markup JSON to extract measurement length and positions.
    
    Returns:
        Tuple of (length_mm, z_position_mm, control_points)
    """
    try:
        # Slicer markup format has "markups" array
        if "markups" not in markup_data or len(markup_data["markups"]) == 0:
            return None, None, None
        
        markup = markup_data["markups"][0]
        
        # Check for control points (line markup has 2 points)
        if "controlPoints" not in markup or len(markup["controlPoints"]) < 2:
            return None, None, None
        
        points = markup["controlPoints"]
        p1 = points[0].get("position", [0, 0, 0])
        p2 = points[1].get("position", [0, 0, 0])
        
        # Calculate length
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        dz = p2[2] - p1[2]
        length = math.sqrt(dx*dx + dy*dy + dz*dz)
        
        # Average Z position
        z_pos = (p1[2] + p2[2]) / 2.0
        
        return length, z_pos, [p1, p2]
        
    except Exception as e:
        logger.warning(f"Error parsing markup: {e}")
        return None, None, None


def verify_thoracic_inlet_assessment(traj, env_info, task_info):
    """
    Verify the thoracic inlet assessment task.
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task configuration with metadata
        
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
    tolerances = metadata.get('tolerances', {})
    weights = metadata.get('scoring_weights', {})
    
    tol_level = tolerances.get('anatomical_level_mm', 10)
    tol_ap = tolerances.get('ap_diameter_mm', 5)
    tol_trans = tolerances.get('transverse_diameter_mm', 8)
    
    w_level = weights.get('correct_level_identified', 20)
    w_ap = weights.get('ap_diameter_accuracy', 20)
    w_trans = weights.get('transverse_diameter_accuracy', 20)
    w_index = weights.get('index_calculated_correctly', 10)
    w_class = weights.get('classification_correct', 15)
    w_cervical = weights.get('cervical_rib_assessment', 5)
    w_report = weights.get('report_completeness', 10)
    
    score = 0
    feedback_parts = []
    details = {
        "ground_truth": {},
        "agent_measurements": {},
        "criteria": {}
    }
    
    # ================================================================
    # Load task result from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # Load ground truth
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use default values
        gt = {
            "t1_z_position_mm": 0,
            "ap_diameter_mm": 47,
            "transverse_diameter_mm": 115,
            "thoracic_inlet_index": 0.41,
            "classification": "Normal",
            "cervical_rib_present": False,
            "tolerance_level_mm": tol_level,
            "tolerance_ap_mm": tol_ap,
            "tolerance_trans_mm": tol_trans
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_t1_z = gt.get("t1_z_position_mm", 0)
    gt_ap = gt.get("ap_diameter_mm", 47)
    gt_trans = gt.get("transverse_diameter_mm", 115)
    gt_index = gt.get("thoracic_inlet_index", 0.41)
    gt_class = gt.get("classification", "Normal")
    gt_cervical = gt.get("cervical_rib_present", False)
    
    details["ground_truth"] = {
        "t1_z_mm": gt_t1_z,
        "ap_diameter_mm": gt_ap,
        "transverse_diameter_mm": gt_trans,
        "index": gt_index,
        "classification": gt_class,
        "cervical_rib": gt_cervical
    }
    
    # ================================================================
    # Check anti-gaming: files created during task
    # ================================================================
    ap_created = result.get("ap_created_after_start", False)
    trans_created = result.get("trans_created_after_start", False)
    
    if not ap_created and not trans_created:
        feedback_parts.append("No measurements created during task (anti-gaming check failed)")
        details["criteria"]["files_created"] = False
    else:
        details["criteria"]["files_created"] = True
    
    # ================================================================
    # Load and parse AP measurement
    # ================================================================
    agent_ap = None
    agent_ap_z = None
    
    temp_ap = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_ap_markup.json", temp_ap.name)
        with open(temp_ap.name, 'r') as f:
            ap_data = json.load(f)
        agent_ap, agent_ap_z, ap_points = parse_slicer_markup(ap_data)
        if agent_ap:
            details["agent_measurements"]["ap_diameter_mm"] = round(agent_ap, 1)
            details["agent_measurements"]["ap_z_position_mm"] = round(agent_ap_z, 1) if agent_ap_z else None
    except FileNotFoundError:
        feedback_parts.append("AP measurement file not found")
    except Exception as e:
        logger.warning(f"Error loading AP markup: {e}")
    finally:
        if os.path.exists(temp_ap.name):
            os.unlink(temp_ap.name)
    
    # ================================================================
    # Load and parse transverse measurement
    # ================================================================
    agent_trans = None
    agent_trans_z = None
    
    temp_trans = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_trans_markup.json", temp_trans.name)
        with open(temp_trans.name, 'r') as f:
            trans_data = json.load(f)
        agent_trans, agent_trans_z, trans_points = parse_slicer_markup(trans_data)
        if agent_trans:
            details["agent_measurements"]["transverse_diameter_mm"] = round(agent_trans, 1)
            details["agent_measurements"]["trans_z_position_mm"] = round(agent_trans_z, 1) if agent_trans_z else None
    except FileNotFoundError:
        feedback_parts.append("Transverse measurement file not found")
    except Exception as e:
        logger.warning(f"Error loading transverse markup: {e}")
    finally:
        if os.path.exists(temp_trans.name):
            os.unlink(temp_trans.name)
    
    # ================================================================
    # CRITERION 1: Correct anatomical level (20 points)
    # ================================================================
    level_correct = False
    
    if agent_ap_z is not None and agent_trans_z is not None:
        ap_level_ok = abs(agent_ap_z - gt_t1_z) <= tol_level
        trans_level_ok = abs(agent_trans_z - gt_t1_z) <= tol_level
        same_level = abs(agent_ap_z - agent_trans_z) <= 5  # Both at same slice
        
        level_correct = ap_level_ok and trans_level_ok and same_level
        
        details["criteria"]["ap_level_ok"] = ap_level_ok
        details["criteria"]["trans_level_ok"] = trans_level_ok
        details["criteria"]["measurements_same_level"] = same_level
        
        if level_correct:
            score += w_level
            feedback_parts.append(f"✓ Measurements at correct T1 level (Z≈{gt_t1_z:.1f}mm)")
        else:
            if not ap_level_ok:
                feedback_parts.append(f"✗ AP not at T1 level: Z={agent_ap_z:.1f}mm, expected≈{gt_t1_z:.1f}mm")
            if not trans_level_ok:
                feedback_parts.append(f"✗ Trans not at T1 level: Z={agent_trans_z:.1f}mm, expected≈{gt_t1_z:.1f}mm")
            if not same_level:
                feedback_parts.append(f"✗ Measurements not at same level")
    elif agent_ap_z is not None or agent_trans_z is not None:
        # Partial credit if one measurement exists
        z = agent_ap_z if agent_ap_z else agent_trans_z
        if abs(z - gt_t1_z) <= tol_level:
            score += w_level // 2
            feedback_parts.append(f"~ Partial: one measurement at correct level")
    else:
        feedback_parts.append("✗ Cannot verify level - no measurement positions available")
    
    details["criteria"]["level_correct"] = level_correct
    
    # ================================================================
    # CRITERION 2: AP diameter accuracy (20 points)
    # ================================================================
    ap_accurate = False
    
    if agent_ap is not None:
        ap_error = abs(agent_ap - gt_ap)
        details["agent_measurements"]["ap_error_mm"] = round(ap_error, 1)
        
        if ap_error <= tol_ap:
            ap_accurate = True
            score += w_ap
            feedback_parts.append(f"✓ AP diameter accurate: {agent_ap:.1f}mm (expected {gt_ap:.1f}±{tol_ap}mm)")
        else:
            feedback_parts.append(f"✗ AP diameter inaccurate: {agent_ap:.1f}mm (expected {gt_ap:.1f}±{tol_ap}mm, error={ap_error:.1f}mm)")
    else:
        feedback_parts.append("✗ AP diameter not measured")
    
    details["criteria"]["ap_accurate"] = ap_accurate
    
    # ================================================================
    # CRITERION 3: Transverse diameter accuracy (20 points)
    # ================================================================
    trans_accurate = False
    
    if agent_trans is not None:
        trans_error = abs(agent_trans - gt_trans)
        details["agent_measurements"]["trans_error_mm"] = round(trans_error, 1)
        
        if trans_error <= tol_trans:
            trans_accurate = True
            score += w_trans
            feedback_parts.append(f"✓ Transverse diameter accurate: {agent_trans:.1f}mm (expected {gt_trans:.1f}±{tol_trans}mm)")
        else:
            feedback_parts.append(f"✗ Transverse diameter inaccurate: {agent_trans:.1f}mm (expected {gt_trans:.1f}±{tol_trans}mm, error={trans_error:.1f}mm)")
    else:
        feedback_parts.append("✗ Transverse diameter not measured")
    
    details["criteria"]["trans_accurate"] = trans_accurate
    
    # ================================================================
    # CRITERION 4-7: Report-based verification
    # ================================================================
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_report = None
    
    try:
        copy_from_env("/tmp/agent_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
    except FileNotFoundError:
        feedback_parts.append("✗ Report file not created")
    except Exception as e:
        feedback_parts.append(f"✗ Error reading report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    if agent_report:
        details["agent_measurements"]["report"] = agent_report
        
        # Check report completeness (10 points)
        required_fields = ["ap_diameter_mm", "transverse_diameter_mm", "thoracic_inlet_index", "classification"]
        missing_fields = [f for f in required_fields if f not in agent_report]
        
        if not missing_fields:
            score += w_report
            feedback_parts.append("✓ Report contains all required fields")
            details["criteria"]["report_complete"] = True
        else:
            feedback_parts.append(f"✗ Report missing fields: {missing_fields}")
            details["criteria"]["report_complete"] = False
        
        # Check index calculation (10 points)
        report_ap = agent_report.get("ap_diameter_mm", 0)
        report_trans = agent_report.get("transverse_diameter_mm", 0)
        report_index = agent_report.get("thoracic_inlet_index", 0)
        
        if report_trans > 0:
            expected_index = report_ap / report_trans
            index_error = abs(report_index - expected_index)
            
            if index_error < 0.02:  # Allow small rounding errors
                score += w_index
                feedback_parts.append(f"✓ Index calculated correctly: {report_index:.3f}")
                details["criteria"]["index_correct"] = True
            else:
                feedback_parts.append(f"✗ Index calculation error: reported {report_index:.3f}, expected {expected_index:.3f}")
                details["criteria"]["index_correct"] = False
        
        # Check classification (15 points)
        report_class = agent_report.get("classification", "").strip()
        
        # Classification should match ground truth
        if report_class.lower() == gt_class.lower():
            score += w_class
            feedback_parts.append(f"✓ Classification correct: {report_class}")
            details["criteria"]["classification_correct"] = True
        else:
            # Also accept if classification is consistent with agent's measurements
            agent_index = agent_ap / agent_trans if (agent_ap and agent_trans and agent_trans > 0) else 0
            
            if agent_index < 0.40 or (agent_ap and agent_ap < 35) or (agent_trans and agent_trans < 90):
                expected_class = "Narrowed"
            elif agent_index > 0.60:
                expected_class = "Wide"
            else:
                expected_class = "Normal"
            
            if report_class.lower() == expected_class.lower():
                score += w_class
                feedback_parts.append(f"✓ Classification consistent with measurements: {report_class}")
                details["criteria"]["classification_correct"] = True
            else:
                feedback_parts.append(f"✗ Classification '{report_class}' doesn't match expected '{gt_class}' or agent measurements")
                details["criteria"]["classification_correct"] = False
        
        # Check cervical rib assessment (5 points)
        report_cervical = agent_report.get("cervical_rib_present", None)
        if report_cervical is not None:
            if report_cervical == gt_cervical:
                score += w_cervical
                feedback_parts.append(f"✓ Cervical rib assessment correct: {report_cervical}")
                details["criteria"]["cervical_rib_correct"] = True
            else:
                feedback_parts.append(f"✗ Cervical rib assessment incorrect: reported {report_cervical}, expected {gt_cervical}")
                details["criteria"]["cervical_rib_correct"] = False
    
    # ================================================================
    # Sanity checks (anti-gaming)
    # ================================================================
    if agent_ap is not None and not (25 <= agent_ap <= 70):
        feedback_parts.append(f"⚠ AP measurement {agent_ap:.1f}mm outside physiological range (25-70mm)")
        score = max(0, score - 10)
    
    if agent_trans is not None and not (60 <= agent_trans <= 160):
        feedback_parts.append(f"⚠ Transverse measurement {agent_trans:.1f}mm outside physiological range (60-160mm)")
        score = max(0, score - 10)
    
    # ================================================================
    # Final score calculation
    # ================================================================
    score = max(0, min(100, score))
    
    # Determine pass/fail
    # Must have level correct AND at least one accurate measurement to pass
    key_criteria_met = level_correct and (ap_accurate or trans_accurate)
    passed = score >= 60 and key_criteria_met
    
    details["final_score"] = score
    details["key_criteria_met"] = key_criteria_met
    
    feedback_str = " | ".join(feedback_parts) if feedback_parts else "No feedback"
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback_str,
        "details": details
    }


if __name__ == "__main__":
    # Test verification locally
    print("Thoracic Inlet Assessment Verifier")
    print("===================================")
    print("This verifier checks:")
    print("  - Measurement placement at T1 level")
    print("  - AP diameter accuracy (±5mm)")
    print("  - Transverse diameter accuracy (±8mm)")
    print("  - Index calculation")
    print("  - Clinical classification")
    print("  - Report completeness")