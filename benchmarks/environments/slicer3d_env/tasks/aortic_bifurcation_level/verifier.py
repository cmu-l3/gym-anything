#!/usr/bin/env python3
"""
Verifier for Aortic Bifurcation Level Identification task.

VERIFICATION METRICS:
1. Bifurcation Localization (30 points) - Is the marker within 20mm of actual bifurcation?
2. Vertebral Level Exact (25 points) - Exact match to ground truth
3. Vertebral Level Adjacent (15 points) - Within ±1 level (alternative to exact)
4. Terminal Diameter (15 points) - Aortic diameter within 5mm
5. Fiducial Saved (10 points) - Valid marker file exists
6. Report Complete (10 points) - JSON with required fields
7. Clinical Comment (5 points bonus) - Meaningful anatomical observation

Pass Threshold: 55 points with Bifurcation Localization achieved
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


def euclidean_distance(p1, p2):
    """Calculate Euclidean distance between two 3D points."""
    if len(p1) != 3 or len(p2) != 3:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))


def parse_slicer_markup_coordinates(marker_data):
    """
    Extract coordinates from Slicer markup JSON format.
    
    Returns:
        list: [x, y, z] coordinates or None if not found
    """
    try:
        # Slicer 5.x markup format
        if 'markups' in marker_data:
            for markup in marker_data['markups']:
                if 'controlPoints' in markup:
                    for cp in markup['controlPoints']:
                        if 'position' in cp:
                            return cp['position']
        
        # Alternative formats
        if 'controlPoints' in marker_data:
            for cp in marker_data['controlPoints']:
                if 'position' in cp:
                    return cp['position']
        
        # Direct position
        if 'position' in marker_data:
            return marker_data['position']
            
    except Exception as e:
        logger.warning(f"Error parsing markup: {e}")
    
    return None


def verify_aortic_bifurcation_level(traj, env_info, task_info):
    """
    Verify aortic bifurcation level identification task completion.

    Scoring (100 points total + 5 bonus):
    - Bifurcation localized: 30 points (within 20mm)
    - Vertebral level exact: 25 points
    - Vertebral level adjacent: 15 points (alternative)
    - Terminal diameter: 15 points (within 5mm)
    - Fiducial saved: 10 points
    - Report complete: 10 points
    - Clinical comment: 5 points (bonus)
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
    vertebral_order = metadata.get('vertebral_order', ['T12', 'L1', 'L2', 'L3', 'L4', 'L5', 'S1'])

    bifurcation_dist_max = thresholds.get('bifurcation_distance_max_mm', 20.0)
    diameter_error_max = thresholds.get('diameter_error_max_mm', 5.0)

    w_bifurcation = weights.get('bifurcation_localized', 30)
    w_level_exact = weights.get('vertebral_level_exact', 25)
    w_level_adjacent = weights.get('vertebral_level_adjacent', 15)
    w_diameter = weights.get('terminal_diameter', 15)
    w_fiducial = weights.get('fiducial_saved', 10)
    w_report = weights.get('report_complete', 10)
    w_comment = weights.get('clinical_comment_bonus', 5)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/bifurcation_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/bifurcation_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_coords = gt_data.get('bifurcation_coords_ras', [0, 0, 0])
    gt_level = gt_data.get('vertebral_level', 'L4').upper()
    gt_diameter = gt_data.get('terminal_diameter_mm', 0)

    details['gt_coords'] = gt_coords
    details['gt_vertebral_level'] = gt_level
    details['gt_diameter_mm'] = gt_diameter

    # ============================================================
    # CRITERION 1: FIDUCIAL MARKER SAVED (10 points)
    # ============================================================
    marker_exists = result.get('marker_exists', False)
    marker_created_during_task = result.get('marker_created_during_task', False)
    
    if marker_exists:
        if marker_created_during_task:
            score += w_fiducial
            feedback_parts.append(f"✓ Fiducial marker saved (+{w_fiducial})")
        else:
            score += w_fiducial // 2
            feedback_parts.append(f"⚠ Marker exists but may not be from this task (+{w_fiducial // 2})")
    else:
        feedback_parts.append("✗ No fiducial marker file found")
    
    details['marker_exists'] = marker_exists
    details['marker_created_during_task'] = marker_created_during_task

    # ============================================================
    # CRITERION 2: BIFURCATION LOCALIZATION (30 points)
    # ============================================================
    bifurcation_localized = False
    bifurcation_distance = float('inf')
    agent_coords = None

    # Try to load marker coordinates
    if marker_exists:
        temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_marker.mrk.json", temp_marker.name)
            with open(temp_marker.name, 'r') as f:
                marker_data = json.load(f)
            agent_coords = parse_slicer_markup_coordinates(marker_data)
        except Exception as e:
            logger.warning(f"Failed to load marker file: {e}")
            # Try from result coords string
            coords_str = result.get('marker_coords', '')
            if coords_str:
                try:
                    agent_coords = [float(x) for x in coords_str.split(',')]
                except:
                    pass
        finally:
            if os.path.exists(temp_marker.name):
                os.unlink(temp_marker.name)

    if agent_coords and len(agent_coords) == 3 and gt_coords:
        bifurcation_distance = euclidean_distance(agent_coords, gt_coords)
        details['agent_coords'] = agent_coords
        details['bifurcation_distance_mm'] = bifurcation_distance

        if bifurcation_distance <= bifurcation_dist_max:
            bifurcation_localized = True
            score += w_bifurcation
            feedback_parts.append(f"✓ Bifurcation correctly localized (distance: {bifurcation_distance:.1f}mm) (+{w_bifurcation})")
        else:
            feedback_parts.append(f"✗ Bifurcation location inaccurate (distance: {bifurcation_distance:.1f}mm > {bifurcation_dist_max}mm)")
    else:
        feedback_parts.append("✗ Could not extract coordinates from marker")
        details['coord_extraction_failed'] = True

    # ============================================================
    # CRITERION 3: REPORT COMPLETENESS (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created_during_task = result.get('report_created_during_task', False)
    
    if report_exists:
        # Try to load and validate report
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        report_data = {}
        try:
            copy_from_env("/tmp/agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_data = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

        required_fields = ['vertebral_level', 'coordinates', 'terminal_diameter_mm']
        found_fields = sum(1 for f in required_fields if f in report_data or 
                          f.replace('_mm', '') in report_data or
                          f.replace('terminal_', '') in report_data)
        
        if found_fields >= 2:
            if report_created_during_task:
                score += w_report
                feedback_parts.append(f"✓ Report complete with {found_fields}/3 required fields (+{w_report})")
            else:
                score += w_report // 2
                feedback_parts.append(f"⚠ Report exists but may not be from this task (+{w_report // 2})")
        else:
            feedback_parts.append(f"⚠ Report incomplete ({found_fields}/3 fields)")
    else:
        feedback_parts.append("✗ No report file found")

    details['report_exists'] = report_exists

    # ============================================================
    # CRITERION 4: VERTEBRAL LEVEL (25 exact / 15 adjacent)
    # ============================================================
    reported_level = result.get('reported_vertebral_level', '').upper().strip()
    details['reported_vertebral_level'] = reported_level
    
    level_scored = False
    if reported_level and gt_level:
        if reported_level == gt_level:
            score += w_level_exact
            feedback_parts.append(f"✓ Vertebral level exact match: {reported_level} (+{w_level_exact})")
            level_scored = True
        elif reported_level in vertebral_order and gt_level in vertebral_order:
            agent_idx = vertebral_order.index(reported_level)
            gt_idx = vertebral_order.index(gt_level)
            if abs(agent_idx - gt_idx) == 1:
                score += w_level_adjacent
                feedback_parts.append(f"⚠ Vertebral level adjacent: {reported_level} vs {gt_level} (+{w_level_adjacent})")
                level_scored = True
            else:
                feedback_parts.append(f"✗ Vertebral level incorrect: {reported_level} vs {gt_level}")
        else:
            feedback_parts.append(f"✗ Vertebral level not recognized: {reported_level}")
    else:
        feedback_parts.append("✗ No vertebral level reported")

    # ============================================================
    # CRITERION 5: TERMINAL DIAMETER MEASUREMENT (15 points)
    # ============================================================
    reported_diameter_str = result.get('reported_diameter_mm', '')
    details['reported_diameter_str'] = reported_diameter_str
    
    if reported_diameter_str and gt_diameter > 0:
        try:
            reported_diameter = float(reported_diameter_str)
            diameter_error = abs(reported_diameter - gt_diameter)
            details['reported_diameter_mm'] = reported_diameter
            details['diameter_error_mm'] = diameter_error
            
            if diameter_error <= diameter_error_max:
                score += w_diameter
                feedback_parts.append(f"✓ Diameter accurate: {reported_diameter:.1f}mm vs {gt_diameter:.1f}mm (+{w_diameter})")
            else:
                feedback_parts.append(f"✗ Diameter inaccurate: {reported_diameter:.1f}mm vs {gt_diameter:.1f}mm (error: {diameter_error:.1f}mm)")
        except ValueError:
            feedback_parts.append(f"✗ Could not parse diameter: {reported_diameter_str}")
    else:
        feedback_parts.append("✗ No terminal diameter reported")

    # ============================================================
    # CRITERION 6: CLINICAL COMMENT BONUS (5 points)
    # ============================================================
    has_comment = result.get('has_clinical_comment', False)
    if has_comment:
        score += w_comment
        feedback_parts.append(f"★ Clinical comment provided (+{w_comment} bonus)")
    
    details['has_clinical_comment'] = has_comment

    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Pass requires 55 points AND bifurcation localization
    passed = score >= 55 and bifurcation_localized

    details['total_score'] = score
    details['bifurcation_localized'] = bifurcation_localized
    details['passed'] = passed

    # Convert any numpy types to Python natives
    details = to_python_type(details)

    return {
        "passed": passed,
        "score": min(score, 100),  # Cap at 100 even with bonus
        "feedback": " | ".join(feedback_parts),
        "details": details
    }