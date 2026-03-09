#!/usr/bin/env python3
"""
Verifier for Tumor Histogram Heterogeneity Analysis task.

VERIFICATION STRATEGY:
1. Mean Intensity Accuracy (20 points) - within 5% of ground truth
2. SD Accuracy (20 points) - within 10% of ground truth  
3. CV Calculation Consistency (15 points) - CV = SD/Mean × 100 internally consistent
4. Heterogeneity Classification (15 points) - correct class for computed CV
5. Statistics CSV Exported (10 points) - valid CSV file with data
6. JSON Report Complete (10 points) - all 6 required fields present
7. Min/Max Reasonable (5 points) - Min < Mean < Max
8. File Timestamps Valid (5 points) - created after task start

Pass threshold: 65 points with mean and SD accuracy criteria met
"""

import json
import os
import sys
import tempfile
import shutil
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def safe_float(value: Any, default: float = 0.0) -> float:
    """Safely convert a value to float."""
    if value is None or value == "":
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def get_expected_class(cv: float) -> str:
    """Determine heterogeneity class from CV value."""
    if cv < 20:
        return "Homogeneous"
    elif cv < 35:
        return "Mildly Heterogeneous"
    elif cv < 50:
        return "Moderately Heterogeneous"
    else:
        return "Highly Heterogeneous"


def normalize_class_name(class_name: str) -> str:
    """Normalize heterogeneity class name for comparison."""
    if not class_name:
        return ""
    normalized = class_name.lower().strip()
    # Handle common variations
    normalized = normalized.replace("_", " ").replace("-", " ")
    # Remove extra whitespace
    normalized = " ".join(normalized.split())
    return normalized


def classes_match(reported: str, expected: str) -> bool:
    """Check if two class names match (case-insensitive, flexible)."""
    r_norm = normalize_class_name(reported)
    e_norm = normalize_class_name(expected)
    
    if r_norm == e_norm:
        return True
    
    # Check for partial matches (e.g., "mildly heterogeneous" matches "mild heterogeneous")
    if "homogeneous" in r_norm and "homogeneous" in e_norm:
        # Check if both are the same type
        r_is_mild = "mild" in r_norm
        e_is_mild = "mild" in e_norm
        r_is_mod = "moderate" in r_norm
        e_is_mod = "moderate" in e_norm
        r_is_high = "high" in r_norm
        e_is_high = "high" in e_norm
        r_is_plain = not (r_is_mild or r_is_mod or r_is_high)
        e_is_plain = not (e_is_mild or e_is_mod or e_is_high)
        
        return (r_is_plain == e_is_plain and 
                r_is_mild == e_is_mild and 
                r_is_mod == e_is_mod and 
                r_is_high == e_is_high)
    
    return False


