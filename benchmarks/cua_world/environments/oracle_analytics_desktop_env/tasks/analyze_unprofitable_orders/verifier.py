#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_unprofitable_orders(traj, env_info, task_info):
    """
    Verifies the Analyze Unprofitable Orders task.
    
    Checks:
    1. .dva file created and exported.
    2. Calculation logic (conditional profit < 0).
    3. Calculation logic (ratio/rate).
    4. Visualization type (bar chart).
    5. Visualization configuration (Region + Percent format).
    6. VLM confirmation of chart.
    """
    
    # 1. Setup and Copy Files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Copy result JSON
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result JSON"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Copy .dva file
    dva_path = task_result.get('output_path', '')
    local_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    has_dva = False
    
    if task_result.get('output_exists') and task_result.get('file_created_during_task'):
        try:
            copy_from_env(dva_path, local_dva.name)
            has_dva = True
        except Exception as e:
            logger.error(f"Failed to copy DVA file: {e}")

    # Initialize Score
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (10 pts)
    if has_dva and os.path.getsize(local_dva.name) > 1000:
        score += 10
        feedback.append("DVA file exported successfully.")
    else:
        feedback.append("DVA file missing or empty.")
        if os.path.exists(local_dva.name): os.unlink(local_dva.name)
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Inspect DVA Content
    # DVA is a zip. We look for XML/JSON defining the analysis.
    calc_logic_found = False
    ratio_logic_found = False
    viz_type_found = False
    region_dim_found = False
    percent_fmt_found = False
    
    try:
        with zipfile.ZipFile(local_dva.name, 'r') as z:
            # Search relevant files (usually datamodel or view definitions)
            for filename in z.namelist():
                if filename.endswith('.xml') or filename.endswith('.json'):
                    try:
                        content = z.read(filename).decode('utf-8', errors='ignore')
                        
                        # Logic Check: "Profit" AND "<" AND "0" (or similar)
                        if "Profit" in content and ("<" in content or "&lt;" in content) and "0" in content:
                            # Rudimentary check for conditional
                            if "CASE" in content or "FILTER" in content or "calc" in content.lower():
                                calc_logic_found = True
                        
                        # Logic Check: Ratio (Count / Count or Sum / Count)
                        if "/" in content and ("COUNT" in content or "SUM" in content):
                            ratio_logic_found = True
                            
                        # Viz Check
                        if 'type="bar"' in content.lower() or 'type="funnel"' in content.lower(): # funnel sometimes misidentified, stick to bar
                             if "bar" in content.lower():
                                 viz_type_found = True
                        
                        # Dimension Check
                        if "Region" in content:
                            region_dim_found = True
                            
                        # Format Check
                        if 'percent' in content.lower() or 'formatString="0%' in content:
                            percent_fmt_found = True
                            
                    except:
                        continue
    except Exception as e:
        feedback.append(f"Error parsing DVA: {e}")

    if os.path.exists(local_dva.name):
        os.unlink(local_dva.name)

    # Criterion 2: Calculation Logic (Condition) (25 pts)
    if calc_logic_found:
        score += 25
        feedback.append("Calculation logic (Profit < 0) detected.")
    else:
        feedback.append("Calculation logic not detected in file.")

    # Criterion 3: Calculation Logic (Rate/Ratio) (25 pts)
    if ratio_logic_found:
        score += 25
        feedback.append("Rate calculation logic detected.")
    else:
        feedback.append("Rate/Ratio logic not detected.")

    # Criterion 4: Visualization Config (10 pts)
    if viz_type_found and region_dim_found:
        score += 10
        feedback.append("Bar chart by Region detected.")
    elif viz_type_found:
        score += 5
        feedback.append("Bar chart detected (Region missing).")
    else:
        feedback.append("Bar chart configuration not found.")

    # Criterion 5: Formatting (10 pts)
    if percent_fmt_found:
        score += 10
        feedback.append("Percentage formatting detected.")
    else:
        feedback.append("Percentage formatting not found in metadata.")

    # Criterion 6: VLM Verification (20 pts)
    # Check if a chart is visible and looks like a bar chart with percentages
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_prompt = """
        Analyze this screenshot of Oracle Analytics Desktop.
        1. Is there a Bar Chart visible?
        2. Does the chart have roughly 4 bars (for Regions)?
        3. Do the axis labels or data labels show Percentages (e.g., 20%, 0.25)?
        4. Does the chart look like a "Loss Rate" analysis (not just total Sales)?
        
        Return JSON: {"bar_chart": bool, "four_regions": bool, "is_percentage": bool, "loss_analysis": bool}
        """
        
        vlm_res = query_vlm(image=final_screen, prompt=vlm_prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('bar_chart'):
                score += 5
            if parsed.get('is_percentage'):
                score += 10
            if parsed.get('loss_analysis') or parsed.get('four_regions'):
                score += 5
            feedback.append(f"VLM Analysis: {parsed}")
        else:
            feedback.append("VLM verification failed.")

    # Final Score Calculation
    passed = score >= 70 and calc_logic_found and viz_type_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }