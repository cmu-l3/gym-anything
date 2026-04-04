#!/usr/bin/env python3
"""
Verifier for pericardial effusion quantification task.

VERIFICATION METRICS:
1. Measurement exists (10 points) - ruler markup file present
2. Thickness accuracy (25 points) - within 3mm of ground truth
3. Measurement location valid (10 points) - ruler placed in pericardial region
4. Segmentation exists (10 points) - segmentation file present
5. Segmentation Dice (15 points) - overlap with ground truth >= 0.4
6. Volume accuracy (10 points) - within 30% of ground truth
7. Severity classification (10 points) - correct Small/Moderate/Large
8. Distribution pattern (5 points) - correct circumferential/loculated
9. Report completeness (5 points) - JSON with all required fields

Pass threshold: 60 points with Thickness Accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import nibabel
nib = None
NIBABEL_AVAILABLE = False

try:
    import nibabel as nib
    NIBABEL_AVAILABLE = True
except ImportError:
    pass


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
            logger.warning(f"Failed to install nibabel: {e}")
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


def dice_coefficient(pred: np.ndarray, gt: np.ndarray) -> float:
    """Calculate Dice coefficient between prediction and ground truth."""
    pred = pred.astype(bool)
    gt = gt.astype(bool)
    
    intersection = np.sum(pred & gt)
    sum_volumes = np.sum(pred) + np.sum(gt)
    
    if sum_volumes == 0:
        return 1.0 if np.sum(pred) == 0 and np.sum(gt) == 0 else 0.0
    
    return float(2.0 * intersection / sum_volumes)


def verify_pericardial_effusion(traj, env_info, task_info):
    """
    Verify pericardial effusion quantification task completion.
    
    Scoring (100 points total):
    - Measurement exists: 10 points
    - Thickness accuracy: 25 points (within 3mm)
    - Measurement location valid: 10 points
    - Segmentation exists: 10 points
    - Segmentation Dice: 15 points (>= 0.4)
    - Volume accuracy: 10 points (within 30%)
    - Severity classification: 10 points
    - Distribution pattern: 5 points
    - Report completeness: 5 points
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
    
    thickness_error_max = thresholds.get('thickness_error_max_mm', 3.0)
    volume_error_max_pct = thresholds.get('volume_error_max_percent', 30)
    min_dice = thresholds.get('min_dice_coefficient', 0.4)
    
    w_meas_exists = weights.get('measurement_exists', 10)
    w_thickness = weights.get('thickness_accuracy', 25)
    w_location = weights.get('measurement_location_valid', 10)
    w_seg_exists = weights.get('segmentation_exists', 10)
    w_dice = weights.get('segmentation_dice', 15)
    w_volume = weights.get('volume_accuracy', 10)
    w_severity = weights.get('severity_classification', 10)
    w_distribution = weights.get('distribution_pattern', 5)
    w_report = weights.get('report_completeness', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/pericardial_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/pericardial_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_thickness = gt_data.get('max_thickness_mm', 0)
    gt_location = gt_data.get('max_thickness_location', '')
    gt_volume = gt_data.get('effusion_volume_ml', 0)
    gt_severity = gt_data.get('severity_classification', '')
    gt_distribution = gt_data.get('distribution_pattern', '')
    
    details['gt_thickness_mm'] = gt_thickness
    details['gt_location'] = gt_location
    details['gt_volume_ml'] = gt_volume
    details['gt_severity'] = gt_severity
    details['gt_distribution'] = gt_distribution
    
    # ============================================================
    # CRITERION 1: Measurement Exists (10 points)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    measurement_created = result.get('measurement_created_during_task', False)
    
    if measurement_exists and measurement_created:
        score += w_meas_exists
        feedback_parts.append(f"✓ Measurement file created during task (+{w_meas_exists})")
    elif measurement_exists:
        score += w_meas_exists // 2
        feedback_parts.append(f"△ Measurement exists but may predate task (+{w_meas_exists // 2})")
    else:
        feedback_parts.append("✗ No measurement file found")
    
    details['measurement_exists'] = measurement_exists
    details['measurement_created'] = measurement_created
    
    # ============================================================
    # CRITERION 2: Thickness Accuracy (25 points)
    # ============================================================
    agent_thickness = 0.0
    thickness_accurate = False
    
    # Try measured thickness first
    measured_str = result.get('measured_thickness_mm', '')
    if measured_str:
        try:
            agent_thickness = float(measured_str)
        except (ValueError, TypeError):
            pass
    
    # Fall back to reported thickness
    if agent_thickness == 0:
        reported_str = result.get('reported_thickness_mm', '')
        if reported_str:
            try:
                agent_thickness = float(reported_str)
            except (ValueError, TypeError):
                pass
    
    if agent_thickness > 0 and gt_thickness > 0:
        thickness_error = abs(agent_thickness - gt_thickness)
        details['agent_thickness_mm'] = agent_thickness
        details['thickness_error_mm'] = thickness_error
        
        if thickness_error <= thickness_error_max:
            score += w_thickness
            thickness_accurate = True
            feedback_parts.append(f"✓ Thickness accurate: {agent_thickness:.1f}mm (error: {thickness_error:.1f}mm) (+{w_thickness})")
        elif thickness_error <= thickness_error_max * 2:
            partial = w_thickness // 2
            score += partial
            feedback_parts.append(f"△ Thickness partially accurate: {agent_thickness:.1f}mm (error: {thickness_error:.1f}mm) (+{partial})")
        else:
            feedback_parts.append(f"✗ Thickness inaccurate: {agent_thickness:.1f}mm vs GT {gt_thickness:.1f}mm (error: {thickness_error:.1f}mm)")
    else:
        feedback_parts.append("✗ No thickness measurement found")
    
    # ============================================================
    # CRITERION 3: Measurement Location Valid (10 points)
    # ============================================================
    # Check if agent's measurement is near the pericardial region
    # This would require loading the markup and checking coordinates
    # For now, award points if measurement exists and thickness is reasonable
    if measurement_exists and agent_thickness > 5 and agent_thickness < 50:
        score += w_location
        feedback_parts.append(f"✓ Measurement location appears valid (+{w_location})")
        details['location_valid'] = True
    elif measurement_exists:
        score += w_location // 2
        feedback_parts.append(f"△ Measurement exists, location uncertain (+{w_location // 2})")
        details['location_valid'] = "uncertain"
    else:
        feedback_parts.append("✗ Cannot verify measurement location")
        details['location_valid'] = False
    
    # ============================================================
    # CRITERION 4: Segmentation Exists (10 points)
    # ============================================================
    seg_exists = result.get('segmentation_exists', False)
    seg_created = result.get('segmentation_created_during_task', False)
    seg_size = result.get('segmentation_size_bytes', 0)
    
    if seg_exists and seg_created and seg_size > 1000:
        score += w_seg_exists
        feedback_parts.append(f"✓ Segmentation created during task (+{w_seg_exists})")
    elif seg_exists and seg_size > 1000:
        score += w_seg_exists // 2
        feedback_parts.append(f"△ Segmentation exists but may predate task (+{w_seg_exists // 2})")
    else:
        feedback_parts.append("✗ No valid segmentation file found")
    
    details['segmentation_exists'] = seg_exists
    details['segmentation_size'] = seg_size
    
    # ============================================================
    # CRITERION 5: Segmentation Dice (15 points)
    # ============================================================
    dice_score = 0.0
    
    if seg_exists and NIBABEL_AVAILABLE or ensure_dependencies():
        # Load agent segmentation
        temp_agent_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        temp_gt_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        
        try:
            copy_from_env("/tmp/agent_pericardial_seg.nii.gz", temp_agent_seg.name)
            copy_from_env("/tmp/pericardial_gt_seg.nii.gz", temp_gt_seg.name)
            
            import nibabel as nib
            agent_nii = nib.load(temp_agent_seg.name)
            gt_nii = nib.load(temp_gt_seg.name)
            
            agent_data = agent_nii.get_fdata()
            gt_data_seg = gt_nii.get_fdata()
            
            # Binary masks
            agent_mask = (agent_data > 0)
            gt_mask = (gt_data_seg > 0)
            
            dice_score = dice_coefficient(agent_mask, gt_mask)
            details['dice_coefficient'] = float(dice_score)
            
            if dice_score >= min_dice:
                score += w_dice
                feedback_parts.append(f"✓ Segmentation Dice: {dice_score:.3f} (+{w_dice})")
            elif dice_score >= min_dice / 2:
                partial = w_dice // 2
                score += partial
                feedback_parts.append(f"△ Segmentation Dice: {dice_score:.3f} (below threshold) (+{partial})")
            else:
                feedback_parts.append(f"✗ Segmentation Dice too low: {dice_score:.3f}")
                
        except Exception as e:
            logger.warning(f"Failed to compute Dice: {e}")
            feedback_parts.append(f"△ Could not verify segmentation overlap")
            details['dice_error'] = str(e)
        finally:
            for f in [temp_agent_seg.name, temp_gt_seg.name]:
                if os.path.exists(f):
                    os.unlink(f)
    else:
        feedback_parts.append("△ Segmentation verification skipped (no nibabel)")
    
    # ============================================================
    # CRITERION 6: Volume Accuracy (10 points)
    # ============================================================
    agent_volume = 0.0
    volume_str = result.get('reported_volume_ml', '')
    if volume_str:
        try:
            agent_volume = float(volume_str)
        except (ValueError, TypeError):
            pass
    
    if agent_volume > 0 and gt_volume > 0:
        volume_error_pct = abs(agent_volume - gt_volume) / gt_volume * 100
        details['agent_volume_ml'] = agent_volume
        details['volume_error_percent'] = volume_error_pct
        
        if volume_error_pct <= volume_error_max_pct:
            score += w_volume
            feedback_parts.append(f"✓ Volume accurate: {agent_volume:.1f}mL (error: {volume_error_pct:.1f}%) (+{w_volume})")
        elif volume_error_pct <= volume_error_max_pct * 2:
            partial = w_volume // 2
            score += partial
            feedback_parts.append(f"△ Volume partially accurate: {agent_volume:.1f}mL (+{partial})")
        else:
            feedback_parts.append(f"✗ Volume inaccurate: {agent_volume:.1f}mL vs GT {gt_volume:.1f}mL")
    else:
        feedback_parts.append("✗ No volume measurement found")
    
    # ============================================================
    # CRITERION 7: Severity Classification (10 points)
    # ============================================================
    agent_severity = result.get('reported_severity', '').strip()
    
    if agent_severity and gt_severity:
        # Normalize for comparison
        agent_sev_norm = agent_severity.lower().strip()
        gt_sev_norm = gt_severity.lower().strip()
        
        details['agent_severity'] = agent_severity
        
        if agent_sev_norm == gt_sev_norm:
            score += w_severity
            feedback_parts.append(f"✓ Severity correct: {agent_severity} (+{w_severity})")
        else:
            # Check for adjacent categories (partial credit)
            severity_order = ['small', 'moderate', 'large']
            try:
                agent_idx = severity_order.index(agent_sev_norm)
                gt_idx = severity_order.index(gt_sev_norm)
                if abs(agent_idx - gt_idx) == 1:
                    partial = w_severity // 2
                    score += partial
                    feedback_parts.append(f"△ Severity adjacent: {agent_severity} vs {gt_severity} (+{partial})")
                else:
                    feedback_parts.append(f"✗ Severity incorrect: {agent_severity} vs {gt_severity}")
            except ValueError:
                feedback_parts.append(f"✗ Invalid severity value: {agent_severity}")
    else:
        feedback_parts.append("✗ No severity classification found")
    
    # ============================================================
    # CRITERION 8: Distribution Pattern (5 points)
    # ============================================================
    agent_distribution = result.get('reported_distribution', '').strip().lower()
    
    if agent_distribution and gt_distribution:
        details['agent_distribution'] = agent_distribution
        
        if agent_distribution == gt_distribution.lower():
            score += w_distribution
            feedback_parts.append(f"✓ Distribution correct: {agent_distribution} (+{w_distribution})")
        else:
            feedback_parts.append(f"✗ Distribution incorrect: {agent_distribution} vs {gt_distribution}")
    else:
        feedback_parts.append("△ No distribution pattern reported")
    
    # ============================================================
    # CRITERION 9: Report Completeness (5 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    if report_exists and report_created:
        # Check if report has all required fields
        required_fields = ['reported_thickness_mm', 'reported_volume_ml', 'reported_severity', 'reported_location']
        fields_present = sum(1 for f in required_fields if result.get(f))
        
        if fields_present >= 3:
            score += w_report
            feedback_parts.append(f"✓ Report complete ({fields_present}/4 fields) (+{w_report})")
        else:
            partial = w_report // 2
            score += partial
            feedback_parts.append(f"△ Report incomplete ({fields_present}/4 fields) (+{partial})")
        
        details['report_fields_present'] = fields_present
    else:
        feedback_parts.append("✗ No report file found")
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Pass requires: score >= 60 AND thickness accuracy achieved
    passed = score >= 60 and thickness_accurate
    
    # Add summary
    feedback_parts.insert(0, f"Score: {score}/100")
    if passed:
        feedback_parts.insert(1, "PASSED ✓")
    else:
        if not thickness_accurate:
            feedback_parts.insert(1, "FAILED - Thickness accuracy not achieved")
        else:
            feedback_parts.insert(1, "FAILED - Score below 60")
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }