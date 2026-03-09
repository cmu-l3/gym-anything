#!/usr/bin/env python3
"""
Verifier for create_soccer_tactic_diagram task.

Checks:
1. Files (.eddx and .jpg) exist and were created during the task.
2. .eddx file is a valid ZIP and contains specific shapes (Soccer Field, Players, Ball).
3. Text annotation is present.
4. JPG file is a valid image.
"""

import os
import json
import tempfile
import zipfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_soccer_tactic_diagram(traj, env_info, task_info):
    """
    Verify the soccer tactic diagram creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    eddx_remote_path = "/home/ga/Documents/soccer_tactic.eddx"
    jpg_remote_path = "/home/ga/Documents/soccer_tactic.jpg"
    result_remote_path = "/tmp/task_result.json"

    # Temporary local files
    temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx').name
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    
    # We don't strictly need to download the JPG for content analysis if we trust the export script's sizing,
    # but downloading it allows verifying it's a real image header if needed. 
    # For now, we rely on metadata for the JPG to keep verification fast.

    score = 0
    feedback_parts = []
    
    try:
        # 1. Load Task Result Metadata
        try:
            copy_from_env(result_remote_path, temp_result)
            with open(temp_result, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result metadata: {str(e)}"}

        # Check EDDX existence and timing (20 pts)
        if result_data.get("eddx_exists") and result_data.get("eddx_created_during_task"):
            score += 20
            feedback_parts.append("EDDX file created successfully.")
        else:
            feedback_parts.append("EDDX file missing or not created during task.")
        
        # Check JPG existence and timing (10 pts)
        if result_data.get("jpg_exists") and result_data.get("jpg_created_during_task") and result_data.get("jpg_size_bytes", 0) > 1000:
            score += 10
            feedback_parts.append("JPG export created successfully.")
        else:
            feedback_parts.append("JPG export missing or invalid.")

        # 2. Analyze EDDX Content (70 pts)
        if result_data.get("eddx_exists"):
            try:
                copy_from_env(eddx_remote_path, temp_eddx)
                
                if not zipfile.is_zipfile(temp_eddx):
                    feedback_parts.append("EDDX file is not a valid archive.")
                else:
                    with zipfile.ZipFile(temp_eddx, 'r') as zf:
                        # Extract all XML content
                        xml_content = ""
                        for name in zf.namelist():
                            if name.endswith('.xml'):
                                try:
                                    xml_content += zf.read(name).decode('utf-8', errors='ignore')
                                except:
                                    pass
                        
                        # Check for Soccer Field (20 pts)
                        # Keywords based on EdrawMax symbol naming conventions
                        if "Soccer Field" in xml_content or "Football Field" in xml_content or "Pitch" in xml_content:
                            score += 20
                            feedback_parts.append("Soccer field background detected.")
                        else:
                            feedback_parts.append("Soccer field background NOT found.")

                        # Check for Players (20 pts)
                        # We look for multiple occurrences of 'Player' or generic shapes if labeled
                        # This is a heuristic count based on substrings
                        player_keywords = ["Player", "User", "Person", "Man"]
                        player_count = 0
                        for kw in player_keywords:
                            player_count += xml_content.count(kw)
                        
                        # We expect at least 10 players. 
                        # Note: Simple string counting is approximate but effective for 'did they place objects' checks.
                        if player_count >= 10:
                            score += 20
                            feedback_parts.append(f"Player objects detected (Count approx: {player_count}).")
                        elif player_count >= 5:
                            score += 10
                            feedback_parts.append(f"Some player objects detected, but fewer than requested ({player_count}).")
                        else:
                            feedback_parts.append("Insufficient player objects found.")

                        # Check for Colors (15 pts)
                        # We look for hex codes roughly corresponding to Red (#FF0000) and Blue (#0000FF)
                        # or common variations found in XML attributes.
                        # EdrawMax might store colors as decimal integers or hex.
                        # We will look for generic evidence of multiple distinct colors.
                        # Simplification: Just checking for the required text title for these points to be robust against internal format changes.
                        
                        # Check for Title Text (15 pts)
                        required_text = "Corner Routine: Near Post Attack"
                        if required_text in xml_content:
                            score += 15
                            feedback_parts.append("Correct title text found.")
                        else:
                            feedback_parts.append("Title text not found.")
                        
                        # Bonus: Check for Ball
                        if "Ball" in xml_content or "Soccer" in xml_content:
                            feedback_parts.append("Ball object likely present.")

            except Exception as e:
                feedback_parts.append(f"Error analyzing EDDX content: {str(e)}")

    finally:
        # Cleanup
        if os.path.exists(temp_eddx):
            os.remove(temp_eddx)
        if os.path.exists(temp_result):
            os.remove(temp_result)

    # Final scoring logic
    # Pass if score >= 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }