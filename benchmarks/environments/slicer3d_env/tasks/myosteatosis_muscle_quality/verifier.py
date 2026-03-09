#!/usr/bin/env python3
"""
Verifier for myosteatosis muscle quality assessment task.

VERIFICATION STRATEGY:
1. Segmentation exists and was created during task (10 points)
2. Segmentation is at correct vertebral level - L3 ±1 (15 points)
3. Segmentation is in anatomically correct location - posterior abdomen (15 points)
4. Mean HU measurement accuracy - within 5 HU of ground truth (25 points)
5. Muscle area is reasonable - 100-250 cm² (10 points)
6. Myosteatosis classification is correct (15 points)
7. Report completeness - JSON with required fields (10 points)

Pass threshold: 60 points with mean HU accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import optional dependencies
NIBABEL_AVAILABLE = False
nib = None

try:
    import nibabel as nib
    NIBABEL_AVAILABLE = True
except ImportError:
    logger.warning("nibabel not available - will try to install")


def ensure_dependencies():
    """Ensure required packages are available."""
    global NIBABEL_AVAILABLE, nib
    if not NIBABEL_AVAILABLE:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
            import nibabel as nib_module
            nib = nib_module
            NIBABEL_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install dependencies: {e}")
            return False
    return True


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


def verify_myosteatosis(traj, env_info, task_info):
    """
    Verify myosteatosis muscle quality assessment task completion.

    Scoring (100 points total):
    - Segmentation exists: 10 points
    - Correct vertebral level (L3): 15 points
    - Anatomical location (posterior abdomen): 15 points
    - Mean HU accuracy: 25 points
    - Area reasonable: 10 points
    - Classification correct: 15 points
    - Report complete: 10 points
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
    myosteatosis_thresholds = metadata.get('myosteatosis_thresholds', {'male': 41, 'female': 33})

    mean_hu_error_max = thresholds.get('mean_hu_error_max', 5.0)
    level_tolerance = thresholds.get('level_tolerance', 1)
    area_min = thresholds.get('area_min_cm2', 100)
    area_max = thresholds.get('area_max_cm2', 250)

    w_seg_exists = weights.get('segmentation_exists', 10)
    w_level = weights.get('correct_vertebral_level', 15)
    w_location = weights.get('anatomical_location', 15)
    w_mean_hu = weights.get('mean_hu_accuracy', 25)
    w_area = weights.get('area_reasonable', 10)
    w_classification = weights.get('classification_correct', 15)
    w_report = weights.get('report_complete', 10)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/myosteatosis_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/muscle_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_mean_hu = gt_data.get('mean_hu', 0)
    gt_area_cm2 = gt_data.get('muscle_area_cm2', 0)
    gt_l3_slice = gt_data.get('l3_slice_index', 0)
    gt_classification = gt_data.get('classification', '')
    gt_myosteatosis = gt_data.get('myosteatosis_present', False)
    patient_sex = gt_data.get('patient_sex', result.get('patient_sex', 'Unknown'))
    ct_shape = gt_data.get('ct_shape', [0, 0, 0])

    details['gt_mean_hu'] = gt_mean_hu
    details['gt_area_cm2'] = gt_area_cm2
    details['gt_l3_slice'] = gt_l3_slice
    details['gt_classification'] = gt_classification
    details['patient_sex'] = patient_sex

    # Get sex-specific threshold
    sex_threshold = myosteatosis_thresholds.get(patient_sex.lower(), 41)

    # ============================================================
    # CRITERION 1: Segmentation Exists (10 points)
    # ============================================================
    seg_exists = result.get('segmentation_exists', False)
    seg_created = result.get('segmentation_created_during_task', False)
    seg_voxels = result.get('agent_voxel_count', 0)

    if seg_exists and seg_created and seg_voxels > 0:
        score += w_seg_exists
        feedback_parts.append(f"✓ Segmentation created ({seg_voxels} voxels)")
        details['seg_exists'] = True
        details['seg_voxels'] = seg_voxels
    elif seg_exists and seg_voxels > 0:
        score += int(w_seg_exists * 0.7)
        feedback_parts.append(f"△ Segmentation exists but may not be new ({seg_voxels} voxels)")
        details['seg_exists'] = True
    else:
        feedback_parts.append("✗ No valid segmentation found")
        details['seg_exists'] = False
        # Early return if no segmentation
        return {
            "passed": False,
            "score": to_python_type(score),
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }

    # ============================================================
    # CRITERION 2: Correct Vertebral Level (15 points)
    # ============================================================
    agent_z_center_str = result.get('agent_z_center', '')
    level_correct = False
    
    if agent_z_center_str:
        try:
            agent_z_center = float(agent_z_center_str)
            z_difference = abs(agent_z_center - gt_l3_slice)
            nz = ct_shape[2] if len(ct_shape) > 2 else 100
            
            # Allow tolerance of ~5% of volume height (approximately 1 vertebral level)
            level_tolerance_slices = max(5, int(nz * 0.05 * level_tolerance))
            
            details['agent_z_center'] = agent_z_center
            details['gt_l3_slice'] = gt_l3_slice
            details['z_difference'] = z_difference
            details['level_tolerance_slices'] = level_tolerance_slices
            
            if z_difference <= level_tolerance_slices:
                score += w_level
                level_correct = True
                feedback_parts.append(f"✓ Correct vertebral level (L3 ±{level_tolerance})")
            elif z_difference <= level_tolerance_slices * 2:
                score += int(w_level * 0.5)
                feedback_parts.append(f"△ Close to L3 level (z diff: {z_difference:.0f})")
            else:
                feedback_parts.append(f"✗ Wrong vertebral level (z diff: {z_difference:.0f})")
        except (ValueError, TypeError):
            feedback_parts.append("✗ Could not determine vertebral level")
    else:
        feedback_parts.append("✗ Vertebral level not determined")

    # ============================================================
    # CRITERION 3: Anatomical Location - Posterior Abdomen (15 points)
    # ============================================================
    # This is partially verified by the segmentation being in the correct z-range
    # and having reasonable characteristics
    agent_area_str = result.get('agent_measured_area_cm2', '')
    
    if agent_area_str:
        try:
            agent_area = float(agent_area_str)
            # Muscle should be in posterior abdomen - we verify indirectly via area and location
            # If area is reasonable, it's likely correctly placed
            if 50 <= agent_area <= 300:  # Broader range for location check
                score += w_location
                feedback_parts.append(f"✓ Anatomically plausible location")
                details['anatomical_location_ok'] = True
            else:
                score += int(w_location * 0.3)
                feedback_parts.append(f"△ Area suggests possible location issue ({agent_area:.1f} cm²)")
                details['anatomical_location_ok'] = False
        except (ValueError, TypeError):
            feedback_parts.append("△ Could not verify anatomical location")
    else:
        # Give partial credit if segmentation exists at correct level
        if level_correct:
            score += int(w_location * 0.5)
            feedback_parts.append("△ Location partially verified via level")

    # ============================================================
    # CRITERION 4: Mean HU Accuracy (25 points)
    # ============================================================
    agent_mean_hu_str = result.get('agent_measured_mean_hu', '')
    mean_hu_accurate = False
    
    if not agent_mean_hu_str:
        # Try from report
        agent_mean_hu_str = result.get('reported_mean_hu', '')
    
    if agent_mean_hu_str and gt_mean_hu:
        try:
            agent_mean_hu = float(agent_mean_hu_str)
            hu_error = abs(agent_mean_hu - gt_mean_hu)
            
            details['agent_mean_hu'] = agent_mean_hu
            details['gt_mean_hu'] = gt_mean_hu
            details['hu_error'] = hu_error
            
            if hu_error <= mean_hu_error_max:
                score += w_mean_hu
                mean_hu_accurate = True
                feedback_parts.append(f"✓ Mean HU accurate ({agent_mean_hu:.1f} vs {gt_mean_hu:.1f}, error: {hu_error:.1f})")
            elif hu_error <= mean_hu_error_max * 2:
                score += int(w_mean_hu * 0.6)
                feedback_parts.append(f"△ Mean HU close ({agent_mean_hu:.1f} vs {gt_mean_hu:.1f}, error: {hu_error:.1f})")
            elif hu_error <= mean_hu_error_max * 3:
                score += int(w_mean_hu * 0.3)
                feedback_parts.append(f"△ Mean HU has some error ({agent_mean_hu:.1f} vs {gt_mean_hu:.1f})")
            else:
                feedback_parts.append(f"✗ Mean HU inaccurate ({agent_mean_hu:.1f} vs {gt_mean_hu:.1f})")
        except (ValueError, TypeError):
            feedback_parts.append("✗ Could not parse mean HU value")
    else:
        feedback_parts.append("✗ Mean HU not measured")

    # ============================================================
    # CRITERION 5: Area Reasonable (10 points)
    # ============================================================
    if agent_area_str:
        try:
            agent_area = float(agent_area_str)
            details['agent_area_cm2'] = agent_area
            details['gt_area_cm2'] = gt_area_cm2
            
            if area_min <= agent_area <= area_max:
                score += w_area
                feedback_parts.append(f"✓ Muscle area reasonable ({agent_area:.1f} cm²)")
            elif area_min * 0.5 <= agent_area <= area_max * 1.5:
                score += int(w_area * 0.5)
                feedback_parts.append(f"△ Muscle area slightly out of range ({agent_area:.1f} cm²)")
            else:
                feedback_parts.append(f"✗ Muscle area unreasonable ({agent_area:.1f} cm²)")
        except (ValueError, TypeError):
            feedback_parts.append("△ Could not verify muscle area")
    else:
        feedback_parts.append("△ Muscle area not measured")

    # ============================================================
    # CRITERION 6: Classification Correct (15 points)
    # ============================================================
    reported_classification = result.get('reported_classification', '').lower()
    
    # Determine what agent's classification should be based on their measurement
    agent_classification_based_on_hu = None
    if agent_mean_hu_str:
        try:
            agent_mean_hu = float(agent_mean_hu_str)
            agent_classification_based_on_hu = "myosteatosis" if agent_mean_hu <= sex_threshold else "normal"
        except:
            pass
    
    gt_classification_lower = gt_classification.lower()
    details['gt_classification'] = gt_classification
    details['reported_classification'] = reported_classification
    details['sex_threshold'] = sex_threshold
    
    classification_correct = False
    if reported_classification:
        if reported_classification in gt_classification_lower or gt_classification_lower in reported_classification:
            score += w_classification
            classification_correct = True
            feedback_parts.append(f"✓ Classification correct ({gt_classification})")
        elif agent_classification_based_on_hu and reported_classification in agent_classification_based_on_hu:
            # Agent's classification matches their measurement even if GT differs
            score += int(w_classification * 0.7)
            feedback_parts.append(f"△ Classification consistent with measurement")
        else:
            feedback_parts.append(f"✗ Classification incorrect (got '{reported_classification}', expected '{gt_classification}')")
    else:
        # Try to infer classification from myosteatosis field in report
        if result.get('report_exists', False):
            score += int(w_classification * 0.3)
            feedback_parts.append("△ Classification not explicitly stated")
        else:
            feedback_parts.append("✗ No classification reported")

    # ============================================================
    # CRITERION 7: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        # Check for required fields
        required_fields = ['mean_hu', 'classification']
        optional_fields = ['muscle_area_cm2', 'vertebral_level', 'patient_sex', 'myosteatosis_present']
        
        has_required = (
            result.get('reported_mean_hu', '') != '' and
            result.get('reported_classification', '') != ''
        )
        
        has_optional = result.get('reported_area', '') != ''
        
        if has_required and has_optional:
            score += w_report
            feedback_parts.append("✓ Report complete with all fields")
        elif has_required:
            score += int(w_report * 0.7)
            feedback_parts.append("✓ Report has required fields")
        else:
            score += int(w_report * 0.3)
            feedback_parts.append("△ Report exists but incomplete")
    else:
        feedback_parts.append("✗ No report file created")

    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Key criteria: mean HU accuracy is the primary measure
    key_criteria_met = mean_hu_accurate and seg_exists
    passed = score >= 60 and key_criteria_met

    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    summary = f"\nScore: {score}/100"
    if passed:
        summary += " - PASSED"
    else:
        summary += " - FAILED"
        if not mean_hu_accurate:
            summary += " (Mean HU accuracy not achieved)"
        elif score < 60:
            summary += " (Score below 60)"

    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": feedback + summary,
        "details": to_python_type(details)
    }