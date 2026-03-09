#!/usr/bin/env python3
"""
Verifier for Measurement Quality Audit task.

VERIFICATION CRITERIA:
1. Error Identification (25 pts): Agent correctly identified erroneous measurements
2. No False Positives (15 pts): Agent did not flag correct measurements as wrong
3. Aortic Correction Level (15 pts): Corrected measurement at proper vertebral level
4. Aortic Correction Value (10 pts): Diameter measurement within tolerance
5. Celiac Correction (10 pts): Celiac distance measurement properly corrected
6. Report Error Descriptions (10 pts): Audit report contains error descriptions
7. Report Corrected Values (10 pts): Report includes corrected measurement values
8. Files Saved (5 pts): Both output files exist and are valid

Pass Threshold: 60 points with error identification achieved
"""

import json
import os
import sys
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_measurement_quality_audit(traj, env_info, task_info):
    """
    Verify measurement quality audit task completion.
    
    Uses copy_from_env to read files from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    
    w_error_id = weights.get('error_identification', 25)
    w_no_fp = weights.get('no_false_positives', 15)
    w_aorta_level = weights.get('aorta_correction_level', 15)
    w_aorta_value = weights.get('aorta_correction_value', 10)
    w_celiac = weights.get('celiac_correction', 10)
    w_descriptions = weights.get('report_error_descriptions', 10)
    w_values = weights.get('report_corrected_values', 10)
    w_files = weights.get('files_saved', 5)

    score = 0
    max_score = 100
    feedback_parts = []
    details = {}

    # Create temp directory for all files
    temp_dir = tempfile.mkdtemp()
    
    try:
        # ================================================================
        # Load result data
        # ================================================================
        result_data = {}
        try:
            local_result = os.path.join(temp_dir, "result.json")
            copy_from_env("/tmp/task_result.json", local_result)
            with open(local_result, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            feedback_parts.append(f"Could not load result file: {e}")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # Check basic requirements
        if not result_data.get("slicer_was_running", False):
            return {"passed": False, "score": 0, "feedback": "3D Slicer was not running"}

        details["task_elapsed_seconds"] = result_data.get("elapsed_seconds", 0)

        # ================================================================
        # Load ground truth
        # ================================================================
        gt_data = {}
        try:
            local_gt = os.path.join(temp_dir, "gt.json")
            copy_from_env("/tmp/measurement_audit_gt.json", local_gt)
            with open(local_gt, 'r') as f:
                gt_data = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load ground truth: {e}")
            # Use defaults from metadata
            gt_data = {
                "erroneous_measurements": metadata.get("erroneous_measurements", 
                    ["trainee_aorta_diameter", "trainee_celiac_distance"]),
                "correct_measurements": metadata.get("correct_measurements",
                    ["trainee_ivc_diameter", "trainee_renal_bifurcation"])
            }

        erroneous_gt = set(gt_data.get("erroneous_measurements", []))
        correct_gt = set(gt_data.get("correct_measurements", []))
        
        details["gt_erroneous"] = list(erroneous_gt)
        details["gt_correct"] = list(correct_gt)

        # ================================================================
        # Load audit report
        # ================================================================
        audit_report = {}
        report_exists = result_data.get("audit_report_exists", False)
        report_created_during_task = result_data.get("report_created_during_task", False)

        if report_exists:
            try:
                local_report = os.path.join(temp_dir, "audit_report.json")
                copy_from_env("/tmp/measurement_audit_report.json", local_report)
                with open(local_report, 'r') as f:
                    audit_report = json.load(f)
                details["audit_report_loaded"] = True
            except Exception as e:
                feedback_parts.append(f"Could not parse audit report: {e}")
                details["audit_report_loaded"] = False
        else:
            feedback_parts.append("Audit report file not found")
            details["audit_report_loaded"] = False

        # ================================================================
        # Load corrected measurements
        # ================================================================
        corrected_markups = {}
        markups_exists = result_data.get("corrected_markups_exists", False)
        markups_created_during_task = result_data.get("corrected_created_during_task", False)

        if markups_exists:
            try:
                local_markups = os.path.join(temp_dir, "corrected.json")
                copy_from_env("/tmp/corrected_measurements.mrk.json", local_markups)
                with open(local_markups, 'r') as f:
                    corrected_markups = json.load(f)
                details["corrected_markups_loaded"] = True
            except Exception as e:
                feedback_parts.append(f"Could not parse corrected markups: {e}")
                details["corrected_markups_loaded"] = False
        else:
            details["corrected_markups_loaded"] = False

        # ================================================================
        # Criterion 1: Error Identification (25 points)
        # ================================================================
        identified_errors = set()

        # Extract identified errors from audit report
        if audit_report:
            # Try various possible keys
            for key in ["erroneous_measurements", "errors", "incorrect_measurements", 
                        "measurements_with_errors", "identified_errors", "flagged_errors"]:
                if key in audit_report:
                    val = audit_report[key]
                    if isinstance(val, list):
                        identified_errors.update(val)
                    elif isinstance(val, dict):
                        identified_errors.update(val.keys())

        # Normalize names
        def normalize_name(name):
            name = str(name).lower().strip()
            for prefix in ["trainee_", "corrected_"]:
                if name.startswith(prefix):
                    name = name[len(prefix):]
            return name

        identified_normalized = {normalize_name(n) for n in identified_errors}
        erroneous_normalized = {normalize_name(n) for n in erroneous_gt}
        correct_normalized = {normalize_name(n) for n in correct_gt}

        # Check true positives
        true_positives = identified_normalized & erroneous_normalized
        details["true_positives"] = list(true_positives)
        details["identified_errors"] = list(identified_normalized)

        error_id_achieved = False
        if len(true_positives) == len(erroneous_normalized):
            score += w_error_id
            feedback_parts.append(f"✓ Correctly identified both erroneous measurements (+{w_error_id})")
            error_id_achieved = True
            details["error_identification"] = "complete"
        elif len(true_positives) >= 1:
            partial_score = int(w_error_id * len(true_positives) / len(erroneous_normalized))
            score += partial_score
            feedback_parts.append(f"◐ Identified {len(true_positives)}/{len(erroneous_normalized)} erroneous measurements (+{partial_score})")
            error_id_achieved = True
            details["error_identification"] = "partial"
        else:
            feedback_parts.append("✗ Did not correctly identify erroneous measurements (+0)")
            details["error_identification"] = "failed"

        # ================================================================
        # Criterion 2: No False Positives (15 points)
        # ================================================================
        false_positives = identified_normalized & correct_normalized
        details["false_positives"] = list(false_positives)

        if len(false_positives) == 0:
            score += w_no_fp
            feedback_parts.append(f"✓ No false positives - correct measurements not flagged (+{w_no_fp})")
        elif len(false_positives) == 1:
            partial = w_no_fp // 2
            score += partial
            feedback_parts.append(f"◐ One false positive: {false_positives} (+{partial})")
        else:
            feedback_parts.append(f"✗ False positives: incorrectly flagged {false_positives} (+0)")

        # ================================================================
        # Criterion 3: Aortic Measurement Correction - Level (15 points)
        # ================================================================
        aorta_level_correct = False
        aorta_correction_found = False

        if corrected_markups and "markups" in corrected_markups:
            for markup in corrected_markups.get("markups", []):
                name = markup.get("name", "").lower()
                if "aorta" in name or "aortic" in name:
                    aorta_correction_found = True
                    details["aorta_correction_name"] = markup.get("name")

                    # Get control points
                    control_points = markup.get("controlPoints", [])
                    if len(control_points) >= 2:
                        z_coords = []
                        for cp in control_points:
                            pos = cp.get("position", [0, 0, 0])
                            if len(pos) >= 3:
                                z_coords.append(pos[2])

                        if z_coords:
                            avg_z = sum(z_coords) / len(z_coords)
                            details["corrected_aorta_z"] = avg_z

                            # Get ground truth Z position
                            gt_aorta = gt_data.get("correct_aorta_measurement", {})
                            gt_z = None
                            if "p1_ras" in gt_aorta:
                                gt_z = gt_aorta["p1_ras"][2]

                            if gt_z is not None:
                                z_error = abs(avg_z - gt_z)
                                details["aorta_z_error_mm"] = round(z_error, 1)

                                # Allow 25mm tolerance in Z direction
                                if z_error <= 25:
                                    aorta_level_correct = True
                                    score += w_aorta_level
                                    feedback_parts.append(f"✓ Aortic measurement at correct level (Z error: {z_error:.1f}mm) (+{w_aorta_level})")
                                else:
                                    feedback_parts.append(f"✗ Aortic measurement still at wrong level (Z error: {z_error:.1f}mm)")
                    break

        if not aorta_correction_found:
            feedback_parts.append("✗ No corrected aortic measurement found")
        details["aorta_correction_found"] = aorta_correction_found

        # ================================================================
        # Criterion 4: Aortic Measurement Value (10 points)
        # ================================================================
        if aorta_correction_found and corrected_markups:
            for markup in corrected_markups.get("markups", []):
                name = markup.get("name", "").lower()
                if "aorta" in name or "aortic" in name:
                    control_points = markup.get("controlPoints", [])
                    if len(control_points) >= 2:
                        p1 = control_points[0].get("position", [0, 0, 0])
                        p2 = control_points[1].get("position", [0, 0, 0])

                        # Calculate measurement length
                        length = math.sqrt(sum((a - b)**2 for a, b in zip(p1, p2)))
                        details["corrected_aorta_diameter_mm"] = round(length, 1)

                        # Compare to ground truth
                        gt_diameter = gt_data.get("correct_aorta_measurement", {}).get("diameter_mm", 33.0)
                        diameter_error = abs(length - gt_diameter)
                        details["aorta_diameter_error_mm"] = round(diameter_error, 1)

                        # Allow 8mm tolerance
                        if diameter_error <= 8:
                            score += w_aorta_value
                            feedback_parts.append(f"✓ Aortic diameter value correct ({length:.1f}mm, error: {diameter_error:.1f}mm) (+{w_aorta_value})")
                        else:
                            feedback_parts.append(f"✗ Aortic diameter value off ({length:.1f}mm vs {gt_diameter:.1f}mm expected)")
                    break

        # ================================================================
        # Criterion 5: Celiac Distance Correction (10 points)
        # ================================================================
        celiac_correction_found = False

        if corrected_markups and "markups" in corrected_markups:
            for markup in corrected_markups.get("markups", []):
                name = markup.get("name", "").lower()
                if "celiac" in name:
                    celiac_correction_found = True
                    score += w_celiac
                    feedback_parts.append(f"✓ Celiac distance measurement corrected (+{w_celiac})")
                    break

        if not celiac_correction_found:
            feedback_parts.append("✗ No corrected celiac measurement found")
        details["celiac_correction_found"] = celiac_correction_found

        # ================================================================
        # Criterion 6: Report Error Descriptions (10 points)
        # ================================================================
        has_descriptions = False
        descriptions_found = []

        if audit_report:
            # Check for error descriptions
            for key in ["error_descriptions", "errors", "findings", "issues", "problems"]:
                if key in audit_report:
                    val = audit_report[key]
                    if isinstance(val, dict):
                        for k, v in val.items():
                            if isinstance(v, str) and len(v) > 10:
                                descriptions_found.append(v[:50])
                            elif isinstance(v, dict):
                                desc = v.get("description", v.get("error", v.get("issue", "")))
                                if isinstance(desc, str) and len(desc) > 10:
                                    descriptions_found.append(desc[:50])
                    elif isinstance(val, list):
                        for item in val:
                            if isinstance(item, str) and len(item) > 10:
                                descriptions_found.append(item[:50])
                            elif isinstance(item, dict):
                                desc = item.get("description", item.get("error", ""))
                                if isinstance(desc, str) and len(desc) > 10:
                                    descriptions_found.append(desc[:50])

        details["descriptions_found"] = descriptions_found[:3]  # Limit for readability

        if len(descriptions_found) >= 2:
            has_descriptions = True
            score += w_descriptions
            feedback_parts.append(f"✓ Audit report contains error descriptions (+{w_descriptions})")
        elif len(descriptions_found) == 1:
            score += w_descriptions // 2
            feedback_parts.append(f"◐ Audit report has partial error descriptions (+{w_descriptions // 2})")
        else:
            feedback_parts.append("✗ Audit report missing error descriptions")

        details["has_error_descriptions"] = has_descriptions

        # ================================================================
        # Criterion 7: Report Corrected Values (10 points)
        # ================================================================
        has_corrected_values = False

        if audit_report:
            # Look for corrected values
            for key in ["corrected_values", "corrections", "new_measurements", 
                        "corrected_measurements", "new_values"]:
                if key in audit_report:
                    val = audit_report[key]
                    if isinstance(val, dict) and len(val) > 0:
                        has_corrected_values = True
                    elif isinstance(val, list) and len(val) > 0:
                        has_corrected_values = True

            # Also check if numeric values are present anywhere
            def find_numeric(obj, depth=0):
                if depth > 3:
                    return False
                if isinstance(obj, (int, float)) and obj > 0:
                    return True
                if isinstance(obj, dict):
                    return any(find_numeric(v, depth+1) for v in obj.values())
                if isinstance(obj, list):
                    return any(find_numeric(v, depth+1) for v in obj)
                return False

            if not has_corrected_values and find_numeric(audit_report):
                # Found numeric values somewhere in the report
                has_corrected_values = True

        if has_corrected_values:
            score += w_values
            feedback_parts.append(f"✓ Audit report includes corrected measurement values (+{w_values})")
        else:
            feedback_parts.append("✗ Audit report missing corrected values")

        details["has_corrected_values"] = has_corrected_values

        # ================================================================
        # Criterion 8: All Files Saved (5 points)
        # ================================================================
        if markups_exists and report_exists:
            markups_size = result_data.get("corrected_markups_size", 0)
            report_size = result_data.get("audit_report_size", 0)

            if markups_size > 100 and report_size > 50:
                # Check if created during task (anti-gaming)
                if markups_created_during_task or report_created_during_task:
                    score += w_files
                    feedback_parts.append(f"✓ All required files saved during task (+{w_files})")
                else:
                    score += w_files // 2
                    feedback_parts.append(f"◐ Files exist but may not be from this task (+{w_files // 2})")
            else:
                feedback_parts.append("✗ Output files empty or too small")
        else:
            missing = []
            if not markups_exists:
                missing.append("corrected_measurements.mrk.json")
            if not report_exists:
                missing.append("measurement_audit_report.json")
            feedback_parts.append(f"✗ Missing output files: {', '.join(missing)}")

        details["markups_exists"] = markups_exists
        details["report_exists"] = report_exists

        # ================================================================
        # Final scoring
        # ================================================================
        details["score"] = score
        details["max_score"] = max_score
        details["percentage"] = round(score / max_score * 100, 1)

        # Pass threshold: 60 points with error identification achieved
        min_score = metadata.get("passing_thresholds", {}).get("min_score", 60)
        passed = score >= min_score and error_id_achieved

        feedback = "\n".join(feedback_parts)
        feedback += f"\n\nFinal Score: {score}/{max_score} ({details['percentage']}%)"

        if passed:
            feedback += "\n\n✓ PASSED - Successfully audited measurements and identified errors"
        else:
            if not error_id_achieved:
                feedback += "\n\n✗ FAILED - Must identify at least one erroneous measurement to pass"
            else:
                feedback += f"\n\n✗ FAILED - Score {score} below threshold of {min_score}"

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": details
        }

    finally:
        # Cleanup temp directory
        try:
            import shutil
            shutil.rmtree(temp_dir)
        except Exception:
            pass