def verify_tumor_histogram_heterogeneity(traj: Dict[str, Any], 
                                          env_info: Dict[str, Any], 
                                          task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the tumor heterogeneity histogram analysis task.
    
    Uses copy_from_env to retrieve files from the container.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Verification environment not available - copy_from_env function missing"
        }
    
    # Get scoring weights from metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    thresholds = metadata.get('passing_thresholds', {})
    
    w_mean = weights.get('mean_accuracy', 20)
    w_sd = weights.get('sd_accuracy', 20)
    w_cv = weights.get('cv_calculation', 15)
    w_class = weights.get('classification_correct', 15)
    w_csv = weights.get('csv_exported', 10)
    w_report = weights.get('report_complete', 10)
    w_minmax = weights.get('minmax_reasonable', 5)
    w_timestamp = weights.get('timestamps_valid', 5)
    
    mean_error_thresh = thresholds.get('mean_error_percent', 5.0)
    sd_error_thresh = thresholds.get('sd_error_percent', 10.0)
    cv_consistency_thresh = thresholds.get('cv_internal_consistency', 1.0)
    
    temp_dir = tempfile.mkdtemp()
    score = 0
    feedback_parts = []
    details = {}
    
    try:
        # ============================================================
        # Load task result from container
        # ============================================================
        result_file = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_file)
            with open(result_file, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Could not load task result: {e}"
            }
        
        sample_id = result.get("sample_id", "BraTS2021_00000")
        details['sample_id'] = sample_id
        
        # ============================================================
        # Load ground truth
        # ============================================================
        gt_file = os.path.join(temp_dir, "ground_truth.json")
        try:
            copy_from_env("/tmp/heterogeneity_gt.json", gt_file)
            with open(gt_file, 'r') as f:
                ground_truth = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Could not load ground truth: {e}"
            }
        
        gt_mean = ground_truth.get("mean_intensity", 0)
        gt_sd = ground_truth.get("std_intensity", 0)
        gt_cv = ground_truth.get("coefficient_of_variation_percent", 0)
        gt_class = ground_truth.get("heterogeneity_class", "")
        gt_min = ground_truth.get("min_intensity", 0)
        gt_max = ground_truth.get("max_intensity", 0)
        
        details['ground_truth'] = {
            'mean': gt_mean,
            'sd': gt_sd,
            'cv': gt_cv,
            'class': gt_class
        }
        
        # ============================================================
        # CRITERION 1: File timestamps valid (5 points)
        # ============================================================
        csv_after_start = result.get("csv_created_after_start", False)
        report_after_start = result.get("report_created_after_start", False)
        
        if csv_after_start or report_after_start:
            score += w_timestamp
            feedback_parts.append(f"✓ Files created during task (+{w_timestamp})")
        else:
            feedback_parts.append("✗ Files may have existed before task (+0)")
        
        # ============================================================
        # CRITERION 2: CSV export (10 points)
        # ============================================================
        csv_exists = result.get("csv_exists", False)
        csv_has_data = result.get("csv_has_data", False)
        
        if csv_exists and csv_has_data:
            if csv_after_start:
                score += w_csv
                feedback_parts.append(f"✓ Statistics CSV exported with data (+{w_csv})")
            else:
                score += w_csv // 2
                feedback_parts.append(f"~ CSV exists but timestamp suspicious (+{w_csv // 2})")
        elif csv_exists:
            score += w_csv // 4
            feedback_parts.append(f"~ CSV exists but appears empty (+{w_csv // 4})")
        else:
            feedback_parts.append("✗ Statistics CSV not found (+0)")
        
        # ============================================================
        # CRITERION 3: Report completeness (10 points)
        # ============================================================
        report_exists = result.get("report_exists", False)
        report_valid = result.get("report_valid", False)
        
        if report_valid:
            # Try to load full report to check fields
            try:
                report_file = os.path.join(temp_dir, "agent_report.json")
                copy_from_env("/tmp/agent_heterogeneity_report.json", report_file)
                with open(report_file, 'r') as f:
                    agent_report = json.load(f)
                
                required_fields = [
                    "mean_intensity", "std_intensity", "min_intensity",
                    "max_intensity", "coefficient_of_variation_percent",
                    "heterogeneity_class"
                ]
                
                # Check for fields with alternate names
                field_aliases = {
                    "mean_intensity": ["mean", "Mean", "mean_value"],
                    "std_intensity": ["std", "SD", "standard_deviation", "stdev"],
                    "min_intensity": ["min", "Min", "minimum"],
                    "max_intensity": ["max", "Max", "maximum"],
                    "coefficient_of_variation_percent": ["cv", "CV", "coefficient_of_variation"],
                    "heterogeneity_class": ["class", "classification", "category"]
                }
                
                present_count = 0
                for field in required_fields:
                    if field in agent_report:
                        present_count += 1
                    else:
                        # Check aliases
                        for alias in field_aliases.get(field, []):
                            if alias in agent_report:
                                present_count += 1
                                break
                
                if present_count == len(required_fields):
                    score += w_report
                    feedback_parts.append(f"✓ All required fields present in report (+{w_report})")
                else:
                    partial = int(w_report * present_count / len(required_fields))
                    score += partial
                    feedback_parts.append(f"~ {present_count}/{len(required_fields)} fields present (+{partial})")
                
                details['report_fields_present'] = present_count
                
            except Exception as e:
                feedback_parts.append(f"~ Could not fully parse report: {e} (+0)")
                agent_report = {}
        else:
            feedback_parts.append("✗ Report invalid or missing (+0)")
            agent_report = {}
        
        # ============================================================
        # CRITERION 4: Mean intensity accuracy (20 points)
        # ============================================================
        reported_mean = safe_float(result.get("reported_mean", 0))
        details['reported_mean'] = reported_mean
        
        mean_achieved = False
        if gt_mean > 0 and reported_mean > 0:
            mean_error = abs(reported_mean - gt_mean) / gt_mean * 100
            details['mean_error_percent'] = mean_error
            
            if mean_error <= mean_error_thresh:
                score += w_mean
                mean_achieved = True
                feedback_parts.append(f"✓ Mean intensity accurate: {reported_mean:.2f} vs GT {gt_mean:.2f} ({mean_error:.1f}% error) (+{w_mean})")
            elif mean_error <= mean_error_thresh * 3:
                partial = w_mean // 2
                score += partial
                feedback_parts.append(f"~ Mean intensity close: {reported_mean:.2f} vs GT {gt_mean:.2f} ({mean_error:.1f}% error) (+{partial})")
            else:
                feedback_parts.append(f"✗ Mean intensity inaccurate: {reported_mean:.2f} vs GT {gt_mean:.2f} ({mean_error:.1f}% error) (+0)")
        elif reported_mean <= 0:
            feedback_parts.append("✗ Mean intensity not reported or invalid (+0)")
        else:
            feedback_parts.append("✗ Could not verify mean (GT invalid) (+0)")
        
        # ============================================================
        # CRITERION 5: SD accuracy (20 points)
        # ============================================================
        reported_sd = safe_float(result.get("reported_sd", 0))
        details['reported_sd'] = reported_sd
        
        sd_achieved = False
        if gt_sd > 0 and reported_sd > 0:
            sd_error = abs(reported_sd - gt_sd) / gt_sd * 100
            details['sd_error_percent'] = sd_error
            
            if sd_error <= sd_error_thresh:
                score += w_sd
                sd_achieved = True
                feedback_parts.append(f"✓ SD accurate: {reported_sd:.2f} vs GT {gt_sd:.2f} ({sd_error:.1f}% error) (+{w_sd})")
            elif sd_error <= sd_error_thresh * 2.5:
                partial = w_sd // 2
                score += partial
                feedback_parts.append(f"~ SD close: {reported_sd:.2f} vs GT {gt_sd:.2f} ({sd_error:.1f}% error) (+{partial})")
            else:
                feedback_parts.append(f"✗ SD inaccurate: {reported_sd:.2f} vs GT {gt_sd:.2f} ({sd_error:.1f}% error) (+0)")
        elif reported_sd <= 0:
            feedback_parts.append("✗ SD not reported or invalid (+0)")
        else:
            feedback_parts.append("✗ Could not verify SD (GT invalid) (+0)")
        
        # ============================================================
        # CRITERION 6: CV calculation consistency (15 points)
        # ============================================================
        reported_cv = safe_float(result.get("reported_cv", 0))
        details['reported_cv'] = reported_cv
        
        if reported_mean > 0 and reported_sd >= 0:
            expected_cv = (reported_sd / reported_mean) * 100
            cv_diff = abs(reported_cv - expected_cv)
            details['expected_cv_from_values'] = expected_cv
            details['cv_consistency_diff'] = cv_diff
            
            if cv_diff <= cv_consistency_thresh:
                score += w_cv
                feedback_parts.append(f"✓ CV internally consistent: {reported_cv:.2f}% (expected {expected_cv:.2f}%) (+{w_cv})")
            elif cv_diff <= cv_consistency_thresh * 5:
                partial = w_cv // 2
                score += partial
                feedback_parts.append(f"~ CV slightly inconsistent: {reported_cv:.2f}% vs expected {expected_cv:.2f}% (+{partial})")
            else:
                feedback_parts.append(f"✗ CV calculation incorrect: {reported_cv:.2f}% vs expected {expected_cv:.2f}% (+0)")
        else:
            feedback_parts.append("✗ Cannot verify CV calculation (mean or SD invalid) (+0)")
        
        # ============================================================
        # CRITERION 7: Heterogeneity classification (15 points)
        # ============================================================
        reported_class = result.get("reported_class", "").strip()
        details['reported_class'] = reported_class
        
        if reported_cv > 0:
            expected_class = get_expected_class(reported_cv)
            details['expected_class_from_cv'] = expected_class
            
            if classes_match(reported_class, expected_class):
                score += w_class
                feedback_parts.append(f"✓ Classification correct: '{reported_class}' for CV={reported_cv:.1f}% (+{w_class})")
            elif classes_match(reported_class, gt_class):
                # Agent got the right answer even if our CV calculation differs
                partial = int(w_class * 0.8)
                score += partial
                feedback_parts.append(f"~ Classification matches ground truth: '{reported_class}' (+{partial})")
            else:
                feedback_parts.append(f"✗ Classification '{reported_class}' doesn't match expected '{expected_class}' for CV={reported_cv:.1f}% (+0)")
        elif classes_match(reported_class, gt_class):
            partial = int(w_class * 0.7)
            score += partial
            feedback_parts.append(f"~ Classification matches ground truth despite CV issues (+{partial})")
        else:
            feedback_parts.append("✗ Classification could not be verified (+0)")
        
        # ============================================================
        # CRITERION 8: Min/Max reasonableness (5 points)
        # ============================================================
        reported_min = safe_float(result.get("reported_min", -1))
        reported_max = safe_float(result.get("reported_max", -1))
        details['reported_min'] = reported_min
        details['reported_max'] = reported_max
        
        if reported_min >= 0 and reported_max > 0 and reported_mean > 0:
            if reported_min < reported_mean < reported_max:
                score += w_minmax
                feedback_parts.append(f"✓ Min/Max reasonable: {reported_min:.1f} < {reported_mean:.1f} < {reported_max:.1f} (+{w_minmax})")
            else:
                feedback_parts.append(f"✗ Min/Max values inconsistent: min={reported_min:.1f}, mean={reported_mean:.1f}, max={reported_max:.1f} (+0)")
        else:
            feedback_parts.append("~ Min/Max not reported or invalid (+0)")
        
        # ============================================================
        # Final scoring and feedback
        # ============================================================
        score = min(100, max(0, score))
        
        # Key criteria for passing
        key_criteria_met = mean_achieved and sd_achieved
        passed = score >= 65 and key_criteria_met
        
        # Add summary
        feedback_parts.append("")
        feedback_parts.append("--- Ground Truth Reference ---")
        feedback_parts.append(f"Mean: {gt_mean:.2f}, SD: {gt_sd:.2f}, CV: {gt_cv:.2f}%")
        feedback_parts.append(f"Expected Class: {gt_class}")
        feedback_parts.append("")
        feedback_parts.append(f"Final Score: {score}/100")
        
        if passed:
            feedback_parts.append("✓ PASSED: Task completed successfully")
        else:
            if not key_criteria_met:
                feedback_parts.append("✗ FAILED: Mean and SD accuracy criteria not met")
            else:
                feedback_parts.append("✗ FAILED: Did not meet passing threshold of 65 points")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts),
            "details": details
        }
        
    except Exception as e:
        logger.exception("Verification error")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
        
    finally:
        # Clean up temp directory
        if temp_dir and os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    # For testing
    print("Tumor Histogram Heterogeneity Verifier")
    print("Run via the task framework, not directly.")