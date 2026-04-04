#!/usr/bin/env python3
"""
Verifier for CSV Transformation Validation task
"""

import sys
import os
import logging
import tempfile
import shutil
import csv
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_csv_rows(filepath):
    """
    Read CSV file and return normalized rows for comparison
    Handles minor whitespace differences
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = []
            for row in reader:
                # Normalize each field by stripping whitespace
                normalized = {k.strip(): v.strip() for k, v in row.items()}
                rows.append(normalized)
            return rows
    except Exception as e:
        logger.error(f"Error reading CSV {filepath}: {e}")
        return None


def compare_csv_files(file1, file2):
    """
    Compare two CSV files, returning (match, differences)
    """
    rows1 = normalize_csv_rows(file1)
    rows2 = normalize_csv_rows(file2)
    
    if rows1 is None or rows2 is None:
        return False, ["Failed to read one or both CSV files"]
    
    if len(rows1) != len(rows2):
        return False, [f"Different number of rows: {len(rows1)} vs {len(rows2)}"]
    
    differences = []
    for i, (r1, r2) in enumerate(zip(rows1, rows2)):
        if r1 != r2:
            # Find specific field differences
            for key in r1.keys():
                if key in r2 and r1[key] != r2[key]:
                    differences.append(f"Row {i+1}, field '{key}': '{r1[key]}' != '{r2[key]}'")
    
    return len(differences) == 0, differences


def verify_csv_validation(traj, env_info, task_info):
    """
    Verify CSV transformation validation task completion.
    
    Checks:
    1. actual_output.csv was generated (script executed)
    2. Output content matches expected_output.csv exactly
    3. validation_passed.txt was created with correct content
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='csv_verify_')
    
    try:
        results_dir = Path("/tmp/task_results")
        
        # Copy result files from container to temp directory
        actual_output_local = os.path.join(temp_dir, "actual_output.csv")
        expected_output_local = os.path.join(temp_dir, "expected_output.csv")
        validation_file_local = os.path.join(temp_dir, "validation_passed.txt")
        
        criteria_passed = 0
        feedback_parts = []
        metadata = {
            "script_executed": False,
            "output_generated": False,
            "output_correct": False,
            "validation_confirmed": False
        }
        
        # Check 1: actual_output.csv was generated
        try:
            copy_from_env("/tmp/task_results/actual_output.csv", actual_output_local)
            if os.path.exists(actual_output_local) and os.path.getsize(actual_output_local) > 0:
                criteria_passed += 1
                metadata["script_executed"] = True
                metadata["output_generated"] = True
                feedback_parts.append("✅ Script executed: actual_output.csv generated")
            else:
                feedback_parts.append("❌ actual_output.csv not found or empty")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "Task not completed: transformation script was not executed. " + 
                               "Run: python parse_orders.py sample_input.csv actual_output.csv",
                    "metadata": metadata
                }
        except Exception as e:
            feedback_parts.append(f"❌ Failed to retrieve actual_output.csv: {str(e)}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Task not completed: actual_output.csv was not generated",
                "metadata": metadata
            }
        
        # Check 2: Output matches expected output
        try:
            copy_from_env("/tmp/task_results/expected_output.csv", expected_output_local)
            
            if not os.path.exists(expected_output_local):
                feedback_parts.append("⚠️ Expected output file not available for comparison")
            else:
                match, differences = compare_csv_files(actual_output_local, expected_output_local)
                
                if match:
                    criteria_passed += 2  # Worth more points
                    metadata["output_correct"] = True
                    feedback_parts.append("✅ Output matches expected result perfectly")
                else:
                    metadata["output_correct"] = False
                    # Show first few differences
                    diff_summary = "; ".join(differences[:3])
                    if len(differences) > 3:
                        diff_summary += f" ... and {len(differences) - 3} more"
                    feedback_parts.append(f"❌ Output differs from expected: {diff_summary}")
        except Exception as e:
            logger.warning(f"Error comparing CSV files: {e}")
            feedback_parts.append(f"⚠️ Could not compare files: {str(e)}")
        
        # Check 3: Validation confirmation file created
        try:
            copy_from_env("/tmp/task_results/validation_passed.txt", validation_file_local)
            
            if os.path.exists(validation_file_local):
                content = read_file_content(validation_file_local).strip()
                
                # Check for expected text (case-insensitive, flexible matching)
                if content and ("matches" in content.lower() or 
                               "passed" in content.lower() or
                               "correct" in content.lower()):
                    criteria_passed += 1
                    metadata["validation_confirmed"] = True
                    feedback_parts.append(f"✅ Validation confirmed: '{content}'")
                else:
                    feedback_parts.append(f"⚠️ Validation file exists but content unexpected: '{content}'")
            else:
                feedback_parts.append("⚠️ validation_passed.txt not created")
        except Exception as e:
            logger.info(f"Validation file not found: {e}")
            feedback_parts.append("⚠️ validation_passed.txt not found")
        
        # Calculate score and determine success
        # Criteria: script_executed (1 pt), output_correct (2 pts), validation_confirmed (1 pt)
        # Total: 4 points possible
        max_score = 4
        score_pct = int((criteria_passed / max_score) * 100)
        
        # Success requires: script executed AND output correct
        passed = metadata["output_generated"] and metadata["output_correct"]
        
        # Bonus: full marks if validation also confirmed
        if passed and metadata["validation_confirmed"]:
            score_pct = 100
        
        feedback = " | ".join(feedback_parts)
        
        if passed:
            return {
                "passed": True,
                "score": score_pct,
                "feedback": f"✅ Task completed successfully! {feedback}",
                "metadata": metadata
            }
        else:
            # Provide helpful guidance based on what's missing
            if not metadata["output_generated"]:
                guidance = "Run the transformation script: python parse_orders.py sample_input.csv actual_output.csv"
            elif not metadata["output_correct"]:
                guidance = "The output doesn't match expected results. Check the transformation logic."
            else:
                guidance = "Create validation_passed.txt to confirm verification."
            
            return {
                "passed": False,
                "score": score_pct,
                "feedback": f"⚠️ Partial completion: {feedback} | Next step: {guidance}",
                "metadata": metadata
            }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "metadata": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
