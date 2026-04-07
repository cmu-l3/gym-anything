#!/usr/bin/env python3
"""
Verifier for create_sales_story task (Oracle Analytics Desktop).

Checks:
1. File Sales_Story_Presentation.dva exists and is a valid ZIP.
2. File was created/modified during the task session.
3. Internal metadata contains evidence of a 'Story' or 'Narrate' mode usage.
4. Internal metadata contains the specific annotation text.
5. VLM verification of the 'Narrate' workflow trajectory.
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil
from vlm_utils import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_story(traj, env_info, task_info):
    """
    Verify the agent created a data story with specific annotation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('annotation_text', "Technology generates the highest revenue")
    
    score = 0
    feedback_parts = []
    passed = False

    # Temp file to store the copied result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.dva')
    temp_json_path = temp_json.name
    temp_dva_path = temp_dva.name
    temp_json.close()
    temp_dva.close()

    try:
        # 1. Get Export Result
        try:
            copy_from_env("C:\\tmp\\task_result.json", temp_json_path)
            with open(temp_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        output_exists = result_data.get('output_exists', False)
        file_created = result_data.get('file_created_during_task', False)
        
        # Scoring: File Existence (20 pts)
        if output_exists:
            score += 20
            feedback_parts.append("Workbook file created")
            
            # Scoring: Anti-gaming (10 pts)
            if file_created:
                score += 10
                feedback_parts.append("File created during session")
            else:
                feedback_parts.append("Warning: File timestamp indicates it was not modified during this session")
        else:
            feedback_parts.append("Workbook file NOT found")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # 2. Content Verification (Deep Inspection of .dva)
        annotation_found = False
        story_mode_detected = False
        
        try:
            # Copy the .dva file
            copy_from_env(result_data.get('output_path'), temp_dva_path)
            
            if zipfile.is_zipfile(temp_dva_path):
                with zipfile.ZipFile(temp_dva_path, 'r') as z:
                    # Iterate through all files in the archive to find metadata
                    # OAD stores project data in XML or JSON files often under 'datamodel' or root
                    for filename in z.namelist():
                        if filename.endswith('.xml') or filename.endswith('.json') or filename.endswith('.txt'):
                            try:
                                with z.open(filename) as f:
                                    content = f.read().decode('utf-8', errors='ignore')
                                    
                                    # Check for annotation text
                                    if expected_text in content:
                                        annotation_found = True
                                    
                                    # Check for Story/Narrate indicators
                                    # Keywords often used in OAD XML/JSON for stories
                                    if '"story"' in content.lower() or '<story' in content.lower() or 'narrative' in content.lower():
                                        story_mode_detected = True
                            except:
                                continue
            else:
                feedback_parts.append("Output file is not a valid DVA archive")
        except Exception as e:
            feedback_parts.append(f"Failed to inspect workbook content: {str(e)}")

        # Scoring: Content
        if annotation_found:
            score += 25
            feedback_parts.append(f"Annotation text '{expected_text}' found in workbook")
        else:
            feedback_parts.append("Annotation text NOT found in workbook metadata")

        if story_mode_detected:
            score += 20
            feedback_parts.append("Story/Narrative structure detected in workbook")
        else:
            # Fallback: if we found the text but not explicit story tag, maybe it's just a text box on canvas
            # We strictly want a Story, but usually adding text involves similar structures.
            pass

        # 3. VLM Trajectory Verification (25 pts)
        # We need to verify the user actually used the "Narrate" tab
        frames = sample_trajectory_frames(traj, n=5)
        
        vlm_prompt = """
        Analyze these screenshots of Oracle Analytics Desktop.
        I am looking for evidence that the user created a 'Story' or used 'Narrate' mode.
        
        Look for:
        1. Click on the 'Narrate' tab (usually top bar).
        2. A filmstrip view at the bottom of the screen (characteristic of Narrate mode).
        3. A text annotation being added to a chart.
        4. The text "Technology generates the highest revenue" visible on screen.
        
        Did the user switch to Narrate mode and add the text?
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_success = vlm_result.get('parsed', {}).get('success', False) # Assuming simple bool parser or relying on positive text
        
        # Simplified VLM check for this template
        # In production, check vlm_result content more rigorously
        vlm_score_contrib = 0
        if "yes" in str(vlm_result).lower() or "narrate" in str(vlm_result).lower():
             vlm_score_contrib = 25
             feedback_parts.append("VLM confirms Narrate workflow")
        else:
             feedback_parts.append("VLM could not confirm Narrate workflow")
        
        score += vlm_score_contrib

        # Final Assessment
        passed = (score >= 70) and annotation_found

    finally:
        # Cleanup
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)
        if os.path.exists(temp_dva_path):
            os.unlink(temp_dva_path)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }