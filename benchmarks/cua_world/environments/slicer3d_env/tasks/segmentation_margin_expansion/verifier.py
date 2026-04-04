#!/usr/bin/env python3
"""
Verifier for Segmentation Margin Expansion task.

VERIFICATION CRITERIA:
1. GTV Preserved (10 pts) - Original GTV segment exists unchanged
2. CTV Exists (10 pts) - CTV segment created with non-zero volume
3. PTV Exists (10 pts) - PTV segment created with non-zero volume
4. CTV Margin Accuracy (20 pts) - CTV volume within 15% of expected 5mm expansion
5. PTV Margin Accuracy (20 pts) - PTV volume within 15% of expected 8mm expansion
6. Proper Nesting (15 pts) - GTV ⊂ CTV ⊂ PTV verified
7. Report Completeness (10 pts) - JSON contains all required fields
8. Report Accuracy (5 pts) - Reported volumes match segmentation

Pass Threshold: 60 points with CTV and PTV existing and properly nested
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


def ensure_dependencies():
    """Ensure required packages are available."""
    try:
        import nrrd
        import nibabel
        return True
    except ImportError:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pynrrd", "nibabel", "scipy"])
            return True
        except Exception as e:
            logger.error(f"Failed to install dependencies: {e}")
            return False


def load_segmentation_nrrd(filepath):
    """
    Load a .seg.nrrd segmentation file.
    
    Returns dict with segment names mapped to binary masks.
    """
    import nrrd
    
    data, header = nrrd.read(filepath)
    
    result = {
        "data": data,
        "header": header,
        "segments": {},
        "segment_names": []
    }
    
    # Parse segment information from header
    # Slicer .seg.nrrd files have segment info in header keys like:
    # Segment0_Name, Segment0_LabelValue, etc.
    
    segment_info = {}
    for key, value in header.items():
        if key.startswith("Segment") and "_" in key:
            parts = key.split("_", 1)
            seg_idx = parts[0].replace("Segment", "")
            attr_name = parts[1]
            
            if seg_idx not in segment_info:
                segment_info[seg_idx] = {}
            segment_info[seg_idx][attr_name] = value
    
    # Extract segment masks based on label values
    for seg_idx, info in segment_info.items():
        name = info.get("Name", f"Segment{seg_idx}")
        label_value = info.get("LabelValue", int(seg_idx) + 1)
        
        try:
            label_value = int(label_value)
        except (ValueError, TypeError):
            label_value = int(seg_idx) + 1
        
        # Create binary mask for this segment
        mask = (data == label_value)
        
        result["segments"][name.lower()] = {
            "name": name,
            "label_value": label_value,
            "mask": mask,
            "voxel_count": int(np.sum(mask))
        }
        result["segment_names"].append(name.lower())
    
    # If no segment info in header, try to infer from unique values
    if not result["segments"]:
        unique_vals = np.unique(data)
        for i, val in enumerate(unique_vals):
            if val > 0:
                mask = (data == val)
                name = f"segment_{int(val)}"
                result["segments"][name] = {
                    "name": name,
                    "label_value": int(val),
                    "mask": mask,
                    "voxel_count": int(np.sum(mask))
                }
                result["segment_names"].append(name)
    
    return result


def calculate_volume_ml(mask, voxel_volume_mm3):
    """Calculate volume in mL from a binary mask."""
    voxel_count = np.sum(mask.astype(bool))
    volume_mm3 = voxel_count * voxel_volume_mm3
    return volume_mm3 / 1000.0


def check_nesting(inner_mask, outer_mask):
    """
    Check if inner_mask is completely contained within outer_mask.
    
    Returns (is_nested, overlap_fraction)
    """
    inner = inner_mask.astype(bool)
    outer = outer_mask.astype(bool)
    
    # Inner should be subset of outer
    # All voxels in inner should also be in outer
    inner_in_outer = np.sum(inner & outer)
    total_inner = np.sum(inner)
    
    if total_inner == 0:
        return True, 1.0  # Empty inner is trivially nested
    
    overlap_fraction = inner_in_outer / total_inner
    is_nested = overlap_fraction >= 0.99  # Allow tiny floating point errors
    
    return is_nested, float(overlap_fraction)


def verify_segmentation_margin_expansion(traj, env_info, task_info):
    """
    Verify margin expansion task completion.
    
    Scoring (100 points total):
    - GTV preserved: 10 points
    - CTV exists: 10 points
    - PTV exists: 10 points
    - CTV margin accuracy: 20 points
    - PTV margin accuracy: 20 points
    - Proper nesting: 15 points
    - Report completeness: 10 points
    - Report accuracy: 5 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Ensure dependencies
    if not ensure_dependencies():
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to install required dependencies"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    volume_tolerance = metadata.get('volume_tolerance_percent', 15) / 100.0
    passing_threshold = metadata.get('passing_threshold', 60)
    
    w_gtv = weights.get('gtv_preserved', 10)
    w_ctv_exists = weights.get('ctv_exists', 10)
    w_ptv_exists = weights.get('ptv_exists', 10)
    w_ctv_accuracy = weights.get('ctv_margin_accuracy', 20)
    w_ptv_accuracy = weights.get('ptv_margin_accuracy', 20)
    w_nesting = weights.get('proper_nesting', 15)
    w_report_complete = weights.get('report_completeness', 10)
    w_report_accuracy = weights.get('report_accuracy', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/margin_task_result.json", temp_result.name)
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
    
    if not result.get('segmentation_exists', False):
        feedback_parts.append("❌ No segmentation file found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Anti-gaming: check if segmentation was created during task
    if not result.get('segmentation_created_during_task', False):
        feedback_parts.append("⚠️ Segmentation may not have been modified during task")
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/margin_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    expected_gtv_vol = gt_data.get('gtv_volume_ml', 0)
    expected_ctv_vol = gt_data.get('expected_ctv_volume_ml', 0)
    expected_ptv_vol = gt_data.get('expected_ptv_volume_ml', 0)
    voxel_volume_mm3 = gt_data.get('voxel_volume_mm3', 1.0)
    
    details['expected_gtv_ml'] = expected_gtv_vol
    details['expected_ctv_ml'] = expected_ctv_vol
    details['expected_ptv_ml'] = expected_ptv_vol
    
    # Load agent's segmentation
    temp_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.seg.nrrd')
    seg_data = None
    try:
        copy_from_env("/tmp/agent_segmentation.seg.nrrd", temp_seg.name)
        seg_data = load_segmentation_nrrd(temp_seg.name)
    except Exception as e:
        logger.warning(f"Failed to load agent segmentation: {e}")
        details['seg_load_error'] = str(e)
        feedback_parts.append(f"❌ Failed to parse segmentation: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_seg.name):
            os.unlink(temp_seg.name)
    
    if seg_data is None:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    segments = seg_data.get('segments', {})
    segment_names = [s.lower() for s in seg_data.get('segment_names', [])]
    
    details['found_segments'] = segment_names
    
    # ================================================================
    # CRITERION 1: GTV Preserved (10 points)
    # ================================================================
    gtv_segment = None
    for name in ['gtv', 'gross tumor volume', 'tumor']:
        if name in segments:
            gtv_segment = segments[name]
            break
    
    if gtv_segment:
        gtv_vol = calculate_volume_ml(gtv_segment['mask'], voxel_volume_mm3)
        details['agent_gtv_ml'] = gtv_vol
        
        # Check if GTV is approximately preserved
        if expected_gtv_vol > 0:
            gtv_diff = abs(gtv_vol - expected_gtv_vol) / expected_gtv_vol
            if gtv_diff <= 0.1:  # Within 10%
                score += w_gtv
                feedback_parts.append(f"✅ GTV preserved ({gtv_vol:.1f} mL)")
            else:
                score += w_gtv * 0.5
                feedback_parts.append(f"⚠️ GTV changed ({gtv_vol:.1f} vs {expected_gtv_vol:.1f} mL)")
        else:
            score += w_gtv
            feedback_parts.append(f"✅ GTV found ({gtv_vol:.1f} mL)")
    else:
        feedback_parts.append("❌ GTV segment not found")
        details['gtv_missing'] = True
    
    # ================================================================
    # CRITERION 2: CTV Exists (10 points)
    # ================================================================
    ctv_segment = None
    for name in ['ctv', 'clinical target volume', 'ctv_5mm']:
        if name in segments:
            ctv_segment = segments[name]
            break
    
    if ctv_segment and ctv_segment['voxel_count'] > 0:
        ctv_vol = calculate_volume_ml(ctv_segment['mask'], voxel_volume_mm3)
        details['agent_ctv_ml'] = ctv_vol
        score += w_ctv_exists
        feedback_parts.append(f"✅ CTV created ({ctv_vol:.1f} mL)")
    else:
        feedback_parts.append("❌ CTV segment not found or empty")
        details['ctv_missing'] = True
    
    # ================================================================
    # CRITERION 3: PTV Exists (10 points)
    # ================================================================
    ptv_segment = None
    for name in ['ptv', 'planning target volume', 'ptv_8mm']:
        if name in segments:
            ptv_segment = segments[name]
            break
    
    if ptv_segment and ptv_segment['voxel_count'] > 0:
        ptv_vol = calculate_volume_ml(ptv_segment['mask'], voxel_volume_mm3)
        details['agent_ptv_ml'] = ptv_vol
        score += w_ptv_exists
        feedback_parts.append(f"✅ PTV created ({ptv_vol:.1f} mL)")
    else:
        feedback_parts.append("❌ PTV segment not found or empty")
        details['ptv_missing'] = True
    
    # ================================================================
    # CRITERION 4: CTV Margin Accuracy (20 points)
    # ================================================================
    if ctv_segment and expected_ctv_vol > 0:
        ctv_vol = details.get('agent_ctv_ml', 0)
        ctv_error = abs(ctv_vol - expected_ctv_vol) / expected_ctv_vol
        details['ctv_error_percent'] = ctv_error * 100
        
        if ctv_error <= volume_tolerance:
            score += w_ctv_accuracy
            feedback_parts.append(f"✅ CTV margin accurate ({ctv_error*100:.1f}% error)")
        elif ctv_error <= volume_tolerance * 2:
            score += w_ctv_accuracy * 0.5
            feedback_parts.append(f"⚠️ CTV margin approximate ({ctv_error*100:.1f}% error)")
        else:
            feedback_parts.append(f"❌ CTV margin inaccurate ({ctv_error*100:.1f}% error)")
    
    # ================================================================
    # CRITERION 5: PTV Margin Accuracy (20 points)
    # ================================================================
    if ptv_segment and expected_ptv_vol > 0:
        ptv_vol = details.get('agent_ptv_ml', 0)
        ptv_error = abs(ptv_vol - expected_ptv_vol) / expected_ptv_vol
        details['ptv_error_percent'] = ptv_error * 100
        
        if ptv_error <= volume_tolerance:
            score += w_ptv_accuracy
            feedback_parts.append(f"✅ PTV margin accurate ({ptv_error*100:.1f}% error)")
        elif ptv_error <= volume_tolerance * 2:
            score += w_ptv_accuracy * 0.5
            feedback_parts.append(f"⚠️ PTV margin approximate ({ptv_error*100:.1f}% error)")
        else:
            feedback_parts.append(f"❌ PTV margin inaccurate ({ptv_error*100:.1f}% error)")
    
    # ================================================================
    # CRITERION 6: Proper Nesting (15 points)
    # ================================================================
    nesting_score = 0
    if gtv_segment and ctv_segment and ptv_segment:
        # Check GTV ⊂ CTV
        gtv_in_ctv, gtv_ctv_overlap = check_nesting(gtv_segment['mask'], ctv_segment['mask'])
        details['gtv_in_ctv_overlap'] = gtv_ctv_overlap
        
        # Check CTV ⊂ PTV
        ctv_in_ptv, ctv_ptv_overlap = check_nesting(ctv_segment['mask'], ptv_segment['mask'])
        details['ctv_in_ptv_overlap'] = ctv_ptv_overlap
        
        if gtv_in_ctv and ctv_in_ptv:
            nesting_score = w_nesting
            feedback_parts.append("✅ Proper nesting: GTV ⊂ CTV ⊂ PTV")
        elif gtv_in_ctv:
            nesting_score = w_nesting * 0.5
            feedback_parts.append(f"⚠️ GTV ⊂ CTV OK, but CTV ⊄ PTV ({ctv_ptv_overlap*100:.1f}%)")
        elif ctv_in_ptv:
            nesting_score = w_nesting * 0.5
            feedback_parts.append(f"⚠️ CTV ⊂ PTV OK, but GTV ⊄ CTV ({gtv_ctv_overlap*100:.1f}%)")
        else:
            feedback_parts.append("❌ Improper nesting - volumes not properly contained")
        
        score += nesting_score
        details['nesting_verified'] = (gtv_in_ctv and ctv_in_ptv)
    else:
        feedback_parts.append("❌ Cannot verify nesting - missing segments")
        details['nesting_verified'] = False
    
    # ================================================================
    # CRITERION 7: Report Completeness (10 points)
    # ================================================================
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    report_data = {}
    try:
        copy_from_env("/tmp/agent_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    required_fields = ['gtv_volume_ml', 'ctv_volume_ml', 'ptv_volume_ml', 'ctv_margin_mm', 'ptv_margin_mm']
    fields_present = sum(1 for f in required_fields if f in report_data)
    
    if fields_present == len(required_fields):
        score += w_report_complete
        feedback_parts.append("✅ Report complete")
    elif fields_present >= 3:
        score += w_report_complete * 0.5
        feedback_parts.append(f"⚠️ Report partial ({fields_present}/{len(required_fields)} fields)")
    else:
        feedback_parts.append("❌ Report incomplete or missing")
    
    details['report_fields_present'] = fields_present
    details['report_data'] = report_data
    
    # ================================================================
    # CRITERION 8: Report Accuracy (5 points)
    # ================================================================
    if report_data and ctv_segment and ptv_segment:
        try:
            reported_ctv = float(report_data.get('ctv_volume_ml', 0))
            reported_ptv = float(report_data.get('ptv_volume_ml', 0))
            actual_ctv = details.get('agent_ctv_ml', 0)
            actual_ptv = details.get('agent_ptv_ml', 0)
            
            ctv_report_error = abs(reported_ctv - actual_ctv) / actual_ctv if actual_ctv > 0 else 1.0
            ptv_report_error = abs(reported_ptv - actual_ptv) / actual_ptv if actual_ptv > 0 else 1.0
            
            if ctv_report_error <= 0.05 and ptv_report_error <= 0.05:
                score += w_report_accuracy
                feedback_parts.append("✅ Reported volumes accurate")
            elif ctv_report_error <= 0.1 and ptv_report_error <= 0.1:
                score += w_report_accuracy * 0.5
                feedback_parts.append("⚠️ Reported volumes approximately correct")
        except (ValueError, TypeError, ZeroDivisionError):
            pass
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    key_criteria_met = (
        ctv_segment is not None and 
        ptv_segment is not None and 
        details.get('nesting_verified', False)
    )
    
    passed = score >= passing_threshold and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    if passed:
        feedback = f"✅ PASSED ({score}/100) | " + feedback
    else:
        if not key_criteria_met:
            feedback = f"❌ FAILED - Key criteria not met ({score}/100) | " + feedback
        else:
            feedback = f"❌ FAILED - Score below threshold ({score}/100) | " + feedback
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": feedback,
        "details": to_python_type(details)
    }