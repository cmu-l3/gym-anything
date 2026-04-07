#!/usr/bin/env python3
"""
Verifier for pebl_multisite_data_harmonization task.

Scoring system (100 points total):
1. Valid Files Created (10 pts)
2. Column Standardization (20 pts)
3. Site C Parsing (20 pts)
4. Exclusion Rules Applied (20 pts)
5. JSON Report Accuracy (10 pts)
6. Merged Data Integrity (20 pts)

Pass threshold: 70 points
"""

import os
import json
import tempfile
import csv

def verify_pebl_multisite_data_harmonization(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # Temporary files
    tmp_csv = tempfile.NamedTemporaryFile(suffix='.csv', delete=False).name
    tmp_json = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name
    tmp_gt = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name

    csv_exists = False
    try:
        copy_from_env('/home/ga/pebl/data/harmonized_dataset.csv', tmp_csv)
        csv_exists = os.path.exists(tmp_csv) and os.path.getsize(tmp_csv) > 0
    except Exception:
        pass

    json_exists = False
    try:
        copy_from_env('/home/ga/pebl/analysis/harmonization_report.json', tmp_json)
        json_exists = os.path.exists(tmp_json) and os.path.getsize(tmp_json) > 0
    except Exception:
        pass

    gt_exists = False
    try:
        copy_from_env('/tmp/harmonization_gt.json', tmp_gt)
        gt_exists = os.path.exists(tmp_gt)
    except Exception:
        pass

    if not gt_exists:
        return {"passed": False, "score": 0, "feedback": "Ground truth not found. Test setup error."}

    with open(tmp_gt, 'r') as f:
        gt_data = json.load(f)

    if csv_exists and json_exists:
        score += 10
        feedback.append("[+10] Both output files created.")
    else:
        feedback.append("[0] One or both output files are missing.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Check CSV
    try:
        with open(tmp_csv, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            try:
                header = next(reader)
            except StopIteration:
                header = []
            rows = list(reader)

        expected_cols = {"participant_id", "site", "block", "trial", "rule", "response", "accuracy", "rt_ms"}
        actual_cols = set([c.strip() for c in header])

        if expected_cols == actual_cols:
            score += 20
            feedback.append("[+20] CSV column names standardized perfectly.")
        else:
            feedback.append(f"[0] CSV columns incorrect. Expected: {expected_cols}, Got: {actual_cols}")

        # Check Site C Parsing
        col_map = {name.strip(): idx for idx, name in enumerate(header)}
        if "participant_id" in col_map and "site" in col_map:
            site_c_rows = [r for r in rows if len(r) > col_map["site"] and r[col_map["site"]].strip().lower() == "site_c"]
            if len(site_c_rows) > 0:
                site_c_pids = set([r[col_map["participant_id"]].strip() for r in site_c_rows if len(r) > col_map["participant_id"]])
                
                # Check if all Site C IDs start with sub-C
                if len(site_c_pids) > 0 and all(pid.upper().startswith("SUB-C") for pid in site_c_pids):
                    score += 20
                    feedback.append("[+20] Site C IDs correctly extracted from filenames.")
                else:
                    feedback.append("[0] Site C IDs not correctly extracted (should start with sub-C).")
            else:
                feedback.append("[0] No site_c rows found in the CSV.")

        # Check exclusions
        if "participant_id" in col_map:
            pids_in_csv = set([r[col_map["participant_id"]].strip().upper() for r in rows if len(r) > col_map["participant_id"]])
            excluded_gt = [exc.upper() for exc in gt_data["excluded"]]
            
            if not any(exc in pids_in_csv for exc in excluded_gt):
                score += 20
                feedback.append(f"[+20] Excluded participants are correctly omitted from the CSV.")
            else:
                feedback.append(f"[0] Excluded participants (e.g., corrupted/incomplete) are incorrectly still present in the CSV.")

        # Check total row count and data integrity
        if len(rows) == gt_data["total_rows"]:
            if "rt_ms" in col_map:
                try:
                    rt_values = [float(r[col_map["rt_ms"]].strip()) for r in rows if len(r) > col_map["rt_ms"] and r[col_map["rt_ms"]].strip()]
                    if len(rt_values) > 0:
                        mean_rt = sum(rt_values) / len(rt_values)
                        if abs(mean_rt - gt_data["gt_mean_rt"]) < 1.0:
                            score += 20
                            feedback.append(f"[+20] CSV data integrity confirmed (row count {len(rows)}, mean RT matched ground truth).")
                        else:
                            feedback.append(f"[+10] CSV row count correct, but mean RT {mean_rt:.1f} didn't match GT {gt_data['gt_mean_rt']:.1f}.")
                            score += 10
                    else:
                        feedback.append("[0] rt_ms column is entirely empty.")
                except ValueError:
                    feedback.append("[0] rt_ms contains non-numeric values preventing data integrity validation.")
            else:
                feedback.append("[0] Cannot check mean RT due to missing rt_ms column.")
        else:
            feedback.append(f"[0] CSV row count is {len(rows)}, expected exactly {gt_data['total_rows']}.")

    except Exception as e:
        feedback.append(f"[0] Error parsing CSV: {e}")

    # Check JSON Report
    try:
        with open(tmp_json, 'r', encoding='utf-8') as f:
            report = json.load(f)

        json_score = 0
        if report.get("total_valid_participants") == gt_data["total_valid"]:
            json_score += 5
        
        # Check global_mean_rt_ms
        if "global_mean_rt_ms" in report:
            try:
                if abs(float(report["global_mean_rt_ms"]) - gt_data["gt_mean_rt"]) < 2.0:
                    json_score += 5
            except ValueError:
                pass
        
        score += json_score
        feedback.append(f"[+{json_score}] JSON report checked (expected 10).")

    except Exception as e:
        feedback.append(f"[0] Error parsing JSON report: {e}")

    # Cleanup
    for p in [tmp_csv, tmp_json, tmp_gt]:
        if os.path.exists(p):
            os.remove(p)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }