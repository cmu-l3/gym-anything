#!/usr/bin/env python3
"""
Verifier for GARCH Volatility Inflation task.

Verification Logic:
1. Script file exists and contains expected commands (garch, open, etc.).
2. Output text file exists and contains GARCH model results (coefficients, log-likelihood).
3. Output CSV file exists and contains data (checks row count).
4. Validation Run: The script was re-executed successfully in the export phase (ensures reproducibility).
5. Anti-gaming: Files must be created after task start.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_garch_volatility_inflation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    result_json_path = "/tmp/task_result.json"
    validation_log_path = "/tmp/task_validation.log"
    
    # Temp files for copying from container
    local_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    local_log = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    local_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp').name
    local_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    local_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name

    files_to_clean = [local_result, local_log, local_script, local_txt, local_csv]

    score = 0
    max_score = 100
    feedback_parts = []
    
    try:
        # 1. Load Result JSON
        try:
            copy_from_env(result_json_path, local_result)
            with open(local_result, 'r') as f:
                res = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        script_info = res.get('script_file', {})
        txt_info = res.get('output_txt', {})
        csv_info = res.get('output_csv', {})
        validation_success = res.get('validation_run_success', False)

        # 2. Check Script File (20 pts)
        if script_info.get('exists'):
            score += 5
            if script_info.get('fresh'):
                score += 5
            
            # Analyze script content
            try:
                copy_from_env(script_info['path'], local_script)
                with open(local_script, 'r') as f:
                    script_content = f.read().lower()
                
                if 'garch' in script_content:
                    score += 5
                else:
                    feedback_parts.append("Script missing 'garch' command")

                if 'usa.gdt' in script_content or 'open' in script_content:
                    score += 5
                else:
                    feedback_parts.append("Script does not appear to open a dataset")
            except:
                feedback_parts.append("Could not read script content")
        else:
            feedback_parts.append("Script file missing")

        # 3. Check Output Text File (30 pts)
        if txt_info.get('exists'):
            score += 5
            if txt_info.get('fresh'):
                score += 5
            
            # Analyze output content for GARCH results
            try:
                copy_from_env(txt_info['path'], local_txt)
                with open(local_txt, 'r') as f:
                    txt_content = f.read()
                
                # Look for GARCH specific terms in output
                garch_terms = re.search(r'(GARCH|garch|ARCH|arch)', txt_content, re.IGNORECASE)
                coeffs = re.search(r'(alpha|beta|omega)', txt_content, re.IGNORECASE)
                loglik = re.search(r'(Log-likelihood|lnL)', txt_content, re.IGNORECASE)

                if garch_terms: score += 10
                else: feedback_parts.append("Output text missing GARCH terms")
                
                if coeffs and loglik: score += 10
                else: feedback_parts.append("Output text missing coefficients/log-likelihood")
            except:
                feedback_parts.append("Could not read output text")
        else:
            feedback_parts.append("Output text file missing")

        # 4. Check CSV File (20 pts)
        if csv_info.get('exists'):
            score += 10
            if csv_info.get('fresh'):
                score += 5
            
            try:
                copy_from_env(csv_info['path'], local_csv)
                with open(local_csv, 'r') as f:
                    lines = f.readlines()
                    # Expect header + data (approx 100 rows for quarterly data)
                    if len(lines) > 50:
                        score += 5
                    else:
                        feedback_parts.append(f"CSV has too few rows ({len(lines)})")
            except:
                feedback_parts.append("Could not read CSV file")
        else:
            feedback_parts.append("Output CSV file missing")

        # 5. Validation Run Check (30 pts)
        # This confirms the script is actually runnable and produces output
        if validation_success:
            score += 30
            feedback_parts.append("Script passed validation re-run")
        else:
            feedback_parts.append("Script failed validation re-run (or generated errors)")
            # Try to read log to give better feedback
            try:
                copy_from_env(validation_log_path, local_log)
                with open(local_log, 'r') as f:
                    log_tail = f.read()[-300:]
                    logger.info(f"Validation Log Tail: {log_tail}")
            except:
                pass

        # Final Evaluation
        passed = score >= 70
        feedback = "; ".join(feedback_parts) if feedback_parts else "Task completed successfully"

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": res
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        for f in files_to_clean:
            if os.path.exists(f):
                os.unlink(f)