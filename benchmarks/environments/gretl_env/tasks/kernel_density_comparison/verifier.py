#!/usr/bin/env python3
import json
import os
import re
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

def verify_kernel_density_comparison(traj, env_info, task_info):
    """
    Verifies the kernel density comparison task.
    
    Criteria:
    1. 'group_stats.txt' exists and contains statistics for two variables (food_hi, food_lo).
    2. Statistics values match expected ranges (High Income mean > Low Income mean).
    3. 'kde_comparison.png' exists and is a valid image.
    4. VLM confirms the image looks like a KDE plot with two curves.
    """
    
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_mean_hi_range = metadata.get('expected_mean_hi_range', [300, 450])
    expected_mean_lo_range = metadata.get('expected_mean_lo_range', [150, 280])

    score = 0
    feedback = []
    
    # Load JSON result from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify Stats File (Existence & Content) - 40 points
    stats_exists = result_data.get('stats_file_exists', False)
    stats_created_during = result_data.get('stats_file_created_during_task', False)
    
    stats_content = ""
    if stats_exists and stats_created_during:
        score += 10
        feedback.append("Statistics file created.")
        
        # Copy content
        temp_stats = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(result_data['stats_file_path'], temp_stats.name)
            with open(temp_stats.name, 'r', encoding='utf-8', errors='ignore') as f:
                stats_content = f.read()
        except Exception as e:
            feedback.append(f"Could not read stats file: {e}")
        finally:
            if os.path.exists(temp_stats.name):
                os.unlink(temp_stats.name)
        
        # Check content logic
        # Look for "Mean" and variable names
        # Note: Gretl output usually lists "Mean", "Median", etc.
        # We look for numbers associated with food_hi and food_lo
        
        # Heuristic regex to find means
        # Matches patterns like "Mean           355.23" or "Mean: 355.23"
        # We need to distinguish between the two variables. 
        # Usually summary output is blocks or a table.
        
        # Check if variable names are present
        if "food_hi" in stats_content and "food_lo" in stats_content:
            score += 10
            feedback.append("Both subgroups (food_hi, food_lo) found in stats.")
            
            # Extract Means
            # This is tricky without strict format, so we search for numbers near "Mean"
            # We assume the user generated valid summary stats
            
            # Simple check: Does the file contain a number > 300 (likely food_hi mean)
            # and a number < 280 (likely food_lo mean)?
            numbers = [float(x) for x in re.findall(r'-?\d+\.\d+', stats_content)]
            
            has_high_mean = any(expected_mean_hi_range[0] <= n <= expected_mean_hi_range[1] for n in numbers)
            has_low_mean = any(expected_mean_lo_range[0] <= n <= expected_mean_lo_range[1] for n in numbers)
            
            if has_high_mean and has_low_mean:
                score += 20
                feedback.append("Statistics values appear correct for the subgroups.")
            else:
                feedback.append("Could not verify specific mean values in output.")
        else:
            feedback.append("Statistics file does not clearly mention 'food_hi' and 'food_lo'.")
            
    else:
        feedback.append("Statistics file missing or not created during task.")

    # 3. Verify Image File (Existence) - 30 points
    img_exists = result_data.get('image_file_exists', False)
    img_created_during = result_data.get('image_file_created_during_task', False)
    img_size = result_data.get('image_file_size', 0)
    
    if img_exists and img_created_during and img_size > 1000: # >1KB
        score += 30
        feedback.append("Plot image file created.")
    else:
        feedback.append("Plot image missing or empty.")

    # 4. VLM Verification (Visual Check) - 30 points
    # We verify if the generated plot actually looks like a KDE comparison
    
    vlm_score = 0
    if img_exists:
        # Get the actual output image from the container for VLM check
        # This is better than the screenshot if available, but we can fallback to screenshot
        # For this setup, we'll try to use the actual output image if copy_from_env works
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        img_for_vlm = None
        try:
            copy_from_env(result_data['image_file_path'], temp_img.name)
            img_for_vlm = temp_img.name
        except:
            img_for_vlm = None # Fallback to screenshot check logic below if needed
            
        if img_for_vlm:
            prompt = (
                "This image should be a Kernel Density Estimation (KDE) plot generated by Gretl. "
                "Does it show a graph with two distinct curves (likely different colors or line styles) "
                "representing distributions? It should likely have a legend or labels for 'food_hi' and 'food_lo'. "
                "Return JSON: {\"is_kde_plot\": bool, \"has_two_curves\": bool, \"has_labels\": bool}"
            )
            
            vlm_res = query_vlm(image=img_for_vlm, prompt=prompt)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_kde_plot"):
                    vlm_score += 15
                if parsed.get("has_two_curves"):
                    vlm_score += 15
                
                if vlm_score < 30 and parsed.get("has_labels"): # Partial credit
                     vlm_score += 5
                     
            os.unlink(temp_img.name)
        else:
            feedback.append("Could not retrieve plot for VLM verification.")

    score += min(vlm_score, 30) # Cap VLM score part
    if vlm_score > 0:
        feedback.append(f"Visual verification passed ({vlm_score}/30).")

    # Final check
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }