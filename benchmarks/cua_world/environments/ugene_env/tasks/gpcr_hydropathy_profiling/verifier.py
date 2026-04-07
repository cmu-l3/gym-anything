#!/usr/bin/env python3
"""Verifier for gpcr_hydropathy_profiling task.

Scores (100 pts total):
1. CSV data exported and parseable as numeric: 15 pts
2. Authentic Kyte-Doolittle Profile Signature (7 peaks found): 25 pts
3. Report mentions sequence length 413: 10 pts
4. Report mentions exactly 7 TM domains: 10 pts
5. Biological Coordinate Accuracy (ranges match ground truth ±15 residues): 30 pts
6. Visual evidence (plot_screenshot.png saved): 10 pts
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gpcr_hydropathy_profiling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_len = metadata.get('expected_sequence_length', 413)
    true_domains = metadata.get('true_tm_domains', [
        [29, 52], [69, 92], [107, 130], [151, 174], [198, 221], [268, 291], [312, 334]
    ])
    tolerance = metadata.get('tolerance', 15)

    score = 0
    feedback_parts = []
    
    # --- Step 1: Read the basic execution results JSON ---
    result_json = {}
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_json.close()
    try:
        copy_from_env("/tmp/gpcr_hydropathy_profiling_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read result.json: {e}")
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # --- Criterion 6: Visual Evidence (10 pts) ---
    if result_json.get("png_exists", False):
        score += 10
        feedback_parts.append("plot_screenshot.png exists (+10)")
    else:
        feedback_parts.append("plot_screenshot.png MISSING (0)")

    # --- Criteria 1 & 2: CSV Data & Signature (15 + 25 pts) ---
    csv_valid = False
    peaks_found = 0
    
    if result_json.get("csv_exists", False) and result_json.get("csv_size_bytes", 0) > 100:
        tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
        tmp_csv.close()
        try:
            copy_from_env("/home/ga/UGENE_Data/protein_properties/results/hydropathy_profile.csv", tmp_csv.name)
            with open(tmp_csv.name, 'r') as f:
                csv_content = f.read().strip().split('\n')
            
            y_values = []
            for line in csv_content:
                # Find all numbers, parse the hydropathy score (typically the 2nd number)
                nums = re.findall(r'-?\d+\.\d+|-?\d+', line)
                if len(nums) >= 2:
                    y_values.append(float(nums[1]))
                elif len(nums) == 1:
                    y_values.append(float(nums[0]))
            
            # Sequence is 413 AA. A window of 19 produces ~395 data points.
            if 350 < len(y_values) < 450:
                csv_valid = True
                score += 15
                feedback_parts.append(f"CSV data valid, {len(y_values)} rows (+15)")
                
                # Check for KD signature (hydrophobic peaks > 1.0)
                in_peak = False
                for v in y_values:
                    if v > 1.2 and not in_peak:
                        peaks_found += 1
                        in_peak = True
                    elif v < 0.0:
                        in_peak = False
                        
                if 5 <= peaks_found <= 9:
                    score += 25
                    feedback_parts.append(f"Authentic Kyte-Doolittle profile detected: {peaks_found} peaks (+25)")
                else:
                    feedback_parts.append(f"CSV data lacks true GPCR KD signature, found {peaks_found} peaks (0)")
            else:
                feedback_parts.append(f"CSV data length invalid: {len(y_values)} rows (0)")
        except Exception as e:
            feedback_parts.append(f"Error parsing CSV: {e} (0)")
        finally:
            if os.path.exists(tmp_csv.name):
                os.unlink(tmp_csv.name)
    else:
        feedback_parts.append("CSV file MISSING or empty (0)")

    # --- Criteria 3, 4, 5: Report Content & Coordinates (10 + 10 + 30 pts) ---
    if result_json.get("txt_exists", False) and result_json.get("txt_size_bytes", 0) > 10:
        tmp_txt = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
        tmp_txt.close()
        try:
            copy_from_env("/home/ga/UGENE_Data/protein_properties/results/tm_domains_report.txt", tmp_txt.name)
            with open(tmp_txt.name, 'r') as f:
                report_content = f.read()
            
            # C3: Mention of 413 AA length
            if "413" in report_content:
                score += 10
                feedback_parts.append("Report mentions correct length 413 (+10)")
            else:
                feedback_parts.append("Report fails to mention 413 AA length (0)")
                
            # C4 & C5: Extract coordinate ranges
            ranges = re.findall(r'(\d+)\s*[-–to\.]+\s*(\d+)', report_content)
            valid_ranges = [(int(start), int(end)) for start, end in ranges if int(start) < int(end)]
            
            # C4: Mentions 7 domains
            if len(valid_ranges) == 7 or "7" in report_content.split():
                score += 10
                feedback_parts.append(f"Report identified 7 domains (+10)")
            else:
                feedback_parts.append(f"Report listed {len(valid_ranges)} domains, expected 7 (0)")
                
            # C5: Biological Coordinate Accuracy
            matched_domains = 0
            for start, end in valid_ranges:
                # Does this range match any of the true TM domains within tolerance?
                for t_start, t_end in true_domains:
                    if abs(start - t_start) <= tolerance and abs(end - t_end) <= tolerance:
                        matched_domains += 1
                        break # Move to next reported range
            
            # Pro-rate the 30 points based on matched domains (up to 7)
            coord_score = int((min(matched_domains, 7) / 7.0) * 30)
            score += coord_score
            if matched_domains > 0:
                feedback_parts.append(f"Biological coordinates: {matched_domains}/7 accurate (+{coord_score})")
            else:
                feedback_parts.append("Biological coordinates: None matched ground truth (0)")
                
        except Exception as e:
            feedback_parts.append(f"Error reading report: {e} (0)")
        finally:
            if os.path.exists(tmp_txt.name):
                os.unlink(tmp_txt.name)
    else:
        feedback_parts.append("tm_domains_report.txt MISSING (0)")

    # Decide pass/fail
    key_criteria_met = csv_valid and (peaks_found >= 5)
    passed = (score >= 65) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }