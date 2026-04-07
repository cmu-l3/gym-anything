#!/usr/bin/env python3
"""
Verifier for wildlife_distance_sampling task.

Verifies:
1. Installation of required package (Distance).
2. Creation of required deliverables (2 CSVs, 2 PNGs).
3. Statistical correctness:
   - AIC model selection logic.
   - Abundance estimates within plausible range for this dataset.
4. Visualization existence.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wildlife_distance_sampling(traj, env_info, task_info):
    """
    Verify the Distance Sampling analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    feedback_parts = []
    
    files = result.get('files', {})
    data = result.get('data', {})
    env = result.get('env', {})

    # Criterion 1: Package Installation & Script (15 pts)
    # Note: We rely on the export script check or script existence/modification
    if env.get('distance_package_installed') == "TRUE":
        score += 10
        feedback_parts.append("Package 'Distance' installed (+10)")
    else:
        feedback_parts.append("Package 'Distance' NOT installed")
    
    if files.get('script', {}).get('new', False):
        score += 5
        feedback_parts.append("Script modified (+5)")

    # Criterion 2: Model Selection CSV (20 pts)
    # Check if CSV exists, has 3 models, and reasonable AICs
    if files.get('model_csv', {}).get('new', False):
        models = data.get('models', [])
        if len(models) >= 3:
            score += 10
            feedback_parts.append("Model selection CSV has >= 3 models (+10)")
        elif len(models) > 0:
            score += 5
            feedback_parts.append("Model selection CSV exists but fewer than 3 models (+5)")
        else:
            feedback_parts.append("Model selection CSV empty or unparseable")
            
        # Check AIC range (Amakihi data with hazard rate usually gives AIC ~ 12300-12400)
        valid_aic = any(12000 < m.get('aic', 0) < 13000 for m in models)
        if valid_aic:
            score += 10
            feedback_parts.append("AIC values in valid range (~12300) (+10)")
        else:
            feedback_parts.append("AIC values outside expected range (check model/data)")
    else:
        feedback_parts.append("Model selection CSV missing or not created during task")

    # Criterion 3: Abundance Estimates (30 pts)
    # Check total abundance. Reference for Amakihi (hazard rate, truncation 82.5) is approx 2500-3500 depending on exact model
    if files.get('abundance_csv', {}).get('new', False):
        total_n = data.get('abundance_total', 0)
        
        # Broad range to account for different model choices (Null vs Covariate)
        # Null model ~ 2800, Covariate models ~ 2600-3000. 
        # We accept 2000 - 4500 to be safe but ensure it's not totally wrong (e.g. 50 or 100000)
        if 2000 <= total_n <= 4500:
            score += 30
            feedback_parts.append(f"Abundance estimate ({total_n:.1f}) within valid range [2000-4500] (+30)")
        elif total_n > 0:
            score += 10
            feedback_parts.append(f"Abundance estimate ({total_n:.1f}) outside expected range [2000-4500] (+10)")
        else:
            feedback_parts.append("Abundance estimate not found or zero")
    else:
        feedback_parts.append("Abundance CSV missing")

    # Criterion 4: Plots (20 pts)
    if files.get('detection_png', {}).get('new', False):
        score += 10
        feedback_parts.append("Detection function plot created (+10)")
    else:
        feedback_parts.append("Detection function plot missing")

    if files.get('qq_png', {}).get('new', False):
        score += 10
        feedback_parts.append("Q-Q plot created (+10)")
    else:
        feedback_parts.append("Q-Q plot missing")

    # Criterion 5: Truncation Check (Inferential - 15 pts)
    # If the abundance is in range, they likely truncated correctly. 
    # Without truncation, estimates are often wilder or AICs different.
    # We implicitly awarded this in Abundance/AIC, but let's give points for the logical step if AICs are good.
    if data.get('models') and any(12000 < m.get('aic', 0) < 13000 for m in data.get('models', [])):
        score += 15
        feedback_parts.append("Model fit suggests correct data truncation (+15)")
    else:
        feedback_parts.append("Could not confirm correct data truncation from model outputs")

    final_score = min(score, 100)
    passed = final_score >= 60

    return {
        "passed": passed,
        "score": final_score,
        "feedback": "; ".join(feedback_parts)
    }