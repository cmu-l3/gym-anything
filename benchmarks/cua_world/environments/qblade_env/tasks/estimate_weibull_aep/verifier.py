#!/usr/bin/env python3
"""
Verifier for estimate_weibull_aep task.

Verification Strategy:
1. File Verification (45 pts):
   - Report file exists and was created during task
   - Contains reasonable AEP value (numeric check)
   - Contains correct Weibull parameters (k=2.0, mean=8.0)
   - Contains correct turbine parameters (cut-in=3, cut-out=25)

2. VLM Verification (55 pts):
   - Workflow verification: Agent visited Turbine BEM module
   - Visual verification: Power curve graph is visible in trajectory
   - Consistency: Screen shows similar values to report
"""

import json
import re
import os
import tempfile
import logging

# Import VLM utilities from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images=None, image=None): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_estimate_weibull_aep(traj, env_info, task_info):
    """Verify QBlade AEP estimation task."""
    
    # 1. Setup and Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. File-Based Verification (45 pts max)
    content = result.get('report_content', '')
    report_exists = result.get('report_exists', False)
    created_during = result.get('report_created_during_task', False)

    # Criterion: Report Exists (10 pts)
    if report_exists and created_during:
        score += 10
        feedback_parts.append("Report file created successfully")
        
        # Parse Content
        content_lower = content.lower()
        
        # Check AEP Value (15 pts)
        # Regex to find numbers associated with AEP
        # Matches: "AEP: 12345", "AEP 12345.67", "12345 kWh"
        aep_matches = re.findall(r'aep[:\s]+([\d\.,]+)', content_lower)
        if not aep_matches:
             # Try finding just a large number followed by kWh/MWh
             aep_matches = re.findall(r'([\d\.,]+)\s*[km]wh', content_lower)
        
        aep_valid = False
        if aep_matches:
            try:
                # Remove commas and convert to float
                val_str = aep_matches[0].replace(',', '')
                val = float(val_str)
                
                # Normalize units if MWh detected
                if 'mwh' in content_lower and val < 100000: 
                    val *= 1000 # Convert MWh to kWh for range check
                
                # Range check (1 MWh to 40 GWh)
                if 1000 <= val <= 40000000:
                    score += 15
                    aep_valid = True
                    feedback_parts.append(f"AEP value ({val:.0f} kWh) is within reasonable range")
                else:
                    feedback_parts.append(f"AEP value ({val}) is outside physical range for this task")
            except ValueError:
                feedback_parts.append("Could not parse numeric AEP value")
        else:
            feedback_parts.append("No AEP value found in report")

        # Check Parameters (20 pts)
        # k=2.0, mean=8.0, cut-in=3, cut-out=25
        param_score = 0
        if '2.0' in content or '2' in content: param_score += 5
        if '8.0' in content or '8' in content: param_score += 5
        if '3' in content: param_score += 5
        if '25' in content: param_score += 5
        
        score += param_score
        if param_score == 20:
            feedback_parts.append("All simulation parameters correct in report")
        elif param_score > 0:
            feedback_parts.append("Some parameters found in report")
            
    else:
        feedback_parts.append("Report file not found or not created during task")

    # 3. VLM Verification (55 pts max)
    # Using trajectory to confirm the work was actually performed in QBlade
    
    frames = sample_trajectory_frames(traj, n=8)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        frames.append(final_img)

    if not frames:
        feedback_parts.append("No screenshots available for visual verification")
    else:
        vlm_prompt = """
        Analyze these screenshots of QBlade software.
        I am looking for evidence that the user performed a Turbine BEM Simulation.
        
        Please check for:
        1. Is a "Power Curve" or "Power vs Windspeed" graph visible? (The graph usually has an S-shape curve).
        2. Is the "Turbine BEM Simulation" module active? (Look for turbine icons or simulation controls).
        3. Are there input fields for "Cut-in", "Cut-out", or "Weibull" parameters visible?
        4. Is there a calculated AEP (Annual Energy Production) value displayed on screen?
        
        Respond in JSON:
        {
            "power_curve_graph_visible": boolean,
            "turbine_module_active": boolean,
            "weibull_params_visible": boolean,
            "aep_value_visible": boolean,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            
            # Score visual evidence
            vlm_score = 0
            
            if parsed.get("power_curve_graph_visible"):
                vlm_score += 20
                feedback_parts.append("Visual Evidence: Power curve graph detected")
            
            if parsed.get("turbine_module_active"):
                vlm_score += 15
                feedback_parts.append("Visual Evidence: Turbine simulation module used")
                
            if parsed.get("weibull_params_visible") or parsed.get("aep_value_visible"):
                vlm_score += 20
                feedback_parts.append("Visual Evidence: Simulation parameters/results visible")
                
            score += vlm_score
        else:
            feedback_parts.append("Visual verification failed to process images")

    # 4. Final Result
    # Pass threshold: 60 points (Must have file + at least some visual evidence)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }