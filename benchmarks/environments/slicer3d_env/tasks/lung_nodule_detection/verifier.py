#!/usr/bin/env python3
"""
Verifier for lung nodule detection task using LIDC-IDRI metrics.

VERIFICATION METRICS:
1. Detection Recall - fraction of ground truth nodules found
2. Detection Precision - fraction of agent's marks that are real nodules
3. Diameter Accuracy - how close measured diameters are to ground truth
4. Lobe Location Accuracy - correct anatomical location reporting
5. Window/Level - did agent adjust to lung window

LIDC-IDRI Annotations:
- Nodules annotated by 4 thoracic radiologists
- Consensus nodules: agreed by >= 2 readers
- Only nodules >= 3mm are considered significant
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
    elif isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def parse_fcsv(fcsv_path):
    """
    Parse a 3D Slicer .fcsv fiducial file.

    Returns list of dicts with 'label', 'x', 'y', 'z' coordinates (RAS).
    """
    points = []
    with open(fcsv_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split(',')
            if len(parts) >= 4:
                try:
                    point = {
                        'id': parts[0] if parts[0] else f"point_{len(points)}",
                        'x': float(parts[1]),
                        'y': float(parts[2]),
                        'z': float(parts[3]),
                        'label': parts[11] if len(parts) > 11 else parts[0],
                    }
                    points.append(point)
                except (ValueError, IndexError):
                    continue
    return points


def match_detections(agent_points, gt_nodules, tolerance_mm=15.0):
    """
    Match agent's fiducial points to ground truth nodules.

    Uses greedy matching: for each agent point, find closest unmatched GT nodule.

    Args:
        agent_points: List of dicts with 'x', 'y', 'z' keys
        gt_nodules: List of dicts with 'centroid_mm' key (list of 3 floats)
        tolerance_mm: Maximum distance to count as a match

    Returns:
        dict with precision, recall, f1, and per-nodule matches
    """
    if not gt_nodules:
        return {
            'true_positives': 0,
            'false_positives': len(agent_points),
            'missed': 0,
            'precision': 0.0 if agent_points else 1.0,
            'recall': 1.0,
            'f1': 0.0 if agent_points else 1.0,
            'matches': [],
        }

    if not agent_points:
        return {
            'true_positives': 0,
            'false_positives': 0,
            'missed': len(gt_nodules),
            'precision': 0.0,
            'recall': 0.0,
            'f1': 0.0,
            'matches': [],
        }

    # Compute distance matrix
    gt_centroids = np.array([n.get('centroid_mm', n.get('centroid_xyz', [0, 0, 0]))
                             for n in gt_nodules])
    agent_coords = np.array([[p['x'], p['y'], p['z']] for p in agent_points])

    # Note: Slicer uses RAS coordinates, GT might be in different format
    # We compute distances and allow for coordinate system differences
    dist_matrix = np.sqrt(np.sum(
        (agent_coords[:, np.newaxis, :] - gt_centroids[np.newaxis, :, :]) ** 2,
        axis=2
    ))

    # Greedy matching
    matched_gt = set()
    matched_agent = set()
    matches = []

    # Sort all pairs by distance
    pairs = []
    for i in range(len(agent_points)):
        for j in range(len(gt_nodules)):
            pairs.append((dist_matrix[i, j], i, j))
    pairs.sort()

    for dist, agent_idx, gt_idx in pairs:
        if agent_idx in matched_agent or gt_idx in matched_gt:
            continue
        if dist <= tolerance_mm:
            matched_agent.add(agent_idx)
            matched_gt.add(gt_idx)
            matches.append({
                'agent_idx': int(agent_idx),
                'gt_idx': int(gt_idx),
                'distance_mm': float(dist),
                'gt_diameter_mm': gt_nodules[gt_idx].get('diameter_mm', 0),
            })

    true_positives = len(matches)
    false_positives = len(agent_points) - true_positives
    missed = len(gt_nodules) - true_positives

    precision = true_positives / len(agent_points) if agent_points else 0
    recall = true_positives / len(gt_nodules) if gt_nodules else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

    return {
        'true_positives': true_positives,
        'false_positives': false_positives,
        'missed': missed,
        'precision': float(precision),
        'recall': float(recall),
        'f1': float(f1),
        'matches': matches,
    }


def verify_lung_nodule_detection(traj, env_info, task_info):
    """
    Verify lung nodule detection using detection metrics.

    Scoring (100 points total):
    - Recall: 30 points (>= 0.60 threshold)
    - Precision: 20 points (>= 0.50 threshold)
    - Diameter accuracy: 15 points (average error < 3mm)
    - Lobe accuracy: 10 points (correct lobe for matched nodules)
    - Window/level adjustment: 10 points (switched to lung window)
    - Report completeness: 15 points (JSON report with required fields)
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
    tolerance_mm = metadata.get('tolerance_mm', 15.0)

    recall_threshold = thresholds.get('recall', 0.60)
    precision_threshold = thresholds.get('precision', 0.50)

    recall_weight = weights.get('recall', 30)
    precision_weight = weights.get('precision', 20)
    diameter_weight = weights.get('diameter_accuracy', 15)
    lobe_weight = weights.get('lobe_accuracy', 10)
    window_weight = weights.get('window_level_correct', 10)
    report_weight = weights.get('report_completeness', 15)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/lidc_task_result.json", temp_result.name)
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
        logger.error(f"Failed to read result: {e}")
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
    gt_nodules = []
    try:
        copy_from_env("/tmp/ground_truth_nodules.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
            gt_nodules = gt_data.get('nodules', [])
            details['gt_nodule_count'] = len(gt_nodules)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # ============================================================
    # LOAD AGENT FIDUCIALS
    # ============================================================
    agent_points = []

    # Try .fcsv file first
    if result.get('fiducials_exist', False):
        temp_fcsv = tempfile.NamedTemporaryFile(delete=False, suffix='.fcsv')
        try:
            copy_from_env("/tmp/agent_fiducials.fcsv", temp_fcsv.name)
            agent_points = parse_fcsv(temp_fcsv.name)
            details['fiducial_source'] = 'fcsv'
        except Exception as e:
            logger.warning(f"Failed to load .fcsv: {e}")
        finally:
            if os.path.exists(temp_fcsv.name):
                os.unlink(temp_fcsv.name)

    # Try exported JSON as fallback
    if not agent_points and result.get('exported_fiducials_exist', False):
        temp_exported = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/exported_fiducials.json", temp_exported.name)
            with open(temp_exported.name, 'r') as f:
                exported = json.load(f)
                for pt in exported.get('points', []):
                    pos = pt.get('position', [0, 0, 0])
                    agent_points.append({
                        'x': pos[0], 'y': pos[1], 'z': pos[2],
                        'label': pt.get('label', ''),
                    })
            details['fiducial_source'] = 'exported_json'
        except Exception as e:
            logger.warning(f"Failed to load exported fiducials: {e}")
        finally:
            if os.path.exists(temp_exported.name):
                os.unlink(temp_exported.name)

    details['agent_fiducial_count'] = len(agent_points)

    if not agent_points:
        feedback_parts.append("No fiducial markers found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) + " | Place fiducial markers on detected nodules",
            "details": to_python_type(details)
        }

    # ============================================================
    # DETECTION MATCHING
    # ============================================================
    if gt_nodules:
        detection = match_detections(agent_points, gt_nodules, tolerance_mm)
        details['detection'] = detection

        # RECALL (30 points)
        recall = detection['recall']
        if recall >= recall_threshold:
            recall_score = recall_weight
            feedback_parts.append(f"Recall: {recall:.2f} >= {recall_threshold}")
        else:
            recall_score = int(recall_weight * (recall / recall_threshold))
            feedback_parts.append(f"Recall: {recall:.2f} < {recall_threshold}")
        score += recall_score
        details['score_recall'] = recall_score

        # PRECISION (20 points)
        precision = detection['precision']
        if precision >= precision_threshold:
            precision_score = precision_weight
            feedback_parts.append(f"Precision: {precision:.2f} >= {precision_threshold}")
        else:
            precision_score = int(precision_weight * (precision / precision_threshold))
            feedback_parts.append(f"Precision: {precision:.2f} < {precision_threshold}")
        score += precision_score
        details['score_precision'] = precision_score

        # DIAMETER ACCURACY (15 points)
        # Check agent's nodule report for diameter measurements
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        agent_report = {}
        try:
            copy_from_env("/tmp/agent_nodule_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                agent_report = json.load(f)
        except Exception:
            pass
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

        # Also try measurements from rulers
        temp_meas = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        agent_measurements = []
        try:
            copy_from_env("/tmp/agent_measurements.json", temp_meas.name)
            with open(temp_meas.name, 'r') as f:
                agent_measurements = json.load(f)
        except Exception:
            pass
        finally:
            if os.path.exists(temp_meas.name):
                os.unlink(temp_meas.name)

        diameter_errors = []
        if agent_report and 'nodules' in agent_report:
            for match in detection['matches']:
                gt_diam = match.get('gt_diameter_mm', 0)
                # Try to find corresponding diameter in agent report
                agent_nodules = agent_report.get('nodules', [])
                if match['agent_idx'] < len(agent_nodules):
                    agent_diam = agent_nodules[match['agent_idx']].get('diameter_mm', 0)
                    if agent_diam > 0 and gt_diam > 0:
                        diameter_errors.append(abs(agent_diam - gt_diam))

        if diameter_errors:
            avg_diam_error = np.mean(diameter_errors)
            details['avg_diameter_error_mm'] = float(avg_diam_error)
            if avg_diam_error <= 3.0:
                diam_score = diameter_weight
                feedback_parts.append(f"Diameter error: {avg_diam_error:.1f}mm (good)")
            elif avg_diam_error <= 5.0:
                diam_score = int(diameter_weight * 0.6)
                feedback_parts.append(f"Diameter error: {avg_diam_error:.1f}mm (fair)")
            else:
                diam_score = int(diameter_weight * 0.2)
                feedback_parts.append(f"Diameter error: {avg_diam_error:.1f}mm (poor)")
        elif agent_measurements:
            # Give partial credit if ruler measurements exist
            diam_score = int(diameter_weight * 0.3)
            feedback_parts.append("Diameter: rulers found but no report")
        else:
            diam_score = 0
            feedback_parts.append("Diameter: no measurements found")

        score += diam_score
        details['score_diameter'] = diam_score

        # LOBE ACCURACY (10 points)
        lobe_correct = 0
        lobe_total = 0
        if agent_report and 'nodules' in agent_report:
            for match in detection['matches']:
                gt_lobe = gt_nodules[match['gt_idx']].get('approximate_lobe', '')
                agent_nodules = agent_report.get('nodules', [])
                if match['agent_idx'] < len(agent_nodules):
                    agent_lobe = agent_nodules[match['agent_idx']].get('lobe', '').upper()
                    if gt_lobe and agent_lobe:
                        lobe_total += 1
                        if gt_lobe.upper() == agent_lobe:
                            lobe_correct += 1

        if lobe_total > 0:
            lobe_accuracy = lobe_correct / lobe_total
            lobe_score = int(lobe_weight * lobe_accuracy)
            feedback_parts.append(f"Lobe: {lobe_correct}/{lobe_total} correct")
        else:
            lobe_score = 0
            feedback_parts.append("Lobe: no location data")
        score += lobe_score
        details['score_lobe'] = lobe_score

    else:
        # No ground truth - give partial credit for any work done
        feedback_parts.append("Ground truth unavailable - partial credit for effort")
        score += int((recall_weight + precision_weight) * 0.3)
        details['no_ground_truth'] = True

    # ============================================================
    # WINDOW/LEVEL CHECK (10 points)
    # ============================================================
    query_vlm = env_info.get('query_vlm')
    window_adjusted = False

    if query_vlm:
        try:
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/lidc_final.png", temp_screenshot.name)

            vlm_result = query_vlm(
                prompt="""Examine this 3D Slicer screenshot showing a chest CT scan.

Check for:
1. Is the lung parenchyma (air-filled lung tissue) clearly visible as dark areas?
2. Does the display appear to use lung window settings (lungs appear dark gray/black with visible vessels)?
3. Or does it appear to use mediastinal/soft tissue window (lungs appear uniformly black)?

Respond in JSON:
{
    "lung_window_used": true/false,
    "lung_parenchyma_visible": true/false,
    "observations": "what you see"
}""",
                image=temp_screenshot.name
            )

            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_window_check'] = parsed
                window_adjusted = parsed.get('lung_window_used', False)
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
        finally:
            if os.path.exists(temp_screenshot.name):
                os.unlink(temp_screenshot.name)

    if window_adjusted:
        window_score = window_weight
        feedback_parts.append("Window: lung window applied")
    else:
        window_score = 0
        feedback_parts.append("Window: lung window NOT detected")
    score += window_score
    details['score_window'] = window_score

    # ============================================================
    # REPORT COMPLETENESS (15 points)
    # ============================================================
    if result.get('report_exists', False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_nodule_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report = json.load(f)

            # Check for required fields
            has_nodules = 'nodules' in report and len(report.get('nodules', [])) > 0
            has_count = 'total_nodules' in report or 'count' in report or len(report.get('nodules', [])) > 0

            if has_nodules:
                nodule_list = report['nodules']
                has_diameter = any('diameter' in n or 'diameter_mm' in n for n in nodule_list)
                has_lobe = any('lobe' in n or 'location' in n for n in nodule_list)

                completeness = sum([has_count, has_diameter, has_lobe]) / 3.0
                report_score = int(report_weight * completeness)

                missing = []
                if not has_diameter:
                    missing.append("diameter")
                if not has_lobe:
                    missing.append("lobe")

                if missing:
                    feedback_parts.append(f"Report: missing {', '.join(missing)}")
                else:
                    feedback_parts.append(f"Report: complete ({len(nodule_list)} nodules)")
            else:
                report_score = int(report_weight * 0.3)
                feedback_parts.append("Report: exists but no nodule list")

        except json.JSONDecodeError:
            report_score = int(report_weight * 0.2)
            feedback_parts.append("Report: invalid JSON")
        except Exception as e:
            report_score = int(report_weight * 0.1)
            feedback_parts.append(f"Report: error reading ({e})")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        report_score = 0
        feedback_parts.append("Report: NOT created")

    score += report_score
    details['score_report'] = report_score

    # ============================================================
    # FINAL SCORING
    # ============================================================
    detection_result = details.get('detection', {})
    recall = detection_result.get('recall', 0)
    precision = detection_result.get('precision', 0)

    passed = (recall >= recall_threshold and precision >= precision_threshold and score >= 50)

    if passed:
        if score >= 85:
            feedback_parts.append("Excellent nodule detection!")
        elif score >= 70:
            feedback_parts.append("Good nodule detection")
        else:
            feedback_parts.append("Acceptable nodule detection")
    else:
        feedback_parts.append("Task NOT completed - improve detection accuracy")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }
