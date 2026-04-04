#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_probit_classification_analysis(traj, env_info, task_info):
    """
    Verify the Probit classification task.
    
    Criteria:
    1. Output files exist and were created during the task (20 pts).
    2. Report file contains a valid classification table (keywords) (30 pts).
    3. Accuracy score file contains a numeric value (20 pts).
    4. The numeric value in the score file matches the value in the report file (30 pts).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Files to retrieve
    files_to_check = {
        "result_json": "/tmp/task_result.json",
        "report_txt": "/home/ga/Documents/gretl_output/classification_report.txt",
        "score_txt": "/home/ga/Documents/gretl_output/accuracy_score.txt"
    }
    
    local_files = {}
    
    # Copy files
    for key, path in files_to_check.items():
        tf = tempfile.NamedTemporaryFile(delete=False)
        try:
            copy_from_env(path, tf.name)
            local_files[key] = tf.name
        except Exception:
            local_files[key] = None
        finally:
            tf.close()

    try:
        # Load Result JSON
        if not local_files["result_json"] or os.path.getsize(local_files["result_json"]) == 0:
            return {"passed": False, "score": 0, "feedback": "Task execution failed (no result metadata)"}
            
        with open(local_files["result_json"], 'r') as f:
            result_meta = json.load(f)

        # 1. Check Files Existence & Timestamp (20 pts)
        report_meta = result_meta.get("report_file", {})
        score_meta = result_meta.get("score_file", {})
        
        if report_meta.get("exists") and report_meta.get("created_during_task"):
            score += 10
            feedback.append("Classification report created.")
        elif report_meta.get("exists"):
            score += 5
            feedback.append("Classification report exists but timestamp is old.")
        else:
            feedback.append("Classification report missing.")

        if score_meta.get("exists") and score_meta.get("created_during_task"):
            score += 10
            feedback.append("Accuracy score file created.")
        elif score_meta.get("exists"):
            score += 5
            feedback.append("Accuracy score file exists but timestamp is old.")
        else:
            feedback.append("Accuracy score file missing.")

        # 2. Analyze Report Content (30 pts)
        extracted_accuracy = None
        if local_files["report_txt"] and os.path.getsize(local_files["report_txt"]) > 0:
            with open(local_files["report_txt"], 'r', errors='ignore') as f:
                content = f.read()
            
            # Look for Probit/Classification keywords
            if "Predicted" in content and "Actual" in content:
                score += 15
                feedback.append("Report format looks correct (Confusion Matrix found).")
            elif "Percent correct" in content:
                score += 10 # Partial credit
                feedback.append("Report mentions percent correct.")
                
            # Try to extract the accuracy percentage
            # Patterns often look like: "Percent correctly predicted = 66.8" or similar
            # Gretl output example: "Percent correctly predicted =  66.80"
            match = re.search(r"Percent correctly predicted\s*[=:]\s*([\d\.]+)", content, re.IGNORECASE)
            if match:
                extracted_accuracy = float(match.group(1))
                score += 15
                feedback.append(f"Found accuracy in report: {extracted_accuracy}%")
            else:
                feedback.append("Could not parse accuracy percentage from report.")
        else:
            feedback.append("Report file is empty or unreadable.")

        # 3. Analyze Score File (20 pts)
        reported_score = None
        if local_files["score_txt"] and os.path.getsize(local_files["score_txt"]) > 0:
            with open(local_files["score_txt"], 'r') as f:
                score_content = f.read().strip()
            
            # Find the first float-like number
            number_match = re.search(r"([\d\.]+)", score_content)
            if number_match:
                try:
                    reported_score = float(number_match.group(1))
                    score += 20
                    feedback.append(f"Score file contains valid number: {reported_score}")
                except ValueError:
                    feedback.append("Score file content is not a valid number.")
            else:
                feedback.append("No number found in score file.")
        else:
            feedback.append("Score file is empty.")

        # 4. Consistency Check (30 pts)
        if extracted_accuracy is not None and reported_score is not None:
            # Allow extracting as decimal (0.668) or percent (66.8)
            # If they match exactly or within tolerance
            
            # Normalize: if reported is < 1 and extracted > 1, multiply reported by 100
            if reported_score < 1.0 and extracted_accuracy > 1.0:
                 normalized_reported = reported_score * 100
            else:
                 normalized_reported = reported_score

            if abs(normalized_reported - extracted_accuracy) < 0.5:
                score += 30
                feedback.append("Reported score matches extraction from report.")
            else:
                feedback.append(f"Mismatch: Report says {extracted_accuracy}, file says {reported_score}.")
        elif extracted_accuracy is None and reported_score is not None:
             # Fallback: check if reported score is in reasonable range for this dataset (approx 66-70%)
             if 60.0 <= reported_score <= 75.0 or 0.60 <= reported_score <= 0.75:
                 score += 15
                 feedback.append("Reported score is within reasonable range for Mroz dataset (fallback check).")

    except Exception as e:
        feedback.append(f"Verification error: {str(e)}")
    finally:
        # Cleanup
        for f in local_files.values():
            if f and os.path.exists(f):
                os.unlink(f)

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }