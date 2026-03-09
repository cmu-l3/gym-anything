#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_comparison(traj, env_info, task_info):
    """
    Verify the model comparison task.
    
    Criteria:
    1. Output file exists and was created during task (20 pts)
    2. Model 1 (Linear) AIC/BIC values correct (20 pts)
    3. Model 2 (Quadratic) AIC/BIC values correct (20 pts)
    4. Model 3 (Sqrt) AIC/BIC values correct (20 pts)
    5. Correct preferred models identified (20 pts)
    
    Tolerance: +/- 2.0 (AIC/BIC definitions can vary slightly by software implementation,
    though gretl to gretl comparison should be exact).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence & Timestamp
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file model_comparison.txt not found"}
    
    if not result.get("file_created_during_task", False):
        feedback.append("Warning: Output file timestamp indicates it wasn't modified during this session.")
        # We penalize but don't fail immediately if content is perfect (could be clock skew edge case)
        score += 5 
    else:
        score += 20
        feedback.append("Output file created successfully.")

    content = result.get("output_content", "")
    gt = result.get("ground_truth", {})
    
    # Pre-extract all numbers from content for fuzzy matching
    # Pattern: capture floats like 123.45, -123.45
    content_nums = [float(x) for x in re.findall(r'-?\d+\.\d+', content)]
    
    tolerance = task_info.get("metadata", {}).get("tolerance", 2.0)
    
    def check_values(label, aic_key, bic_key):
        gt_aic = gt.get(aic_key)
        gt_bic = gt.get(bic_key)
        
        if gt_aic is None or gt_bic is None:
            return 0, f"Ground truth for {label} missing."
            
        # Check if numbers exist in content within tolerance
        aic_found = any(abs(n - gt_aic) <= tolerance for n in content_nums)
        bic_found = any(abs(n - gt_bic) <= tolerance for n in content_nums)
        
        pts = 0
        msg = []
        if aic_found:
            pts += 10
        else:
            msg.append(f"{label} AIC missing/incorrect (Expected ~{gt_aic:.2f})")
            
        if bic_found:
            pts += 10
        else:
            msg.append(f"{label} BIC missing/incorrect (Expected ~{gt_bic:.2f})")
            
        return pts, ", ".join(msg) if msg else f"{label} values correct."

    # 3. Verify Model Values
    # Model 1
    pts1, msg1 = check_values("Linear", "aic1", "bic1")
    score += pts1
    feedback.append(msg1)
    
    # Model 2
    pts2, msg2 = check_values("Quadratic", "aic2", "bic2")
    score += pts2
    feedback.append(msg2)
    
    # Model 3
    pts3, msg3 = check_values("Sqrt", "aic3", "bic3")
    score += pts3
    feedback.append(msg3)
    
    # 4. Verify Preferred Model Identification
    # Determine winner from GT
    try:
        # Create list of (value, model_name_regex)
        aics = [
            (gt["aic1"], r"linear|model\s*1"),
            (gt["aic2"], r"quadratic|model\s*2"),
            (gt["aic3"], r"sqrt|square\s*root|model\s*3")
        ]
        bics = [
            (gt["bic1"], r"linear|model\s*1"),
            (gt["bic2"], r"quadratic|model\s*2"),
            (gt["bic3"], r"sqrt|square\s*root|model\s*3")
        ]
        
        best_aic_idx = aics.index(min(aics, key=lambda x: x[0]))
        best_bic_idx = bics.index(min(bics, key=lambda x: x[0]))
        
        aic_regex = aics[best_aic_idx][1]
        bic_regex = bics[best_bic_idx][1]
        
        # Search for statements like "AIC preferred: Model 2"
        # We look for lines containing "AIC" and "preferred/best/lowest" and the model name
        content_lower = content.lower()
        
        aic_pref_correct = False
        bic_pref_correct = False
        
        # Simple proximity check: Does "AIC" appear near "Model X" or "Linear/Quad"?
        # And "prefer/best"?
        
        if re.search(fr"aic.*(prefer|best|low|select).*({aic_regex})", content_lower) or \
           re.search(fr"({aic_regex}).*(prefer|best|low|select).*aic", content_lower):
            aic_pref_correct = True
            
        if re.search(fr"bic.*(prefer|best|low|select).*({bic_regex})", content_lower) or \
           re.search(fr"({bic_regex}).*(prefer|best|low|select).*bic", content_lower):
            bic_pref_correct = True
            
        if aic_pref_correct:
            score += 10
            feedback.append("AIC preferred model correctly identified.")
        else:
            feedback.append("Failed to identify AIC preferred model.")

        if bic_pref_correct:
            score += 10
            feedback.append("BIC preferred model correctly identified.")
        else:
            feedback.append("Failed to identify BIC preferred model.")
            
    except Exception as e:
        feedback.append(f"Error verifying preferences: {e}")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }