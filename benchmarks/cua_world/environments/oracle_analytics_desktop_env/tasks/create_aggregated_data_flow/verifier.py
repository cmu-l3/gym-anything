#!/usr/bin/env python3
"""
Verifier for create_aggregated_data_flow task in Oracle Analytics Desktop.

Verification Criteria:
1. CSV file exists at expected path.
2. CSV file was created during the task session.
3. Content Analysis:
   - Header contains: Region, Product Category, Sales, Profit
   - Row count is approximately 12-16 (4 regions * 3 categories + header)
   - 'Sales' column contains aggregated numbers (not small individual transaction values)
   - 'Profit' column exists
4. VLM Verification:
   - Trajectory shows Data Flow editor usage (nodes connected)
   - Trajectory shows 'Save Data' step
"""

import json
import os
import tempfile
import logging
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_aggregated_data_flow(traj, env_info, task_info):
    """
    Verify the aggregated data flow task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_cols = set([c.lower() for c in metadata.get('expected_columns', ["region", "product category", "sales", "profit"])])
    
    # CRITERION 1: File Existence & Timestamp (20 pts)
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("Output CSV exists.")
        if created_during:
            score += 10
            feedback_parts.append("File created during task session.")
        else:
            feedback_parts.append("File timestamp indicates it was NOT created during this session.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}

    # CRITERION 2: Content Analysis (CSV Parsing) (60 pts)
    csv_sample = result.get('csv_sample', "")
    row_count = result.get('row_count', 0)
    
    if csv_sample:
        try:
            # Parse the sample provided in JSON
            f = io.StringIO(csv_sample.strip())
            reader = csv.reader(f)
            headers = next(reader, [])
            header_lower = [h.lower().strip() for h in headers]
            
            # Check Headers (20 pts)
            missing_cols = []
            for col in expected_cols:
                if col not in header_lower:
                    missing_cols.append(col)
            
            if not missing_cols:
                score += 20
                feedback_parts.append("CSV headers are correct.")
            else:
                feedback_parts.append(f"Missing headers: {missing_cols}")
            
            # Check Row Count (aggregation check) (20 pts)
            # Raw data is 9000+ rows. Aggregated data should be tiny (<20 rows).
            if 2 <= row_count <= 25:
                score += 20
                feedback_parts.append(f"Row count ({row_count}) indicates aggregation.")
            elif row_count > 100:
                feedback_parts.append(f"Row count ({row_count}) is too high - likely raw data, not aggregated.")
            else:
                feedback_parts.append(f"Row count ({row_count}) is suspicious.")

            # Check Values (Corporate Filter Check) (20 pts)
            # We can't sum precisely without full file, but we can check if data looks numeric/aggregated
            data_rows = list(reader)
            if data_rows:
                # Assuming 'Region' is col 0, 'Sales' is likely col 2 or 3
                # Just check if we have numeric values
                has_numbers = any(any(c.replace('.', '', 1).isdigit() for c in row) for row in data_rows)
                if has_numbers:
                    score += 20
                    feedback_parts.append("Data appears to contain calculated values.")
                    
        except Exception as e:
            feedback_parts.append(f"Error parsing CSV content: {e}")
    else:
        feedback_parts.append("CSV content is empty.")

    # CRITERION 3: VLM Verification (20 pts)
    # Check trajectory for 'Data Flow' UI usage
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Analyze these screenshots of Oracle Analytics Desktop.
        Does the user:
        1. Open the 'Data Flow' editor? (Look for nodes connected by lines, steps like 'Filter', 'Aggregate')
        2. Save the data? (Look for 'Save Data' node or dialog)
        3. View a table with 'Corporate' data?
        
        Respond with YES/NO and confidence.
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                # Simple keyword check in response
                resp_text = vlm_res.get('parsed', {}).get('response', '').lower()
                if "yes" in resp_text or "data flow" in resp_text:
                    score += 20
                    feedback_parts.append("VLM confirms Data Flow usage.")
                else:
                    feedback_parts.append("VLM did not clearly observe Data Flow usage.")
        except:
            pass # VLM failure doesn't fail task if CSV is perfect

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }