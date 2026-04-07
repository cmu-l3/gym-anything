#!/usr/bin/env python3
"""
Verifier for create_waterfall_profit task.

Verification Strategy:
1. Programmatic (Primary):
   - Check if .dva file exists and was created during task.
   - Inspect .dva content (ZIP archive) for "waterfall" keyword and required columns.
2. VLM (Secondary):
   - Check trajectory for interactions with "Waterfall" chart type.
   - Check final screenshot for visual confirmation of waterfall chart (red/green bars).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil

# Import VLM utils (mock import assumed available in framework)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_waterfall_profit(traj, env_info, task_info):
    """
    Verify creation of Waterfall chart showing Profit by Sub Category.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'Profit_Waterfall.dva')
    viz_keyword = metadata.get('viz_type_keyword', 'waterfall')
    
    score = 0
    feedback_parts = []
    
    # Setup temp directory
    temp_dir = tempfile.mkdtemp()
    local_json_path = os.path.join(temp_dir, "task_result.json")
    local_dva_path = os.path.join(temp_dir, expected_filename)
    
    try:
        # 1. READ METADATA FROM VM
        try:
            copy_from_env("C:\\tmp\\task_result.json", local_json_path)
            with open(local_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
            
        file_exists = result_data.get("file_exists", False)
        created_during = result_data.get("file_created_during_task", False)
        
        if not file_exists:
            return {"passed": False, "score": 0, "feedback": "Project file not saved."}
            
        score += 10 # File exists
        feedback_parts.append("File saved")
        
        if created_during:
            score += 10
            feedback_parts.append("New file created")
        else:
            feedback_parts.append("File timestamp invalid (old file?)")

        # 2. INSPECT DVA CONTENT (Programmatic)
        dva_valid = False
        content_score = 0
        
        try:
            copy_from_env(result_data.get("file_path"), local_dva_path)
            
            if zipfile.is_zipfile(local_dva_path):
                score += 5 # Valid zip
                dva_valid = True
                
                with zipfile.ZipFile(local_dva_path, 'r') as z:
                    # Search all XML/JSON files in the archive for keywords
                    # OAD .dva files contain XML or JSON definitions of the canvas
                    found_waterfall = False
                    found_profit = False
                    found_subcategory = False
                    
                    for filename in z.namelist():
                        if filename.endswith('.xml') or filename.endswith('.json'):
                            try:
                                with z.open(filename) as f:
                                    content = f.read().decode('utf-8', errors='ignore').lower()
                                    if viz_keyword in content:
                                        found_waterfall = True
                                    if "profit" in content:
                                        found_profit = True
                                    if "product sub category" in content or "product sub category" in content.replace('_', ' '):
                                        found_subcategory = True
                            except:
                                continue
                    
                    if found_waterfall:
                        content_score += 25
                        feedback_parts.append("Waterfall visualization detected in metadata")
                    else:
                        feedback_parts.append("Waterfall type NOT detected in file")
                        
                    if found_profit and found_subcategory:
                        content_score += 20
                        feedback_parts.append("Correct columns (Profit, Sub Category) detected")
                    elif found_profit or found_subcategory:
                        content_score += 10
                        feedback_parts.append("Some required columns detected")
                    else:
                        feedback_parts.append("Required data columns NOT detected")
                        
                score += content_score
            else:
                feedback_parts.append("Saved file is not a valid DVA archive")
                
        except Exception as e:
            feedback_parts.append(f"Failed to inspect file content: {str(e)}")

        # 3. VLM VERIFICATION
        vlm_score = 0
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        # We need at least the final screenshot
        if final_img:
            images_to_check = frames + [final_img]
            
            prompt = """
            Analyze these screenshots of Oracle Analytics Desktop.
            1. Is a Waterfall chart visible? (Look for a chart with floating vertical bars, often green for increase and red for decrease, showing a running total or breakdown).
            2. Does the chart title or axes mention "Profit" and "Sub Category"?
            3. Are there positive (up) and negative (down) bars visible?
            
            Return JSON:
            {
                "waterfall_chart_visible": boolean,
                "labels_correct": boolean,
                "positive_negative_bars": boolean
            }
            """
            
            vlm_result = query_vlm(images=images_to_check, prompt=prompt)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("waterfall_chart_visible", False):
                    vlm_score += 20
                    feedback_parts.append("VLM: Waterfall chart visible")
                
                if parsed.get("labels_correct", False):
                    vlm_score += 5
                    feedback_parts.append("VLM: Labels match")
                    
                if parsed.get("positive_negative_bars", False):
                    vlm_score += 5
                    feedback_parts.append("VLM: Positive/Negative bars visible")
            else:
                feedback_parts.append("VLM verification failed")
                
        score += vlm_score

        # Final Evaluation
        # Pass if: File exists/valid AND (Content correct OR VLM confirms chart)
        # We require at least 60 points
        passed = score >= 60 and dva_valid
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        shutil.rmtree(temp_dir)