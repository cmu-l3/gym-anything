#!/usr/bin/env python3
"""
Verifier for Brain Midline Shift Measurement task.

VERIFICATION METRICS:
1. Measurement accuracy - how close is agent's measurement to ground truth shift
2. Direction correctness - did agent identify correct shift direction (left/right)
3. Severity classification - is the severity category correct for the shift value
4. Markup existence - did agent create a valid ruler/line markup
5. Report completeness - does report contain required fields

Scoring (100 points total):
- Measurement accuracy: 35 points (within 5mm tolerance)
- Direction correct: 20 points
- Severity classification: 15 points
- Markup created: 10 points
- Slice selection: 10 points (measurement at plausible brain level)
- Report completeness: 10 points
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


def classify_severity(shift_mm):
    """Classify severity based on shift in mm."""
    if shift_mm < 3:
        return "minimal"
    elif shift_mm < 5:
        return "moderate"
    elif shift_mm < 10:
        return "severe"
    else:
        return "critical"


def verify_brain_midline_shift(traj, env_info, task_info):
    """
    Verify brain midline shift measurement task completion.
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
    
    Returns:
        dict with 'passed', 'score', 'feedback', and 'details'
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
    
    measurement_error_max = thresholds.get('measurement_error_max_mm', 5.0)
    
    w_measurement = weights.get('measurement_accuracy', 35)
    w_direction = weights.get('direction_correct', 20)
    w_severity = weights.get('severity_classification', 15)
    w_markup = weights.get('markup_created', 10)
    w_slice = weights.get('slice_selection', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/midline_task_result.json", temp_result.name)
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
    # ANTI-GAMING: Check timestamps
    # ============================================================
    measurement_created = result.get('measurement_created_during_task', False)
    report_created = result.get('report_created_during_task', False)
    
    if not measurement_created and result.get('measurement_exists', False):
        feedback_parts.append("⚠ Measurement file existed before task started")
        details['anti_gaming_warning'] = "measurement_preexisted"
    
    # ============================================================
    # LOAD GROUND TRUTH
    # ============================================================
    gt_shift_str = result.get('ground_truth_shift_mm', '')
    gt_direction = result.get('ground_truth_direction', '').lower()
    gt_severity = result.get('ground_truth_severity', '').lower()
    
    gt_shift = 0.0
    try:
        gt_shift = float(gt_shift_str) if gt_shift_str else 0.0
    except (ValueError, TypeError):
        gt_shift = 0.0
    
    details['gt_shift_mm'] = gt_shift
    details['gt_direction'] = gt_direction
    details['gt_severity'] = gt_severity
    
    # ============================================================
    # CRITERION 1: MARKUP CREATED (10 points)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    
    if measurement_exists and measurement_created:
        score += w_markup
        feedback_parts.append(f"✓ Measurement markup created ({w_markup} pts)")
    elif measurement_exists:
        score += w_markup // 2
        feedback_parts.append(f"△ Measurement exists but may predate task ({w_markup // 2}/{w_markup} pts)")
    else:
        feedback_parts.append(f"✗ No measurement markup found (0/{w_markup} pts)")
    
    details['markup_exists'] = measurement_exists
    details['markup_created_during_task'] = measurement_created
    
    # ============================================================
    # CRITERION 2: MEASUREMENT ACCURACY (35 points)
    # ============================================================
    agent_shift = 0.0
    
    # Try to get agent's measurement from multiple sources
    measured_shift_str = result.get('measured_shift_mm', '')
    reported_shift_str = result.get('reported_shift_mm', '')
    
    # Prefer measured (from markup) over reported (from report file)
    if measured_shift_str:
        try:
            agent_shift = float(measured_shift_str)
        except (ValueError, TypeError):
            pass
    
    if agent_shift == 0.0 and reported_shift_str:
        try:
            agent_shift = float(reported_shift_str)
        except (ValueError, TypeError):
            pass
    
    details['agent_shift_mm'] = agent_shift
    
    if agent_shift > 0:
        error = abs(agent_shift - gt_shift)
        details['measurement_error_mm'] = error
        
        # Plausibility check
        if agent_shift > 30:
            feedback_parts.append(f"✗ Measurement implausibly large ({agent_shift:.1f}mm > 30mm) (0/{w_measurement} pts)")
        elif error <= 3.0:
            # Within 3mm - full points
            score += w_measurement
            feedback_parts.append(f"✓ Measurement accurate: {agent_shift:.1f}mm (GT: {gt_shift:.1f}mm, error: {error:.1f}mm) ({w_measurement} pts)")
        elif error <= measurement_error_max:
            # Within tolerance - partial points
            partial = int(w_measurement * 0.7)
            score += partial
            feedback_parts.append(f"△ Measurement within {measurement_error_max}mm: {agent_shift:.1f}mm (GT: {gt_shift:.1f}mm, error: {error:.1f}mm) ({partial}/{w_measurement} pts)")
        elif error <= 8.0:
            # Close but outside tolerance
            partial = int(w_measurement * 0.3)
            score += partial
            feedback_parts.append(f"△ Measurement close: {agent_shift:.1f}mm (GT: {gt_shift:.1f}mm, error: {error:.1f}mm) ({partial}/{w_measurement} pts)")
        else:
            feedback_parts.append(f"✗ Measurement inaccurate: {agent_shift:.1f}mm (GT: {gt_shift:.1f}mm, error: {error:.1f}mm) (0/{w_measurement} pts)")
    else:
        feedback_parts.append(f"✗ No valid measurement value found (0/{w_measurement} pts)")
    
    # ============================================================
    # CRITERION 3: DIRECTION CORRECT (20 points)
    # ============================================================
    agent_direction = result.get('reported_direction', '').lower().strip()
    details['agent_direction'] = agent_direction
    
    if agent_direction and gt_direction:
        # Normalize direction values
        agent_dir_normalized = 'left' if 'left' in agent_direction else ('right' if 'right' in agent_direction else agent_direction)
        gt_dir_normalized = 'left' if 'left' in gt_direction else ('right' if 'right' in gt_direction else gt_direction)
        
        if agent_dir_normalized == gt_dir_normalized:
            score += w_direction
            feedback_parts.append(f"✓ Direction correct: {agent_direction} ({w_direction} pts)")
        elif gt_shift < 2.0:
            # Minimal shift - direction ambiguous
            partial = w_direction // 2
            score += partial
            feedback_parts.append(f"△ Direction differs but shift is minimal ({partial}/{w_direction} pts)")
        else:
            feedback_parts.append(f"✗ Direction incorrect: {agent_direction} (GT: {gt_direction}) (0/{w_direction} pts)")
    elif gt_direction == 'none' or gt_shift < 1.0:
        # No significant shift - any direction acceptable
        if agent_direction:
            score += w_direction // 2
            feedback_parts.append(f"△ Direction reported ({agent_direction}) but shift is minimal ({w_direction // 2}/{w_direction} pts)")
        else:
            score += w_direction // 2
            feedback_parts.append(f"△ No direction reported but shift is minimal ({w_direction // 2}/{w_direction} pts)")
    else:
        feedback_parts.append(f"✗ Direction not reported (0/{w_direction} pts)")
    
    # ============================================================
    # CRITERION 4: SEVERITY CLASSIFICATION (15 points)
    # ============================================================
    agent_severity = result.get('reported_severity', '').lower().strip()
    details['agent_severity'] = agent_severity
    
    # Also compute expected severity from agent's measurement for consistency check
    if agent_shift > 0:
        expected_severity_from_measurement = classify_severity(agent_shift)
    else:
        expected_severity_from_measurement = None
    
    severity_order = ["minimal", "moderate", "severe", "critical"]
    
    if agent_severity:
        # Normalize severity
        agent_sev_normalized = None
        for sev in severity_order:
            if sev in agent_severity:
                agent_sev_normalized = sev
                break
        
        if agent_sev_normalized and gt_severity:
            try:
                agent_idx = severity_order.index(agent_sev_normalized)
                gt_idx = severity_order.index(gt_severity)
                
                if agent_sev_normalized == gt_severity:
                    score += w_severity
                    feedback_parts.append(f"✓ Severity classification correct: {agent_severity} ({w_severity} pts)")
                elif abs(agent_idx - gt_idx) == 1:
                    partial = int(w_severity * 0.5)
                    score += partial
                    feedback_parts.append(f"△ Severity off by one: {agent_severity} (GT: {gt_severity}) ({partial}/{w_severity} pts)")
                else:
                    feedback_parts.append(f"✗ Severity incorrect: {agent_severity} (GT: {gt_severity}) (0/{w_severity} pts)")
            except ValueError:
                partial = int(w_severity * 0.3)
                score += partial
                feedback_parts.append(f"△ Severity partially recognized: {agent_severity} ({partial}/{w_severity} pts)")
        elif agent_sev_normalized:
            partial = int(w_severity * 0.3)
            score += partial
            feedback_parts.append(f"△ Severity reported but GT unavailable ({partial}/{w_severity} pts)")
        else:
            feedback_parts.append(f"✗ Unrecognized severity: {agent_severity} (0/{w_severity} pts)")
    else:
        feedback_parts.append(f"✗ Severity not reported (0/{w_severity} pts)")
    
    # ============================================================
    # CRITERION 5: SLICE SELECTION (10 points)
    # Measurement should be at a plausible brain level
    # ============================================================
    if measurement_exists and agent_shift > 0 and agent_shift < 30:
        # Plausible measurement suggests appropriate slice selection
        score += w_slice
        feedback_parts.append(f"✓ Measurement at plausible brain level ({w_slice} pts)")
    elif measurement_exists:
        partial = w_slice // 2
        score += partial
        feedback_parts.append(f"△ Measurement exists but may not be at optimal level ({partial}/{w_slice} pts)")
    else:
        feedback_parts.append(f"✗ Cannot verify slice selection (0/{w_slice} pts)")
    
    # ============================================================
    # CRITERION 6: REPORT COMPLETENESS (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        required_fields = ['shift_mm', 'direction', 'severity']
        fields_present = 0
        
        if result.get('reported_shift_mm'):
            fields_present += 1
        if result.get('reported_direction'):
            fields_present += 1
        if result.get('reported_severity'):
            fields_present += 1
        
        if fields_present == 3:
            score += w_report
            feedback_parts.append(f"✓ Report contains all required fields ({w_report} pts)")
        elif fields_present >= 2:
            partial = int(w_report * 0.7)
            score += partial
            feedback_parts.append(f"△ Report has {fields_present}/3 required fields ({partial}/{w_report} pts)")
        elif fields_present >= 1:
            partial = int(w_report * 0.3)
            score += partial
            feedback_parts.append(f"△ Report has {fields_present}/3 required fields ({partial}/{w_report} pts)")
        else:
            feedback_parts.append(f"✗ Report file exists but missing required fields (0/{w_report} pts)")
    else:
        feedback_parts.append(f"✗ Report file not found (0/{w_report} pts)")
    
    details['report_exists'] = report_exists
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Key criteria for passing: measurement exists AND reasonably accurate
    measurement_error = details.get('measurement_error_mm', float('inf'))
    key_criteria_met = (
        measurement_exists and 
        agent_shift > 0 and 
        measurement_error <= measurement_error_max
    )
    
    passed = score >= 60 and key_criteria_met
    
    details['total_score'] = score
    details['key_criteria_met'] = key_criteria_met
    details['passed'] = passed
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal Score: {score}/100"
    feedback += f"\nPass Threshold: 60 points with measurement error ≤ {measurement_error_max}mm"
    feedback += f"\nKey Criteria Met: {key_criteria_met}"
    feedback += f"\nResult: {'PASS ✓' if passed else 'FAIL ✗'}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": to_python_type(details)
    }


if __name__ == "__main__":
    # Test mode
    result_file = sys.argv[1] if len(sys.argv) > 1 else "/tmp/midline_task_result.json"
    
    # Mock env_info with copy_from_env
    import shutil
    def mock_copy(src, dst):
        shutil.copy(src, dst)
    
    env_info = {'copy_from_env': mock_copy}
    task_info = {
        'metadata': {
            'passing_thresholds': {'measurement_error_max_mm': 5.0},
            'scoring_weights': {
                'measurement_accuracy': 35,
                'direction_correct': 20,
                'severity_classification': 15,
                'markup_created': 10,
                'slice_selection': 10,
                'report_completeness': 10
            }
        }
    }
    
    result = verify_brain_midline_shift({}, env_info, task_info)
    print(result['feedback'])
    print(f"\nDetails: {json.dumps(result.get('details', {}), indent=2)}")
    sys.exit(0 if result.get('passed', False) else 1)