#!/usr/bin/env python3
"""
Verifier for SMA Angle Measurement task.

VERIFICATION STRATEGY:
1. Markup file validity (10 pts): Properly formatted angle markup exists
2. SMA angle accuracy (30 pts): Angle within ±5° of ground truth
3. Anatomical positioning (15 pts): Measurement physiologically plausible
4. Aortomesenteric distance (15 pts): Distance within ±3mm of ground truth
5. Classification correctness (15 pts): Clinical category matches expected
6. Report completeness (10 pts): JSON with all required fields
7. Measurement consistency (5 pts): Classification matches measurements

Pass threshold: 60 points with angle measurement within ±8 degrees
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


def classify_by_measurements(angle, distance=None):
    """Determine classification based on measurements."""
    if angle is None:
        return None
    if angle < 25:
        return "sma_syndrome_likely"
    elif angle <= 38:
        return "borderline"
    else:
        return "normal"


def parse_angle_from_markup(markup_data):
    """Extract angle value from Slicer markup data."""
    try:
        import numpy as np
    except ImportError:
        return None, None
    
    if not markup_data or 'markups' not in markup_data:
        return None, None
    
    for markup in markup_data.get('markups', []):
        if markup.get('type') == 'Angle':
            # Try measurements first
            for m in markup.get('measurements', []):
                if 'angle' in m.get('name', '').lower():
                    angle = m.get('value')
                    cps = markup.get('controlPoints', [])
                    vertex = cps[1].get('position') if len(cps) >= 2 else None
                    return angle, vertex
            
            # Calculate from control points
            cps = markup.get('controlPoints', [])
            if len(cps) >= 3:
                p1 = np.array(cps[0].get('position', [0,0,0]))
                p2 = np.array(cps[1].get('position', [0,0,0]))  # vertex
                p3 = np.array(cps[2].get('position', [0,0,0]))
                
                v1 = p1 - p2
                v2 = p3 - p2
                
                dot = np.dot(v1, v2)
                norms = np.linalg.norm(v1) * np.linalg.norm(v2)
                
                if norms > 0:
                    cos_angle = np.clip(dot / norms, -1, 1)
                    angle = float(np.degrees(np.arccos(cos_angle)))
                    return angle, p2.tolist()
    
    return None, None


def verify_sma_angle_measurement(traj, env_info, task_info):
    """
    Verify SMA angle measurement task completion.
    
    Scoring (100 points total):
    - Markup file validity: 10 points
    - SMA angle accuracy: 30 points
    - Anatomical positioning: 15 points
    - Aortomesenteric distance: 15 points
    - Classification correct: 15 points
    - Report completeness: 10 points
    - Measurement consistency: 5 points
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
    
    angle_error_max = thresholds.get('angle_error_max_degrees', 5.0)
    distance_error_max = thresholds.get('distance_error_max_mm', 3.0)
    
    w_angle = weights.get('angle_accuracy', 30)
    w_position = weights.get('anatomical_position', 15)
    w_distance = weights.get('distance_accuracy', 15)
    w_classification = weights.get('classification_correct', 15)
    w_markup = weights.get('markup_valid', 10)
    w_report = weights.get('report_complete', 10)
    w_consistency = weights.get('consistency', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/sma_angle_result.json", temp_result.name)
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
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    if not result.get('task_attempted', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task was not attempted - no output files created"
        }
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/sma_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use defaults
        gt_data = {
            "sma_angle_degrees": 40.0,
            "sma_angle_tolerance": 5.0,
            "aortomesenteric_distance_mm": 9.5,
            "distance_tolerance_mm": 3.0,
            "expected_classification": "borderline",
            "physiological_range": {"min": 5, "max": 90}
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_angle = gt_data.get('sma_angle_degrees', 40.0)
    gt_tolerance = gt_data.get('sma_angle_tolerance', angle_error_max)
    gt_distance = gt_data.get('aortomesenteric_distance_mm', 9.5)
    gt_dist_tolerance = gt_data.get('distance_tolerance_mm', distance_error_max)
    gt_classification = gt_data.get('expected_classification', 'borderline')
    physio_range = gt_data.get('physiological_range', {"min": 5, "max": 90})
    
    details['ground_truth'] = {
        'angle_degrees': gt_angle,
        'distance_mm': gt_distance,
        'classification': gt_classification
    }
    
    # ============================================================
    # 1. Markup File Validity (10 points)
    # ============================================================
    markup_info = result.get('markup_file', {})
    measured_angle = None
    
    if markup_info.get('exists', False):
        # Check if created during task (anti-gaming)
        if markup_info.get('created_during_task', False):
            # Try to get angle from markup
            measured_angle_str = markup_info.get('measured_angle_degrees', '')
            if measured_angle_str:
                try:
                    measured_angle = float(measured_angle_str)
                    score += w_markup
                    details['markup_valid'] = w_markup
                    feedback_parts.append(f"✓ Markup file created with angle measurement")
                except ValueError:
                    details['markup_valid'] = w_markup // 2
                    score += w_markup // 2
                    feedback_parts.append("◐ Markup file exists but angle extraction failed")
            else:
                details['markup_valid'] = w_markup // 2
                score += w_markup // 2
                feedback_parts.append("◐ Markup file exists but no angle found")
        else:
            details['markup_valid'] = 0
            feedback_parts.append("✗ Markup file existed before task (not created during task)")
    else:
        details['markup_valid'] = 0
        feedback_parts.append("✗ Markup file not found")
    
    # ============================================================
    # 2. SMA Angle Accuracy (30 points)
    # ============================================================
    if measured_angle is not None:
        angle_error = abs(measured_angle - gt_angle)
        details['measured_angle'] = measured_angle
        details['angle_error'] = angle_error
        
        if angle_error <= gt_tolerance:
            score += w_angle
            details['angle_accuracy'] = w_angle
            feedback_parts.append(
                f"✓ Angle measurement accurate: {measured_angle:.1f}° "
                f"(expected {gt_angle:.1f}° ± {gt_tolerance:.0f}°)"
            )
        elif angle_error <= gt_tolerance * 1.6:  # Up to 8 degrees
            partial = int(w_angle * 0.7)
            score += partial
            details['angle_accuracy'] = partial
            feedback_parts.append(
                f"◐ Angle measurement close: {measured_angle:.1f}° "
                f"(expected {gt_angle:.1f}°, error: {angle_error:.1f}°)"
            )
        elif angle_error <= gt_tolerance * 2.5:  # Up to 12.5 degrees
            partial = int(w_angle * 0.4)
            score += partial
            details['angle_accuracy'] = partial
            feedback_parts.append(
                f"◐ Angle measurement approximate: {measured_angle:.1f}° "
                f"(expected {gt_angle:.1f}°, error: {angle_error:.1f}°)"
            )
        else:
            details['angle_accuracy'] = 0
            feedback_parts.append(
                f"✗ Angle measurement inaccurate: {measured_angle:.1f}° "
                f"(expected {gt_angle:.1f}°, error: {angle_error:.1f}°)"
            )
    else:
        details['angle_accuracy'] = 0
        feedback_parts.append("✗ No angle measurement found")
    
    # ============================================================
    # 3. Anatomical Positioning (15 points)
    # ============================================================
    # Check if measurement is physiologically plausible
    if measured_angle is not None:
        min_angle = physio_range.get('min', 5)
        max_angle = physio_range.get('max', 90)
        
        if min_angle <= measured_angle <= max_angle:
            score += w_position
            details['anatomical_position'] = w_position
            feedback_parts.append(
                f"✓ Measurement physiologically plausible ({min_angle}°-{max_angle}°)"
            )
        else:
            details['anatomical_position'] = 0
            feedback_parts.append(
                f"✗ Angle {measured_angle:.1f}° outside physiological range"
            )
    else:
        details['anatomical_position'] = 0
        feedback_parts.append("✗ Cannot verify anatomical position without measurement")
    
    # ============================================================
    # 4. Report Completeness (10 points)
    # ============================================================
    report_info = result.get('report_file', {})
    
    if report_info.get('exists', False) and report_info.get('valid_format', False):
        score += w_report
        details['report_complete'] = w_report
        feedback_parts.append("✓ Report file exists with required fields")
    elif report_info.get('exists', False):
        partial = w_report // 2
        score += partial
        details['report_complete'] = partial
        feedback_parts.append("◐ Report file exists but missing some fields")
    else:
        details['report_complete'] = 0
        feedback_parts.append("✗ Report file not found")
    
    # ============================================================
    # 5. Aortomesenteric Distance (15 points)
    # ============================================================
    reported_distance_str = report_info.get('reported_distance_mm', '')
    reported_distance = None
    
    if reported_distance_str:
        try:
            reported_distance = float(reported_distance_str)
            details['reported_distance'] = reported_distance
            
            distance_error = abs(reported_distance - gt_distance)
            details['distance_error'] = distance_error
            
            if distance_error <= gt_dist_tolerance:
                score += w_distance
                details['distance_accuracy'] = w_distance
                feedback_parts.append(
                    f"✓ Distance measurement accurate: {reported_distance:.1f}mm "
                    f"(expected {gt_distance:.1f}mm ± {gt_dist_tolerance:.0f}mm)"
                )
            elif distance_error <= gt_dist_tolerance * 2:
                partial = int(w_distance * 0.5)
                score += partial
                details['distance_accuracy'] = partial
                feedback_parts.append(
                    f"◐ Distance measurement approximate: {reported_distance:.1f}mm "
                    f"(expected {gt_distance:.1f}mm)"
                )
            else:
                details['distance_accuracy'] = 0
                feedback_parts.append(
                    f"✗ Distance measurement inaccurate: {reported_distance:.1f}mm "
                    f"(expected {gt_distance:.1f}mm)"
                )
        except ValueError:
            details['distance_accuracy'] = 0
            feedback_parts.append("✗ Invalid distance value in report")
    else:
        details['distance_accuracy'] = 0
        feedback_parts.append("✗ No distance measurement in report")
    
    # ============================================================
    # 6. Classification Correctness (15 points)
    # ============================================================
    reported_classification = report_info.get('classification', '').lower().strip()
    
    # Normalize classification strings
    classification_map = {
        "normal": "normal",
        "borderline": "borderline",
        "sma_syndrome_likely": "sma_syndrome_likely",
        "sma syndrome likely": "sma_syndrome_likely",
        "sma_syndrome": "sma_syndrome_likely",
        "abnormal": "sma_syndrome_likely",
        "syndrome": "sma_syndrome_likely"
    }
    
    normalized_classification = classification_map.get(
        reported_classification.replace('_', ' ').replace('-', ' '),
        reported_classification
    )
    details['reported_classification'] = normalized_classification
    
    if normalized_classification == gt_classification:
        score += w_classification
        details['classification_correct'] = w_classification
        feedback_parts.append(f"✓ Classification correct: {reported_classification}")
    elif normalized_classification and measured_angle is not None:
        # Check if internally consistent even if doesn't match GT
        expected_from_measurement = classify_by_measurements(measured_angle, reported_distance)
        if normalized_classification == expected_from_measurement:
            partial = int(w_classification * 0.5)
            score += partial
            details['classification_correct'] = partial
            feedback_parts.append(
                f"◐ Classification {reported_classification} is consistent with measurement "
                f"but differs from ground truth ({gt_classification})"
            )
        else:
            details['classification_correct'] = 0
            feedback_parts.append(
                f"✗ Classification incorrect: {reported_classification} "
                f"(expected {gt_classification})"
            )
    else:
        details['classification_correct'] = 0
        if not reported_classification:
            feedback_parts.append("✗ No classification provided")
        else:
            feedback_parts.append(
                f"✗ Classification incorrect: {reported_classification} "
                f"(expected {gt_classification})"
            )
    
    # ============================================================
    # 7. Measurement Consistency (5 points)
    # ============================================================
    if measured_angle is not None and normalized_classification:
        expected_class = classify_by_measurements(measured_angle, reported_distance)
        if normalized_classification == expected_class:
            score += w_consistency
            details['consistency'] = w_consistency
            feedback_parts.append("✓ Classification is consistent with measurements")
        else:
            details['consistency'] = 0
            feedback_parts.append(
                f"✗ Classification ({reported_classification}) inconsistent with "
                f"measured angle ({measured_angle:.1f}°)"
            )
    else:
        details['consistency'] = 0
        feedback_parts.append("✗ Cannot verify consistency - missing data")
    
    # ============================================================
    # Final Results
    # ============================================================
    details = to_python_type(details)
    
    # Pass threshold: 60 points AND angle within ±8 degrees
    angle_acceptable = False
    if measured_angle is not None:
        angle_acceptable = abs(measured_angle - gt_angle) <= 8.0
    
    passed = (score >= 60) and angle_acceptable
    
    if passed:
        feedback_parts.append(f"\n✓ PASSED with {score}/100 points")
    else:
        if score >= 60 and not angle_acceptable:
            feedback_parts.append(
                f"\n✗ FAILED: Score {score}/100 but angle not within acceptable range (±8°)"
            )
        else:
            feedback_parts.append(f"\n✗ FAILED with {score}/100 points (need 60 and accurate angle)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


def main():
    """Main entry point for standalone verification testing."""
    result_path = "/tmp/sma_angle_result.json"
    
    if len(sys.argv) > 1:
        result_path = sys.argv[1]
    
    # Mock env_info for testing
    class MockCopyFromEnv:
        def __call__(self, src, dst):
            import shutil
            shutil.copy(src, dst)
    
    env_info = {'copy_from_env': MockCopyFromEnv()}
    task_info = {
        'metadata': {
            'passing_thresholds': {
                'angle_error_max_degrees': 5.0,
                'distance_error_max_mm': 3.0
            },
            'scoring_weights': {
                'angle_accuracy': 30,
                'anatomical_position': 15,
                'distance_accuracy': 15,
                'classification_correct': 15,
                'markup_valid': 10,
                'report_complete': 10,
                'consistency': 5
            }
        }
    }
    
    result = verify_sma_angle_measurement({}, env_info, task_info)
    
    print("\n" + "=" * 60)
    print("SMA ANGLE MEASUREMENT VERIFICATION RESULTS")
    print("=" * 60)
    print(f"\nTotal Score: {result['score']}/100")
    print(f"Passed: {'Yes' if result['passed'] else 'No'}")
    print(f"\nFeedback:\n{result['feedback']}")
    
    if 'details' in result:
        print("\nDetails:")
        print(json.dumps(result['details'], indent=2))
    
    return 0 if result['passed'] else 1


if __name__ == "__main__":
    sys.exit(main())