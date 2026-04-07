#!/usr/bin/env python3
"""
Verifier for CCAM Procedure Code Analysis Report task.

Verifies:
1. Existence and freshness of report and schema files.
2. Accuracy of reported statistics (Total Codes, Table Count) against ground truth.
3. Validity of sampled procedure codes.
4. Correct formatting of the report.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ccam_procedure_report(traj, env_info, task_info):
    """
    Verify the agent's CCAM report against database ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Create temp directory for all files
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Fetch Task Result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

        # 2. Fetch Agent's Files
        schema_path = os.path.join(temp_dir, "ccam_schema.txt")
        report_path = os.path.join(temp_dir, "ccam_report.txt")
        
        try:
            if result['schema_file']['exists']:
                copy_from_env(result['schema_file']['path'], schema_path)
            if result['report_file']['exists']:
                copy_from_env(result['report_file']['path'], report_path)
        except Exception:
            pass # We handle missing files in scoring

        # 3. Fetch Ground Truth Files
        gt_table_count_path = os.path.join(temp_dir, "gt_table_count.txt")
        gt_total_codes_path = os.path.join(temp_dir, "gt_total_codes.txt")
        gt_sample_path = os.path.join(temp_dir, "gt_sample_20.txt")
        gt_tables_path = os.path.join(temp_dir, "gt_tables.txt")

        try:
            copy_from_env("/tmp/task_result_gt/table_count.txt", gt_table_count_path)
            copy_from_env("/tmp/task_result_gt/total_codes.txt", gt_total_codes_path)
            copy_from_env("/tmp/task_result_gt/sample_20.txt", gt_sample_path)
            copy_from_env("/tmp/task_result_gt/tables.txt", gt_tables_path)
        except Exception as e:
            logger.warning(f"Could not fetch some ground truth files: {e}")

        # Load Ground Truth Data
        try:
            with open(gt_table_count_path, 'r') as f:
                gt_table_count = int(f.read().strip())
            with open(gt_total_codes_path, 'r') as f:
                gt_total_codes = int(f.read().strip())
            with open(gt_sample_path, 'r') as f:
                gt_sample_content = f.read()
            with open(gt_tables_path, 'r') as f:
                gt_table_names = [line.strip() for line in f.readlines() if line.strip()]
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error reading ground truth: {e}"}

        # ============================================================
        # Scoring Logic
        # ============================================================

        # Criterion 1: Schema File (10 pts)
        if result['schema_file']['exists'] and result['schema_file']['size_bytes'] > 100:
            if result['schema_file']['created_during_task']:
                score += 10
                feedback_parts.append("Schema file created successfully")
            else:
                score += 5
                feedback_parts.append("Schema file exists but timestamp is old")
        else:
            feedback_parts.append("Schema file missing or empty")

        # Criterion 2: Report File Existence (10 pts)
        if result['report_file']['exists'] and result['report_file']['size_bytes'] > 200:
            if result['report_file']['created_during_task']:
                score += 10
                feedback_parts.append("Report file created successfully")
            else:
                score += 5
                feedback_parts.append("Report file exists but timestamp is old")
        else:
            feedback_parts.append("Report file missing or too small")
            # If report is missing, we can't check content
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Read Report Content
        try:
            with open(report_path, 'r', encoding='utf-8', errors='replace') as f:
                report_content = f.read()
                report_lines = report_content.splitlines()
        except Exception:
            return {"passed": False, "score": score, "feedback": "Failed to read report content"}

        # Criterion 3: Header Format (5 pts)
        if len(report_lines) > 0 and "CCAM Procedure Code Report" in report_lines[0]:
            score += 5
        else:
            feedback_parts.append("Incorrect report header")

        # Criterion 4: Total Code Count Accuracy (20 pts)
        # Look for "Total procedure codes: <N>"
        code_count_match = re.search(r"Total procedure codes:\s*(\d+)", report_content, re.IGNORECASE)
        if code_count_match:
            reported_count = int(code_count_match.group(1))
            # 5% tolerance
            tolerance = max(1, int(gt_total_codes * 0.05))
            diff = abs(reported_count - gt_total_codes)
            if diff <= tolerance:
                score += 20
                feedback_parts.append(f"Total count accurate ({reported_count})")
            else:
                feedback_parts.append(f"Total count inaccurate (Reported: {reported_count}, Actual: {gt_total_codes})")
        else:
            feedback_parts.append("Total procedure codes count not found in report")

        # Criterion 5: Table Count Accuracy (10 pts)
        table_count_match = re.search(r"Number of tables:\s*(\d+)", report_content, re.IGNORECASE)
        if table_count_match:
            reported_tables = int(table_count_match.group(1))
            if reported_tables == gt_table_count:
                score += 10
                feedback_parts.append("Table count accurate")
            else:
                feedback_parts.append(f"Table count incorrect (Reported: {reported_tables}, Actual: {gt_table_count})")
        else:
            feedback_parts.append("Number of tables not found in report")

        # Criterion 6: Sample Procedures Verification (20 pts)
        # Check if sampled codes from report exist in our ground truth sample
        # Note: Ground truth sample might be a subset, so we check if report codes look valid
        # A better check: The GT sample file contains raw "Code\tDescription".
        
        sample_section = False
        valid_samples = 0
        samples_checked = 0
        
        for line in report_lines:
            if "=== Sample Procedures" in line:
                sample_section = True
                continue
            if "=== Schema Summary" in line:
                sample_section = False
                break
            
            if sample_section and "|" in line:
                samples_checked += 1
                code = line.split("|")[0].strip()
                # Check if this code appears in the ground truth sample text
                if code and code in gt_sample_content:
                    valid_samples += 1
                elif samples_checked > 20:
                    break

        if samples_checked >= 15 and valid_samples >= 10:
             score += 20
             feedback_parts.append(f"Sample procedures verified ({valid_samples} matches)")
        elif samples_checked > 0:
             score += 10
             feedback_parts.append(f"Sample procedures partially verified ({valid_samples} matches)")
        else:
             feedback_parts.append("Sample procedures section missing or malformed")

        # Criterion 7: Schema Coverage (15 pts)
        # Check if actual table names appear in the Schema Summary section
        schema_section = False
        tables_found = 0
        
        for line in report_lines:
            if "=== Schema Summary" in line:
                schema_section = True
                continue
            
            if schema_section and ":" in line:
                # Basic check: does the line contain a known table name?
                for tbl in gt_table_names:
                    if tbl in line:
                        tables_found += 1
                        break
        
        # Calculate coverage percentage
        coverage = 0
        if gt_table_count > 0:
            coverage = (tables_found / gt_table_count) * 100
        
        if coverage >= 80:
            score += 15
            feedback_parts.append("Schema summary covers >80% of tables")
        elif coverage >= 50:
            score += 8
            feedback_parts.append("Schema summary covers >50% of tables")
        else:
            feedback_parts.append("Schema summary poor coverage")

        # Criterion 8: Formatting (10 pts)
        format_ok = True
        if "=== Sample Procedures" not in report_content: format_ok = False
        if "=== Schema Summary" not in report_content: format_ok = False
        if "|" not in report_content: format_ok = False
        
        if format_ok:
            score += 10
        else:
            feedback_parts.append("Report formatting issues (missing headers or separators)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }