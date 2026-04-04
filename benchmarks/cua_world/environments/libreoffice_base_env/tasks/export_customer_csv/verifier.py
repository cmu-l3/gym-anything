#!/usr/bin/env python3
"""
Verifier for export_customer_csv task.
Verifies that the agent correctly queried the database and exported the results to CSV.
"""

import json
import os
import csv
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_customer_csv(traj, env_info, task_info):
    """
    Verify the exported CSV file for correctness.
    
    Criteria:
    1. File exists and was created during the task.
    2. Header row matches expected columns.
    3. Row count is exactly 59 (one per customer).
    4. Data is sorted by TotalSpending descending.
    5. Grand total matches expected database total (approx 2328.60).
    6. Top spender matches ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_header = metadata.get('expected_header', [])
    expected_row_count = metadata.get('expected_row_count', 59)
    expected_total_sum = metadata.get('expected_total_sum', 2328.60)
    tolerance = metadata.get('tolerance', 0.1)

    # Load task result metadata
    task_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", task_result_file.name)
        with open(task_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(task_result_file.name):
            os.unlink(task_result_file.name)

    # Basic Checks
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during this task session."}

    # Retrieve the actual CSV content
    csv_file = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(task_result["output_path"], csv_file.name)
        
        with open(csv_file.name, 'r', encoding='utf-8', errors='replace') as f:
            # Detect dialect (in case they used semicolons or tabs)
            try:
                content = f.read(1024)
                f.seek(0)
                dialect = csv.Sniffer().sniff(content)
            except csv.Error:
                dialect = 'excel' # Fallback
            
            reader = csv.reader(f, dialect)
            rows = list(reader)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File created but could not be parsed as CSV: {str(e)}"}
    finally:
        if os.path.exists(csv_file.name):
            os.unlink(csv_file.name)

    score = 15 # Points for creating a valid file
    feedback = []

    # Verify Header (10 pts)
    if not rows:
        return {"passed": False, "score": score, "feedback": "CSV file is empty."}
    
    header = [h.strip().replace('"', '') for h in rows[0]]
    # Normalize headers for comparison (case-insensitive)
    norm_header = [h.lower() for h in header]
    norm_expected = [h.lower() for h in expected_header]
    
    # Check if all expected columns are present (order checked loosely)
    missing_cols = [col for col in norm_expected if col not in norm_header]
    
    if not missing_cols:
        score += 10
        feedback.append("Header row correct.")
        
        # Identify indices for key columns
        try:
            spending_idx = norm_header.index("totalspending")
            id_idx = norm_header.index("customerid")
        except ValueError:
             # Should be caught by missing_cols check, but safety fallback
             spending_idx = -1
             id_idx = -1
    else:
        feedback.append(f"Missing columns in header: {', '.join(missing_cols)}")
        # If headers are missing, we might not be able to verify data accurately
        spending_idx = -1

    # Verify Row Count (15 pts)
    data_rows = rows[1:]
    row_count = len(data_rows)
    if row_count == expected_row_count:
        score += 15
        feedback.append(f"Correct row count ({row_count}).")
    else:
        feedback.append(f"Incorrect row count: {row_count} (expected {expected_row_count}).")

    # Verify Data Content
    if spending_idx != -1 and len(data_rows) > 0:
        total_spending_sum = 0.0
        sorted_correctly = True
        previous_spending = float('inf')
        
        try:
            for i, row in enumerate(data_rows):
                if len(row) <= spending_idx:
                    continue
                
                # Parse spending value
                try:
                    val_str = row[spending_idx].replace('$', '').replace(',', '').strip()
                    val = float(val_str)
                except ValueError:
                    continue
                
                total_spending_sum += val
                
                # Check sort order (descending)
                if val > previous_spending + 0.01: # Small epsilon for float comparison
                    sorted_correctly = False
                previous_spending = val

            # Verify Sum (25 pts)
            diff = abs(total_spending_sum - expected_total_sum)
            if diff <= tolerance * expected_total_sum: # e.g. within 5%? metadata says 0.05
                # Tighter check: metadata tolerance is likely absolute or small relative
                # The prompt set tolerance 0.05. Let's assume absolute tolerance of ~1.0 for float issues
                if diff < 1.0:
                    score += 25
                    feedback.append(f"Total spending sum correct ({total_spending_sum:.2f}).")
                else:
                    score += 15 # Partial credit if close
                    feedback.append(f"Total spending sum close ({total_spending_sum:.2f}).")
            else:
                feedback.append(f"Total spending sum mismatch: {total_spending_sum:.2f} (expected {expected_total_sum}).")

            # Verify Sorting (10 pts)
            if sorted_correctly:
                score += 10
                feedback.append("Data sorted correctly (descending).")
            else:
                feedback.append("Data NOT sorted by spending descending.")
                
            # Verify Top Spender (15 pts)
            # Top spender in Chinook is typically Helena Holý (ID 6, ~49.62)
            top_row = data_rows[0]
            if len(top_row) > spending_idx:
                try:
                    top_val = float(top_row[spending_idx].replace(',', ''))
                    # Check against metadata
                    if abs(top_val - 49.62) < 0.1:
                        score += 15
                        feedback.append("Top spender value correct.")
                    else:
                        feedback.append(f"Top spender value incorrect: {top_val}.")
                except:
                    pass

        except Exception as e:
            feedback.append(f"Error parsing data rows: {str(e)}")
            
    # Structure/Format bonus (10 pts)
    if score >= 40:
        score += 10 # CSV structure was parseable and contained data

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }