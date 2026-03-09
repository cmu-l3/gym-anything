#!/usr/bin/env python3
"""
Verifier for abdominal aorta measurement task.

VERIFICATION METRICS:
1. Diameter accuracy - how close is agent's measurement to ground truth
2. Clinical classification - Normal/Ectatic/Aneurysmal
3. Measurement placed - did agent use a ruler/measurement tool
4. Vertebral level - approximate location accuracy
5. Report completeness

Ground Truth: AMOS 2022 dataset with aorta segmentation label
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


def verify_aorta_measurement(traj, env_info, task_info):
    """
    Verify aorta measurement task completion.

    Scoring (100 points total):
    - Diameter accuracy: 35 points (within 5mm)
    - Classification correct: 25 points
    - Measurement placed: 15 points (ruler/line markup exists)
    - Vertebral level: 10 points (within 1 level)
    - Report completeness: 15 points
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

    diameter_error_max = thresholds.get('diameter_error_max_mm', 5.0)

    w_diameter = weights.get('diameter_accuracy', 35)
    w_classification = weights.get('classification_correct', 25)
    w_measurement = weights.get('measurement_placed', 15)
    w_level = weights.get('vertebral_level', 10)
    w_report = weights.get('report_completeness', 15)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/aorta_task_result.json", temp_result.name)
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
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/aorta_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_diameter = gt_data.get('max_diameter_mm', 0)
    gt_classification = gt_data.get('classification', '')
    gt_vertebral_level = gt_data.get('approximate_vertebral_level', '')

    details['gt_diameter_mm'] = gt_diameter
    details['gt_classification'] = gt_classification
    details['gt_vertebral_level'] = gt_vertebral_level

    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    agent_diameter = 0.0
    agent_classification = ''
    agent_level = ''

    # Try from reported diameter in result
    reported_diam_str = result.get('reported_diameter_mm', '')
    if reported_diam_str:
        try:
            agent_diameter = float(reported_diam_str)
        except (ValueError, TypeError):
            pass

    # Try from measurement file
    if agent_diameter == 0 and result.get('measurement_exists', False):
        temp_meas = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/aorta_agent_measurement.json", temp_meas.name)
            with open(temp_meas.name, 'r') as f:
                meas_data = json.load(f)
                for m in meas_data.get('measurements', []):
                    if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
                        agent_diameter = float(m['length_mm'])
                        break
        except Exception as e:
            logger.warning(f"Failed to load measurement: {e}")
        finally:
            if os.path.exists(temp_meas.name):
                os.unlink(temp_meas.name)

    # Try from agent report
    if result.get('report_exists', False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/aorta_agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report = json.load(f)

            # Extract diameter from report
            if agent_diameter == 0:
                for key in ['max_diameter_mm', 'diameter_mm', 'diameter',
                            'maximum_diameter', 'max_diameter']:
                    if key in report:
                        try:
                            agent_diameter = float(report[key])
                            break
                        except (ValueError, TypeError):
                            pass

            # Extract classification
            for key in ['classification', 'assessment', 'clinical_assessment',
                        'clinical_classification']:
                if key in report:
                    agent_classification = str(report[key])
                    break

            # Extract vertebral level
            for key in ['vertebral_level', 'level', 'location']:
                if key in report:
                    agent_level = str(report[key])
                    break

        except Exception as e:
            logger.warning(f"Failed to load report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # Get classification from result if not from report
    if not agent_classification:
        agent_classification = result.get('reported_classification', '')
    if not agent_level:
        agent_level = result.get('reported_vertebral_level', '')

    details['agent_diameter_mm'] = round(agent_diameter, 2) if agent_diameter else 0
    details['agent_classification'] = agent_classification
    details['agent_vertebral_level'] = agent_level

    # ============================================================
    # MEASUREMENT PLACED (15 points)
    # ============================================================
    measurement_placed = result.get('measurement_exists', False) or agent_diameter > 0
    details['measurement_placed'] = measurement_placed

    if measurement_placed:
        meas_score = w_measurement
        feedback_parts.append("Measurement: placed")
    else:
        meas_score = 0
        feedback_parts.append("Measurement: NOT placed")
    score += meas_score
    details['score_measurement'] = meas_score

    # ============================================================
    # DIAMETER ACCURACY (35 points)
    # ============================================================
    if agent_diameter > 0 and gt_diameter > 0:
        diameter_error = abs(agent_diameter - gt_diameter)
        details['diameter_error_mm'] = round(diameter_error, 2)

        if diameter_error <= diameter_error_max:
            diam_score = w_diameter
            feedback_parts.append(f"Diameter: {agent_diameter:.1f}mm (error: {diameter_error:.1f}mm, within {diameter_error_max}mm)")
        elif diameter_error <= 10:
            diam_score = int(w_diameter * 0.5)
            feedback_parts.append(f"Diameter: {agent_diameter:.1f}mm (error: {diameter_error:.1f}mm)")
        elif diameter_error <= 15:
            diam_score = int(w_diameter * 0.2)
            feedback_parts.append(f"Diameter: {agent_diameter:.1f}mm (error: {diameter_error:.1f}mm, poor)")
        else:
            diam_score = 0
            feedback_parts.append(f"Diameter: {agent_diameter:.1f}mm (error: {diameter_error:.1f}mm, too large)")
    elif agent_diameter > 0:
        diam_score = int(w_diameter * 0.3)  # Partial credit for measuring something
        feedback_parts.append(f"Diameter: {agent_diameter:.1f}mm (no GT to compare)")
    else:
        diam_score = 0
        feedback_parts.append("Diameter: no measurement found")
    score += diam_score
    details['score_diameter'] = diam_score

    # ============================================================
    # CLASSIFICATION CORRECT (25 points)
    # ============================================================
    if agent_classification and gt_classification:
        # Normalize classification strings
        agent_class_norm = agent_classification.strip().lower()
        gt_class_norm = gt_classification.strip().lower()

        classification_correct = agent_class_norm == gt_class_norm

        # Also check if agent derived correct classification from their own measurement
        if agent_diameter > 0:
            if agent_diameter < 30:
                derived_class = 'normal'
            elif agent_diameter < 35:
                derived_class = 'ectatic'
            else:
                derived_class = 'aneurysmal'
            derived_correct = derived_class == gt_class_norm
        else:
            derived_correct = False

        details['classification_correct'] = classification_correct
        details['derived_classification_correct'] = derived_correct

        if classification_correct:
            class_score = w_classification
            feedback_parts.append(f"Classification: {agent_classification} (correct)")
        elif derived_correct:
            # Agent's measurement would give correct classification even if they stated wrong
            class_score = int(w_classification * 0.5)
            feedback_parts.append(f"Classification: {agent_classification} (measurement implies correct class)")
        else:
            class_score = 0
            feedback_parts.append(f"Classification: {agent_classification} (GT: {gt_classification})")
    elif agent_classification:
        class_score = int(w_classification * 0.3)
        feedback_parts.append(f"Classification: {agent_classification} (no GT)")
    else:
        class_score = 0
        feedback_parts.append("Classification: NOT provided")
    score += class_score
    details['score_classification'] = class_score

    # ============================================================
    # VERTEBRAL LEVEL (10 points)
    # ============================================================
    if agent_level and gt_vertebral_level:
        # Parse vertebral levels for comparison
        vertebral_order = ['T12', 'L1', 'L2', 'L3', 'L4', 'L5', 'S1']

        agent_level_norm = agent_level.upper().strip()
        gt_level_norm = gt_vertebral_level.upper().strip()

        level_exact = agent_level_norm == gt_level_norm

        # Check if within 1 level
        level_close = False
        if agent_level_norm in vertebral_order and gt_level_norm in vertebral_order:
            agent_idx = vertebral_order.index(agent_level_norm)
            gt_idx = vertebral_order.index(gt_level_norm)
            level_close = abs(agent_idx - gt_idx) <= 1

        details['level_exact_match'] = level_exact
        details['level_close_match'] = level_close

        if level_exact:
            level_score = w_level
            feedback_parts.append(f"Level: {agent_level} (exact)")
        elif level_close:
            level_score = int(w_level * 0.5)
            feedback_parts.append(f"Level: {agent_level} (close, GT: {gt_vertebral_level})")
        else:
            level_score = 0
            feedback_parts.append(f"Level: {agent_level} (GT: {gt_vertebral_level})")
    elif agent_level:
        level_score = int(w_level * 0.3)
        feedback_parts.append(f"Level: {agent_level}")
    else:
        level_score = 0
        feedback_parts.append("Level: NOT reported")
    score += level_score
    details['score_level'] = level_score

    # ============================================================
    # REPORT COMPLETENESS (15 points)
    # ============================================================
    if result.get('report_exists', False):
        temp_report2 = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/aorta_agent_report.json", temp_report2.name)
            with open(temp_report2.name, 'r') as f:
                report = json.load(f)

            required_fields = ['diameter', 'classification', 'vertebral_level']
            found = 0
            for field in required_fields:
                for key in report.keys():
                    if field.replace('_', '') in key.lower().replace('_', ''):
                        found += 1
                        break

            report_score = int(w_report * (found / len(required_fields)))
            feedback_parts.append(f"Report: {found}/{len(required_fields)} fields")
        except Exception:
            report_score = int(w_report * 0.2)
            feedback_parts.append("Report: error reading")
        finally:
            if os.path.exists(temp_report2.name):
                os.unlink(temp_report2.name)
    else:
        report_score = 0
        feedback_parts.append("Report: NOT created")
    score += report_score
    details['score_report'] = report_score

    # ============================================================
    # FINAL SCORING
    # ============================================================
    diameter_ok = (agent_diameter > 0 and gt_diameter > 0 and
                   abs(agent_diameter - gt_diameter) <= diameter_error_max)
    classification_ok = (agent_classification.strip().lower() ==
                         gt_classification.strip().lower()) if (agent_classification and gt_classification) else False

    passed = diameter_ok and classification_ok and score >= 50

    if passed:
        if score >= 85:
            feedback_parts.append("Excellent measurement!")
        elif score >= 70:
            feedback_parts.append("Good measurement")
        else:
            feedback_parts.append("Acceptable measurement")
    else:
        reasons = []
        if not diameter_ok:
            reasons.append("diameter accuracy")
        if not classification_ok:
            reasons.append("classification")
        feedback_parts.append(f"Task NOT completed - improve {', '.join(reasons)}")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }
