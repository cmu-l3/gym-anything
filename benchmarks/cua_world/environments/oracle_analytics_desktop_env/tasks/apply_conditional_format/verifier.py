#!/usr/bin/env python3
"""
Verifier for apply_conditional_format task in Oracle Analytics Desktop.

Verification Strategy:
1. File Verification (40 pts): Checks if 'Supply_Chain_Profit_Analysis.dva' was saved
   and modified during the task.
2. VLM Verification (60 pts): Uses trajectory frames to verify:
   - A Table visualization exists.
   - Profit column has colored backgrounds.
   - Three distinct colors (Red/Yellow/Green) are visible.
   - Title matches requirements.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_apply_conditional_format(traj, env_info, task_info):
    """
    Verify the conditional formatting task using file checks and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. FILE-BASED VERIFICATION (40 Points)
    # =========================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        # Copy result JSON from Windows container (path defined in export_result.ps1)
        # Note: copy_from_env usually handles path conversion if the agent runner supports it,
        # otherwise we assume the standard temp path.
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        feedback_parts.append("Failed to retrieve task result file from environment")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    output_exists = result_data.get("output_exists", False)
    created_during = result_data.get("file_created_during_task", False)
    
    if output_exists:
        score += 20
        feedback_parts.append("Workbook file saved successfully (20/20)")
        if created_during:
            score += 20
            feedback_parts.append("File created/modified during task session (20/20)")
        else:
            feedback_parts.append("File exists but was not modified during this session (0/20)")
    else:
        feedback_parts.append("Workbook file 'Supply_Chain_Profit_Analysis.dva' not found (0/40)")

    # =========================================================
    # 2. VLM VISUAL VERIFICATION (60 Points)
    # =========================================================
    # Use multiple frames to see the workflow and the final state
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        frames.append(final_screen)
        
    vlm_prompt = """
    You are verifying an Oracle Analytics Desktop task.
    
    Goal: Create a table with 'Product Sub Category', 'Profit', and 'Sales', and apply Conditional Formatting to the Profit column:
    - Red for negative values (< 0)
    - Yellow/Amber for mid values (0 to 5000)
    - Green for high values (>= 5000)
    
    Analyze the screenshots (chronological order) and the final screen.
    
    Check for:
    1. **Table Visualization**: Is there a table showing data?
    2. **Columns**: Do you see 'Product Sub Category', 'Profit', and 'Sales'?
    3. **Conditional Formatting**: Are the cells in the Profit column colored?
    4. **Color Logic**: Do you see Red, Yellow, and Green cells in that column? (or shades of these)
    5. **Title**: Is the title 'Product Profitability by Sub-Category' visible?
    
    Respond in JSON:
    {
        "table_exists": boolean,
        "formatting_applied": boolean,
        "three_colors_visible": boolean,
        "title_correct": boolean,
        "confidence": "low/medium/high",
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Criterion 1: Table exists (15 pts)
        if parsed.get("table_exists"):
            score += 15
            feedback_parts.append("Table visualization detected (15/15)")
        else:
            feedback_parts.append("Table visualization not found via VLM")

        # Criterion 2: Conditional Formatting Applied (15 pts)
        if parsed.get("formatting_applied"):
            score += 15
            feedback_parts.append("Conditional formatting (colored cells) visible (15/15)")
        else:
            feedback_parts.append("No conditional formatting detected")

        # Criterion 3: Correct Colors (20 pts)
        if parsed.get("three_colors_visible"):
            score += 20
            feedback_parts.append("Correct color scheme (Red/Yellow/Green) visible (20/20)")
        elif parsed.get("formatting_applied"):
            score += 10 # Partial credit if formatting exists but maybe not all 3 colors visible
            feedback_parts.append("Formatting applied but all 3 colors not clearly distinct (10/20)")
            
        # Criterion 4: Title (10 pts)
        if parsed.get("title_correct"):
            score += 10
            feedback_parts.append("Correct title visible (10/10)")
        else:
            feedback_parts.append("Title mismatch or not visible")
            
    else:
        feedback_parts.append("Visual verification failed (VLM error)")

    # =========================================================
    # Final Evaluation
    # =========================================================
    passed = score >= 55 and output_exists and result_data.get("formatting_applied", True) # VLM fallback implicit
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }