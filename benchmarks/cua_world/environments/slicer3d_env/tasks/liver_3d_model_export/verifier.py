#!/usr/bin/env python3
"""
Verifier for Liver 3D Model Export task.

VERIFICATION METRICS:
1. Liver STL exists and valid (10 points)
2. Tumor STL exists and valid (10 points) - if tumors in ground truth
3. Liver mesh watertight (10 points) - printability check
4. Tumor mesh watertight (10 points) - if applicable
5. Liver volume accuracy (15 points) - within 30% of ground truth
6. Tumor volume accuracy (15 points) - within 50% of ground truth
7. Triangle count reasonable (5 points) - between 1K-500K
8. Smoothing applied (5 points) - indicated in report
9. Report complete (10 points) - all required fields
10. Report volume match (5 points) - reported matches actual
11. Tumor count correct (5 points) - matches ground truth

Total: 100 points
Pass threshold: 60 points with both STL files existing and valid
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_liver_3d_model_export(traj, env_info, task_info):
    """
    Verify liver 3D model export task completion.
    
    Uses copy_from_env to retrieve exported result data from container.
    Multi-criteria scoring with anti-gaming timestamp checks.
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
    
    liver_vol_error_max = thresholds.get('liver_volume_error_max_pct', 30) / 100.0
    tumor_vol_error_max = thresholds.get('tumor_volume_error_max_pct', 50) / 100.0
    min_triangles = thresholds.get('min_triangles', 1000)
    max_triangles = thresholds.get('max_triangles', 500000)
    
    # Scoring weights
    w_liver_exists = weights.get('liver_stl_exists', 10)
    w_tumor_exists = weights.get('tumor_stl_exists', 10)
    w_liver_watertight = weights.get('liver_watertight', 10)
    w_tumor_watertight = weights.get('tumor_watertight', 10)
    w_liver_vol = weights.get('liver_volume_accuracy', 15)
    w_tumor_vol = weights.get('tumor_volume_accuracy', 15)
    w_triangles = weights.get('triangle_count', 5)
    w_smoothing = weights.get('smoothing_applied', 5)
    w_report = weights.get('report_complete', 10)
    w_report_match = weights.get('report_volume_match', 5)
    w_tumor_count = weights.get('tumor_count_correct', 5)
    
    # Copy result JSON from container
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/liver_task_result.json", temp_result.name)
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
        feedback_parts.append("⚠ Slicer was not running at export time")
    
    # Get ground truth values
    gt_liver_vol = float(result.get('gt_liver_volume_ml', 0))
    gt_tumor_vol = float(result.get('gt_tumor_volume_ml', 0))
    gt_tumor_count = int(result.get('gt_tumor_count', 0))
    
    details['gt_liver_volume_ml'] = gt_liver_vol
    details['gt_tumor_volume_ml'] = gt_tumor_vol
    details['gt_tumor_count'] = gt_tumor_count
    
    # ============================================================
    # CRITERION 1: Liver STL Exists (10 points)
    # ============================================================
    liver_exists = result.get('liver_stl_exists', False)
    liver_size = result.get('liver_stl_size_bytes', 0)
    liver_created = result.get('liver_created_during_task', False)
    
    if liver_exists and liver_size > 10000:  # At least 10KB
        if liver_created:
            score += w_liver_exists
            details['liver_stl_exists'] = {"points": w_liver_exists, "status": "PASS"}
            feedback_parts.append(f"✓ Liver STL exists ({liver_size/1024:.1f}KB)")
        else:
            score += w_liver_exists // 2
            details['liver_stl_exists'] = {"points": w_liver_exists // 2, "status": "PARTIAL"}
            feedback_parts.append(f"⚠ Liver STL exists but may be pre-existing")
    else:
        details['liver_stl_exists'] = {"points": 0, "status": "FAIL"}
        feedback_parts.append("✗ Liver STL not found or too small")
    
    # ============================================================
    # CRITERION 2: Tumor STL Exists (10 points)
    # ============================================================
    tumor_exists = result.get('tumor_stl_exists', False)
    tumor_size = result.get('tumor_stl_size_bytes', 0)
    tumor_created = result.get('tumor_created_during_task', False)
    
    if gt_tumor_count > 0:
        # Tumors expected in ground truth
        if tumor_exists and tumor_size > 500:
            if tumor_created:
                score += w_tumor_exists
                details['tumor_stl_exists'] = {"points": w_tumor_exists, "status": "PASS"}
                feedback_parts.append(f"✓ Tumor STL exists ({tumor_size/1024:.1f}KB)")
            else:
                score += w_tumor_exists // 2
                details['tumor_stl_exists'] = {"points": w_tumor_exists // 2, "status": "PARTIAL"}
                feedback_parts.append(f"⚠ Tumor STL exists but may be pre-existing")
        else:
            details['tumor_stl_exists'] = {"points": 0, "status": "FAIL"}
            feedback_parts.append("✗ Tumor STL not found (tumors present in case)")
    else:
        # No tumors in ground truth
        if not tumor_exists or tumor_size < 100:
            score += w_tumor_exists
            details['tumor_stl_exists'] = {"points": w_tumor_exists, "status": "PASS"}
            feedback_parts.append("✓ No tumor STL (correctly - no tumors in case)")
        else:
            score += w_tumor_exists // 2
            details['tumor_stl_exists'] = {"points": w_tumor_exists // 2, "status": "PARTIAL"}
            feedback_parts.append("⚠ Tumor STL created but no tumors in ground truth")
    
    # ============================================================
    # CRITERION 3: Liver Watertight (10 points)
    # ============================================================
    liver_watertight = result.get('liver_watertight', False)
    
    if liver_exists:
        if liver_watertight:
            score += w_liver_watertight
            details['liver_watertight'] = {"points": w_liver_watertight, "status": "PASS"}
            feedback_parts.append("✓ Liver mesh is watertight (printable)")
        else:
            details['liver_watertight'] = {"points": 0, "status": "FAIL"}
            feedback_parts.append("✗ Liver mesh is not watertight")
    else:
        details['liver_watertight'] = {"points": 0, "status": "SKIP"}
    
    # ============================================================
    # CRITERION 4: Tumor Watertight (10 points)
    # ============================================================
    tumor_watertight = result.get('tumor_watertight', False)
    
    if gt_tumor_count > 0:
        if tumor_exists:
            if tumor_watertight:
                score += w_tumor_watertight
                details['tumor_watertight'] = {"points": w_tumor_watertight, "status": "PASS"}
                feedback_parts.append("✓ Tumor mesh is watertight (printable)")
            else:
                details['tumor_watertight'] = {"points": 0, "status": "FAIL"}
                feedback_parts.append("✗ Tumor mesh is not watertight")
        else:
            details['tumor_watertight'] = {"points": 0, "status": "SKIP"}
    else:
        # No tumors expected
        score += w_tumor_watertight
        details['tumor_watertight'] = {"points": w_tumor_watertight, "status": "N/A"}
    
    # ============================================================
    # CRITERION 5: Liver Volume Accuracy (15 points)
    # ============================================================
    liver_stl_vol = float(result.get('liver_stl_volume_ml', 0))
    details['liver_stl_volume_ml'] = liver_stl_vol
    
    if gt_liver_vol > 0 and liver_stl_vol > 0:
        liver_vol_error = abs(liver_stl_vol - gt_liver_vol) / gt_liver_vol
        details['liver_volume_error_pct'] = liver_vol_error * 100
        
        if liver_vol_error <= liver_vol_error_max:
            score += w_liver_vol
            details['liver_volume_accuracy'] = {"points": w_liver_vol, "status": "PASS"}
            feedback_parts.append(f"✓ Liver volume accurate ({liver_stl_vol:.1f}mL vs GT {gt_liver_vol:.1f}mL, {liver_vol_error*100:.1f}% error)")
        elif liver_vol_error <= liver_vol_error_max * 1.5:
            partial_points = w_liver_vol // 2
            score += partial_points
            details['liver_volume_accuracy'] = {"points": partial_points, "status": "PARTIAL"}
            feedback_parts.append(f"⚠ Liver volume partially accurate ({liver_vol_error*100:.1f}% error)")
        else:
            details['liver_volume_accuracy'] = {"points": 0, "status": "FAIL"}
            feedback_parts.append(f"✗ Liver volume inaccurate ({liver_vol_error*100:.1f}% error)")
    else:
        details['liver_volume_accuracy'] = {"points": 0, "status": "FAIL"}
        feedback_parts.append("✗ Could not verify liver volume")
    
    # ============================================================
    # CRITERION 6: Tumor Volume Accuracy (15 points)
    # ============================================================
    tumor_stl_vol = float(result.get('tumor_stl_volume_ml', 0))
    details['tumor_stl_volume_ml'] = tumor_stl_vol
    
    if gt_tumor_count > 0 and gt_tumor_vol > 0:
        if tumor_stl_vol > 0:
            tumor_vol_error = abs(tumor_stl_vol - gt_tumor_vol) / gt_tumor_vol
            details['tumor_volume_error_pct'] = tumor_vol_error * 100
            
            if tumor_vol_error <= tumor_vol_error_max:
                score += w_tumor_vol
                details['tumor_volume_accuracy'] = {"points": w_tumor_vol, "status": "PASS"}
                feedback_parts.append(f"✓ Tumor volume accurate ({tumor_stl_vol:.2f}mL vs GT {gt_tumor_vol:.2f}mL)")
            elif tumor_vol_error <= tumor_vol_error_max * 1.5:
                partial_points = w_tumor_vol // 2
                score += partial_points
                details['tumor_volume_accuracy'] = {"points": partial_points, "status": "PARTIAL"}
                feedback_parts.append(f"⚠ Tumor volume partially accurate ({tumor_vol_error*100:.1f}% error)")
            else:
                details['tumor_volume_accuracy'] = {"points": 0, "status": "FAIL"}
                feedback_parts.append(f"✗ Tumor volume inaccurate ({tumor_vol_error*100:.1f}% error)")
        else:
            details['tumor_volume_accuracy'] = {"points": 0, "status": "FAIL"}
            feedback_parts.append("✗ No tumor volume measured")
    else:
        # No tumors in ground truth
        score += w_tumor_vol
        details['tumor_volume_accuracy'] = {"points": w_tumor_vol, "status": "N/A"}
    
    # ============================================================
    # CRITERION 7: Triangle Count Reasonable (5 points)
    # ============================================================
    liver_triangles = int(result.get('liver_triangles', 0))
    tumor_triangles = int(result.get('tumor_triangles', 0))
    total_triangles = liver_triangles + tumor_triangles
    
    details['total_triangles'] = total_triangles
    
    if min_triangles <= total_triangles <= max_triangles:
        score += w_triangles
        details['triangle_count'] = {"points": w_triangles, "status": "PASS"}
        feedback_parts.append(f"✓ Triangle count reasonable ({total_triangles:,})")
    elif total_triangles > 0:
        partial_points = w_triangles // 2
        score += partial_points
        details['triangle_count'] = {"points": partial_points, "status": "PARTIAL"}
        feedback_parts.append(f"⚠ Triangle count unusual ({total_triangles:,})")
    else:
        details['triangle_count'] = {"points": 0, "status": "FAIL"}
        feedback_parts.append("✗ No triangles in models")
    
    # ============================================================
    # CRITERION 8: Smoothing Applied (5 points)
    # ============================================================
    reported_smoothing = result.get('reported_smoothing', False)
    
    # Also check triangle count as proxy - very high counts suggest no smoothing
    smoothing_likely = (liver_triangles > 0 and liver_triangles < 200000)
    
    if reported_smoothing:
        score += w_smoothing
        details['smoothing_applied'] = {"points": w_smoothing, "status": "PASS"}
        feedback_parts.append("✓ Smoothing applied (per report)")
    elif smoothing_likely:
        partial_points = w_smoothing // 2
        score += partial_points
        details['smoothing_applied'] = {"points": partial_points, "status": "PARTIAL"}
        feedback_parts.append("⚠ Smoothing may have been applied (reasonable triangle count)")
    else:
        details['smoothing_applied'] = {"points": 0, "status": "FAIL"}
        feedback_parts.append("✗ Smoothing not indicated")
    
    # ============================================================
    # CRITERION 9: Report Complete (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    reported_liver = float(result.get('reported_liver_volume_ml', 0))
    reported_tumor = float(result.get('reported_tumor_volume_ml', 0))
    reported_count = int(result.get('reported_tumor_count', -1))
    
    if report_exists:
        fields_present = 0
        if reported_liver > 0:
            fields_present += 1
        if reported_tumor >= 0:  # Can be 0 if no tumors
            fields_present += 1
        if reported_count >= 0:
            fields_present += 1
        
        if fields_present >= 3:
            score += w_report
            details['report_complete'] = {"points": w_report, "status": "PASS"}
            feedback_parts.append("✓ Report contains all required fields")
        elif fields_present >= 1:
            partial_points = w_report // 2
            score += partial_points
            details['report_complete'] = {"points": partial_points, "status": "PARTIAL"}
            feedback_parts.append("⚠ Report partially complete")
        else:
            details['report_complete'] = {"points": 0, "status": "FAIL"}
            feedback_parts.append("✗ Report missing required fields")
    else:
        details['report_complete'] = {"points": 0, "status": "FAIL"}
        feedback_parts.append("✗ Report file not found")
    
    # ============================================================
    # CRITERION 10: Report Volume Match (5 points)
    # ============================================================
    if reported_liver > 0 and liver_stl_vol > 0:
        report_liver_error = abs(reported_liver - liver_stl_vol) / liver_stl_vol if liver_stl_vol > 0 else float('inf')
        
        if report_liver_error <= 0.20:  # Within 20%
            score += w_report_match
            details['report_volume_match'] = {"points": w_report_match, "status": "PASS"}
            feedback_parts.append("✓ Reported volumes match model volumes")
        else:
            details['report_volume_match'] = {"points": 0, "status": "FAIL"}
            feedback_parts.append(f"✗ Reported volumes don't match models ({report_liver_error*100:.0f}% diff)")
    else:
        details['report_volume_match'] = {"points": 0, "status": "SKIP"}
    
    # ============================================================
    # CRITERION 11: Tumor Count Correct (5 points)
    # ============================================================
    if reported_count == gt_tumor_count:
        score += w_tumor_count
        details['tumor_count_correct'] = {"points": w_tumor_count, "status": "PASS"}
        feedback_parts.append(f"✓ Tumor count correct ({reported_count})")
    elif abs(reported_count - gt_tumor_count) <= 1 and reported_count >= 0:
        partial_points = w_tumor_count // 2
        score += partial_points
        details['tumor_count_correct'] = {"points": partial_points, "status": "PARTIAL"}
        feedback_parts.append(f"⚠ Tumor count close (reported {reported_count}, actual {gt_tumor_count})")
    else:
        details['tumor_count_correct'] = {"points": 0, "status": "FAIL"}
        if reported_count >= 0:
            feedback_parts.append(f"✗ Tumor count incorrect (reported {reported_count}, actual {gt_tumor_count})")
        else:
            feedback_parts.append(f"✗ Tumor count not reported (actual {gt_tumor_count})")
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    details['score'] = score
    details['max_score'] = 100
    
    # Pass criteria: score >= 60 AND both STL files exist (or tumor not required)
    stl_files_valid = liver_exists and (liver_size > 10000)
    if gt_tumor_count > 0:
        stl_files_valid = stl_files_valid and tumor_exists and (tumor_size > 500)
    
    passed = (score >= 60) and stl_files_valid
    
    if passed:
        feedback_parts.append(f"\n✓ TASK PASSED with score {score}/100")
    else:
        if not stl_files_valid:
            feedback_parts.append(f"\n✗ TASK FAILED - Required STL files missing or invalid (score: {score}/100)")
        else:
            feedback_parts.append(f"\n✗ TASK FAILED - Score {score}/100 (need 60 to pass)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test mode
    print("Verifier module for liver_3d_model_export task")
    print("Run with task framework to execute verification")