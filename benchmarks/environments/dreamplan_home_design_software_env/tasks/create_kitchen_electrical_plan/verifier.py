#!/usr/bin/env python3
"""
Verifier for create_kitchen_electrical_plan task.

Verification Strategy:
1. File Verification (Anti-Gaming):
   - Check if 'kitchen_electrical_plan.png' exists and was created during the task.
   - Check if project file was saved/modified.
   - Check if DreamPlan is still running.

2. VLM Verification (Visual Content):
   - Analyze the agent's saved screenshot ('kitchen_electrical_plan.png') for:
     - 2D Blueprint view style (blue/white lines).
     - Presence of electrical symbols (Outlets, Switches).
     - Kitchen context (counters, appliances).
   - Analyze the final screen state to confirm the agent left the app in Blueprint view.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_kitchen_electrical_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows paths in container need handling. Usually copy_from_env handles absolute paths.
        copy_from_env("C:\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Screenshots
    agent_screenshot_local = None
    if result.get('screenshot_exists'):
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(result['screenshot_path'], temp_img.name)
            agent_screenshot_local = temp_img.name
        except Exception as e:
            logger.warning(f"Failed to copy agent screenshot: {e}")

    # 3. Evaluate Anti-Gaming Criteria (30 points)
    
    # Screenshot exists and created during task (10 pts)
    if result.get('screenshot_exists') and result.get('screenshot_created_during_task'):
        score += 10
        feedback_parts.append("Screenshot created during task.")
    elif result.get('screenshot_exists'):
        score += 5
        feedback_parts.append("Screenshot exists but timestamp is suspicious.")
    else:
        feedback_parts.append("Expected screenshot not found.")

    # Project saved (10 pts)
    if result.get('project_saved'):
        score += 10
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file not saved.")

    # App running (10 pts)
    if result.get('app_running'):
        score += 10
        feedback_parts.append("Application is running.")

    # 4. VLM Verification (70 points)
    if agent_screenshot_local:
        prompt = """
        You are an architectural plan reviewer. Analyze this screenshot from DreamPlan Home Design Software.
        
        Task: Create a kitchen electrical plan in 2D Blueprint view with specific symbols.
        
        Check for:
        1. **View Mode**: Is this a 2D Blueprint / Floor Plan view? (Look for top-down view, schematic lines, grid, or blueprint style).
        2. **Context**: Is this a kitchen? (Look for counters, sink, stove, refrigerator).
        3. **Symbols**: Do you see small electrical symbols placed on walls or counters?
           - Standard Outlets (usually circles with two lines or similar icons)
           - Switches (usually '$' or 'S' icons)
           - High Voltage / Range Outlet (distinct icon near stove)
        
        Count roughly how many symbols you see.
        
        Return JSON:
        {
            "is_blueprint_view": true/false,
            "is_kitchen": true/false,
            "symbols_visible": true/false,
            "symbol_count_approx": int,
            "has_outlet_symbols": true/false,
            "has_switch_symbol": true/false,
            "has_high_voltage_symbol": true/false
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, image=agent_screenshot_local)
        
        if vlm_res and vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {})
            
            # Blueprint View (20 pts)
            if analysis.get('is_blueprint_view'):
                score += 20
                feedback_parts.append("Confirmed 2D Blueprint view.")
            else:
                feedback_parts.append("Screenshot does not look like 2D Blueprint view.")

            # Symbols Presence (30 pts)
            symbol_score = 0
            if analysis.get('symbols_visible'):
                count = analysis.get('symbol_count_approx', 0)
                # We asked for 4 outlets + 1 switch + 1 HV = 6 total
                if count >= 4:
                    symbol_score = 30
                elif count >= 1:
                    symbol_score = 15
                
                # Bonus checks for specific types
                if analysis.get('has_switch_symbol') and analysis.get('has_high_voltage_symbol'):
                    feedback_parts.append("Specific symbols (Switch/HV) detected.")
                else:
                    feedback_parts.append("Some symbols detected.")
            
            score += symbol_score
            
            # Context (20 pts)
            if analysis.get('is_kitchen'):
                score += 20
                feedback_parts.append("Confirmed kitchen location.")
            else:
                feedback_parts.append("Location does not look like a kitchen.")
                
        else:
            feedback_parts.append("VLM analysis failed.")
            
        # Cleanup
        if os.path.exists(agent_screenshot_local):
            os.unlink(agent_screenshot_local)
            
    else:
        feedback_parts.append("No screenshot available for visual verification.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }