#!/usr/bin/env python3
"""
Verifier for noise_filter_evaluation task.

Scoring (100 pts total):
1. Output files exist & created during task (5 files * 3 pts) = 15 pts
2. CSV structure is valid (4 rows, correct headers) = 15 pts
3. Filtered images are valid (size check + existence) = 15 pts
4. SNR improvement demonstrated (stats in CSV show filtering worked) = 15 pts
5. StdDev reduction demonstrated (noise reduced) = 10 pts
6. Best filter identified correctly in report = 15 pts
7. Mean intensity preserved (filters didn't destroy data) = 10 pts
8. Report completeness (mentions improvement) = 5 pts

Pass threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_noise_filter_evaluation(traj, env_info, task_info):
    """
    Verifies the noise filter evaluation task using the JSON export from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Retrieve result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/filter_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}

    score = 0
    feedback = []
    
    files = result.get("files", {})
    csv_data = result.get("csv_data", [])
    
    # 1. File Existence & Creation (15 pts)
    files_found = 0
    files_new = 0
    required = ["gaussian_filtered.tif", "median_filtered.tif", "mean_filtered.tif", "filter_comparison.csv", "filter_report.txt"]
    
    for fname in required:
        info = files.get(fname, {})
        if info.get("exists"):
            files_found += 1
            if info.get("modified_after_start"):
                files_new += 1
    
    if files_found == 5:
        score += 5
        feedback.append("All output files present (+5)")
    else:
        feedback.append(f"Missing output files ({files_found}/5 found)")
        
    if files_new == 5:
        score += 10
        feedback.append("All files created during task (+10)")
    elif files_new > 0:
        score += 5
        feedback.append(f"Some files created during task ({files_new}/5) (+5)")

    # 2. CSV Validity (15 pts)
    if result.get("csv_valid"):
        score += 15
        feedback.append("CSV structure and data valid (+15)")
    elif len(csv_data) >= 4:
        score += 10
        feedback.append("CSV has data but may have minor issues (+10)")
    else:
        feedback.append("CSV data incomplete or missing")

    # 3. Image Validity (15 pts)
    # Checked via file size > 10KB (implies actual image content, not empty file)
    valid_imgs = 0
    for img in ["gaussian_filtered.tif", "median_filtered.tif", "mean_filtered.tif"]:
        if files.get(img, {}).get("size", 0) > 10000:
            valid_imgs += 1
    
    if valid_imgs == 3:
        score += 15
        feedback.append("All filtered images valid (+15)")
    else:
        score += valid_imgs * 5
        feedback.append(f"{valid_imgs}/3 images valid (+{valid_imgs * 5})")

    # 4. SNR Improvement (15 pts)
    if result.get("snr_improvement"):
        score += 15
        feedback.append("SNR improvement confirmed for all filters (+15)")
    else:
        feedback.append("SNR improvement not consistent across filters")

    # 5. StdDev Reduction (10 pts)
    if result.get("std_reduction"):
        score += 10
        feedback.append("Noise reduction (StdDev decrease) confirmed (+10)")
    else:
        feedback.append("Noise reduction not consistently detected")

    # 6. Best Filter Identification (15 pts)
    report_content = result.get("report_content", "")
    
    # Find actual best from CSV
    best_filter_csv = "unknown"
    max_snr = -1.0
    for row in csv_data:
        try:
            name = row.get('filter', '').lower()
            snr = float(row.get('snr', 0))
            if name != 'original' and snr > max_snr:
                max_snr = snr
                best_filter_csv = name
        except: pass
        
    if best_filter_csv in report_content and "best" in report_content:
        score += 15
        feedback.append(f"Correctly identified '{best_filter_csv}' as best filter (+15)")
    elif "best" in report_content and result.get("report_valid"):
        # Mentions best but maybe mismatches our calc (could be close)
        score += 10
        feedback.append("Report identifies a best filter, but check logic (+10)")
    else:
        feedback.append("Report does not clearly identify best filter")

    # 7. Mean Preservation (10 pts)
    # Filters should reduce noise (StdDev) but keep signal (Mean) roughly same
    orig_mean = 0
    means_consistent = True
    for row in csv_data:
        if row.get('filter') == 'original':
            try: orig_mean = float(row.get('mean', 0))
            except: pass
            break
            
    if orig_mean > 0:
        for row in csv_data:
            try:
                curr_mean = float(row.get('mean', 0))
                if abs(curr_mean - orig_mean) / orig_mean > 0.2: # >20% deviation
                    means_consistent = False
            except: pass
            
        if means_consistent and len(csv_data) >= 4:
            score += 10
            feedback.append("Mean intensity preserved across filters (+10)")
        else:
            feedback.append("Warning: Significant intensity shift detected in filters")

    # 8. Report Completeness (5 pts)
    if result.get("report_valid"):
        score += 5
        feedback.append("Report format valid (+5)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }