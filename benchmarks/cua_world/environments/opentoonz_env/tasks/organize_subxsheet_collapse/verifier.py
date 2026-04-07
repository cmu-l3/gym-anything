#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_subxsheet_collapse(traj, env_info, task_info):
    """
    Verifies that the agent has:
    1. Created the organized scene file.
    2. Used a Sub-Xsheet (found in the .tnz XML).
    3. Rendered a verification frame that is not empty.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Verify Scene File Existence (20 pts)
    if result.get("scene_exists") and result.get("scene_created_during_task"):
        score += 20
        feedback.append("Scene file created successfully.")
        
        # Pull the actual .tnz file to analyze its structure
        scene_path = result.get("scene_path")
        temp_scene = tempfile.NamedTemporaryFile(delete=False, suffix='.tnz')
        try:
            copy_from_env(scene_path, temp_scene.name)
            
            # Parse XML
            try:
                tree = ET.parse(temp_scene.name)
                root = tree.getroot()
                
                # Check for Sub-Xsheet level definition
                # Look for <level ... type="subXsheet"> OR <subXsheet> tag depending on version
                # OpenToonz usually defines it in the <levels> section
                has_subxsheet = False
                levels = root.find("levels")
                if levels is not None:
                    for level in levels:
                        if level.get("type") == "subXsheet" or level.tag == "subXsheet":
                            has_subxsheet = True
                            break
                
                # Check for usage in xsheet columns
                # The xsheet should ideally have fewer columns than original (3)
                # or explicit reference to the subxsheet level
                xsheet = root.find("xsheet")
                columns = xsheet.find("columns") if xsheet is not None else None
                col_count = 0
                if columns is not None:
                    col_count = len(list(columns))

                # 2. Structure Verification (40 pts)
                if has_subxsheet:
                    score += 40
                    feedback.append("Sub-Xsheet structure detected in scene file.")
                    
                    # Bonus check: If column count is reduced (Original was 3: Back, Table, Char)
                    # If collapsed Back+Table -> SubXsheet, we have SubXsheet + Char = 2 columns.
                    if col_count <= 2:
                        feedback.append(f"Column count reduced to {col_count} (cleaner timeline).")
                    else:
                        feedback.append(f"Column count is {col_count} (might still be cluttered, but Sub-Xsheet exists).")
                else:
                    feedback.append("Failed: No Sub-Xsheet found in scene file XML.")

            except ET.ParseError:
                feedback.append("Error: Could not parse scene file XML.")
        except Exception as e:
            feedback.append(f"Error analyzing scene file: {e}")
        finally:
            if os.path.exists(temp_scene.name):
                os.unlink(temp_scene.name)
    else:
        feedback.append("Scene file not found or not created during task.")

    # 3. Verify Render (Visual Integrity) (40 pts)
    # Ideally compare against ground truth, but basic check is file existence + size
    if result.get("render_exists") and result.get("render_created_during_task"):
        render_size = result.get("render_size_bytes", 0)
        # 1KB is too small for a 1080p frame, usually >10KB even if simple
        if render_size > 5000: 
            score += 40
            feedback.append("Verification render created and has valid size.")
        else:
            score += 10
            feedback.append("Verification render created but seems empty/corrupt (too small).")
    else:
        feedback.append("No verification render found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }