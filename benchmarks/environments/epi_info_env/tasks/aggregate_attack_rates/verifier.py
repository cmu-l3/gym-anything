import json
import os
import pandas as pd
import logging
import tempfile
from io import StringIO

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aggregate_attack_rates(traj, env_info, task_info):
    """
    Verify the Aggregate Attack Rates task.
    
    Checks:
    1. CSV file exists and was created during the task.
    2. CSV contains expected headers (AgeGroup, Ill, Count).
    3. CSV content matches Oswego dataset aggregation logic.
    """
    
    # 1. Setup and retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', r"C:\Users\Docker\Documents\AgeIllnessSummary.csv")
    
    # Load task result metadata (from export_result.ps1)
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path inside container where export_result.ps1 saved the JSON
        # Note: Windows path in container needs to be mapped. 
        # Usually copy_from_env handles the path mapping or we use the linux mount path if known.
        # Assuming the env mapping or standard /tmp location if forwarded.
        # But export_result.ps1 saved to C:\Users\Docker\AppData\Local\Temp\task_result.json
        # We need to use the path that copy_from_env understands. 
        # In dockur/windows, typically C: is mounted or accessible.
        # Let's try the full path.
        copy_from_env(r"C:\Users\Docker\AppData\Local\Temp\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
        # Proceeding to check file directly if JSON fails
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # Criteria 1: File Existence & Anti-Gaming (20 pts)
    output_exists = task_result.get('output_exists', False)
    created_during = task_result.get('file_created_during_task', False)
    
    if output_exists:
        if created_during:
            score += 20
            feedback.append("Output file created successfully.")
        else:
            score += 5
            feedback.append("Output file exists but has old timestamp (pre-task?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}

    # Criteria 2: Content Analysis (80 pts)
    # Copy the actual CSV file
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_path, temp_csv.name)
        
        # Try reading CSV with pandas
        try:
            df = pd.read_csv(temp_csv.name)
            
            # Normalize column names (case insensitive)
            df.columns = [c.lower() for c in df.columns]
            
            # Check headers
            has_age = any('age' in c for c in df.columns)
            has_ill = any('ill' in c for c in df.columns)
            has_count = any(c in ['count', 'freq', 'frequency', 'n'] for c in df.columns)
            
            if has_age and has_ill and has_count:
                score += 20
                feedback.append("CSV has correct columns.")
            else:
                feedback.append(f"Missing required columns. Found: {list(df.columns)}")
            
            # Check Recode Logic (30 pts)
            # Expected categories: 0-19, 20-39, 40-59, 60+
            age_col = next((c for c in df.columns if 'age' in c), None)
            if age_col:
                unique_ages = set(df[age_col].astype(str).str.strip())
                expected_groups = {'0-19', '20-39', '40-59', '60+'}
                
                # Check intersection
                found_groups = unique_ages.intersection(expected_groups)
                if len(found_groups) == 4:
                    score += 30
                    feedback.append("Recoding logic appears correct (all 4 age groups found).")
                elif len(found_groups) >= 2:
                    score += 15
                    feedback.append(f"Partial recoding match. Found: {found_groups}")
                else:
                    feedback.append(f"Incorrect age groups. Found: {unique_ages}")
            
            # Check Data Aggregation (30 pts)
            # Total count should be 75 (Oswego dataset size)
            count_col = next((c for c in df.columns if c in ['count', 'freq', 'frequency', 'n']), None)
            if count_col:
                total_count = df[count_col].sum()
                if 70 <= total_count <= 80: # Allow slight variance if dataset version differs
                    score += 30
                    feedback.append(f"Total record count is correct ({total_count}).")
                else:
                    score += 10
                    feedback.append(f"Total count {total_count} seems off (Expected ~75).")
            
        except Exception as e:
            feedback.append(f"Failed to parse CSV: {str(e)}")
            
    except Exception as e:
        feedback.append(f"Failed to retrieve CSV file: {str(e)}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }