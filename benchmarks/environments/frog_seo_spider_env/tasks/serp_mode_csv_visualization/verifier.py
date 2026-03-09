#!/usr/bin/env python3
"""
Verifier for SERP Mode Bulk Snippet Visualization task.

Verifies that:
1. Screaming Frog was used and running.
2. A new CSV export file was created during the task.
3. The export contains data matching the input CSV (anti-gaming: verifying correct data source).
4. The export contains SERP-specific columns (Pixel Width/Truncation) indicating correct mode usage.
"""

import json
import os
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_serp_mode_visualization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_row_count = metadata.get('expected_row_count', 10)
    expected_title_fragment = metadata.get('expected_title_fragment', "The Ultimate Guide to SEO that is Definitely Too Long")
    # Screaming Frog column names can vary slightly by version, checking for keywords
    serp_keywords = ["pixel", "width", "truncated", "px"]

    feedback_parts = []
    score = 0
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify App Running (10 pts)
    if result.get("app_running", False):
        score += 10
        feedback_parts.append("Screaming Frog was running.")
    else:
        feedback_parts.append("Screaming Frog was NOT running.")

    # 3. Verify File Creation (30 pts)
    if result.get("file_found", False):
        score += 30
        feedback_parts.append("New export file created.")
        
        # 4. Verify Content (60 pts total)
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            # Copy the exported CSV for analysis
            copy_from_env("/tmp/exported_serp_data.csv", temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                reader = csv.reader(f)
                headers = next(reader, [])
                rows = list(reader)
                
                # Check A: SERP Specific Columns (20 pts)
                # Look for columns like "Title Width (pixels)" or "Title Truncated"
                header_str = " ".join(headers).lower()
                serp_col_found = any(k in header_str for k in serp_keywords)
                
                if serp_col_found:
                    score += 20
                    feedback_parts.append("Export contains SERP analysis columns (Pixel Width/Truncation).")
                else:
                    feedback_parts.append("Export missing SERP analysis columns. Did you use SERP Mode export?")

                # Check B: Data Integrity (Source Match) (20 pts)
                # Check if the specific long title from input exists in output
                content_match = False
                for row in rows:
                    if any(expected_title_fragment in cell for cell in row):
                        content_match = True
                        break
                
                if content_match:
                    score += 20
                    feedback_parts.append("Export contains correct draft metadata from input file.")
                else:
                    feedback_parts.append("Export does NOT contain the expected input data.")

                # Check C: Row Count (20 pts)
                # Should be 10 rows matching the 10 input items
                # Allow slight variance if header handling is weird, but exact is best
                if abs(len(rows) - expected_row_count) <= 1:
                    score += 20
                    feedback_parts.append(f"Row count correct ({len(rows)}).")
                else:
                    feedback_parts.append(f"Row count mismatch (Found {len(rows)}, Expected ~{expected_row_count}).")

        except Exception as e:
            feedback_parts.append(f"Failed to analyze CSV content: {str(e)}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    else:
        feedback_parts.append("No new export file found.")

    # Final Score Calculation
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }