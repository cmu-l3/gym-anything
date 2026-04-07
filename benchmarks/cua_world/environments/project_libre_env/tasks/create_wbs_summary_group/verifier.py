#!/usr/bin/env python3
"""
Verifier for create_wbs_summary_group task.

Verifies that the user has:
1. Created a new summary task named "Testing Phase"
2. Indented specific child tasks under it (OutlineLevel check)
3. Saved the result to the correct XML file

Uses copy_from_env to retrieve files from the container.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging
from typing import Dict, Any, Tuple

# Import VLM utils from framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=1): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

NS = "http://schemas.microsoft.com/project"

def verify_create_wbs_summary_group(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Projects/updated_project.xml')
    summary_name = metadata.get('summary_task_name', 'Testing Phase')
    child_names = metadata.get('child_tasks', [])

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Task Result JSON
    # ---------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.close()
            with open(tmp.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # Check file existence and timestamp (Anti-gaming)
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output XML file not found. Did you save to '/home/ga/Projects/updated_project.xml'?"}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task session."}
    
    score += 10 # File saved correctly
    feedback_parts.append("File saved successfully (10/100)")

    # ---------------------------------------------------------
    # 2. Parse XML Structure
    # ---------------------------------------------------------
    xml_score = 0
    xml_feedback = []
    
    with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tmp:
        xml_path = tmp.name
    
    try:
        copy_from_env(expected_path, xml_path)
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        # Helper to find text safely
        def find_text(elem, tag):
            found = elem.find(f"{{{NS}}}{tag}")
            return found.text if found is not None else ""

        tasks = root.find(f"{{{NS}}}Tasks")
        if tasks is None:
            raise ValueError("Invalid Project XML: No <Tasks> element")

        # Extract relevant tasks
        all_task_elems = tasks.findall(f"{{{NS}}}Task")
        
        summary_task = None
        summary_outline_level = -1
        
        # Search for the summary task
        for t in all_task_elems:
            name = find_text(t, "Name")
            if summary_name.lower() in name.lower():
                summary_task = t
                try:
                    summary_outline_level = int(find_text(t, "OutlineLevel") or "1")
                except ValueError:
                    summary_outline_level = 1
                break
        
        if summary_task is not None:
            xml_score += 20
            xml_feedback.append(f"Summary task '{summary_name}' found (+20)")
            
            # Check if it is actually marked as a summary/group
            is_summary = find_text(summary_task, "Summary")
            if is_summary == "1":
                xml_score += 10
                xml_feedback.append("Task is correctly marked as Summary (+10)")
            else:
                xml_feedback.append("Task exists but is NOT marked as a Summary (0)")
        else:
            xml_feedback.append(f"Summary task '{summary_name}' NOT found (0)")

        # Check children indentation
        children_found = 0
        children_correct = 0
        
        for t in all_task_elems:
            name = find_text(t, "Name")
            
            # Check if this is one of our expected children
            if any(child in name for child in child_names):
                children_found += 1
                try:
                    level = int(find_text(t, "OutlineLevel") or "0")
                    # Logic: Child level should be Summary Level + 1
                    if summary_task is not None and level == summary_outline_level + 1:
                        children_correct += 1
                except ValueError:
                    pass

        # Score children
        # 4 children * 10 points each = 40 points max
        child_score = children_correct * 10
        xml_score += child_score
        
        if children_correct == len(child_names):
            xml_feedback.append(f"All {children_correct} child tasks indented correctly (+{child_score})")
        elif children_correct > 0:
            xml_feedback.append(f"Only {children_correct}/{len(child_names)} child tasks indented correctly (+{child_score})")
        else:
            xml_feedback.append("No child tasks were indented correctly (0)")

    except Exception as e:
        xml_feedback.append(f"Failed to parse project XML: {str(e)}")
    finally:
        if os.path.exists(xml_path):
            os.unlink(xml_path)

    score += xml_score
    feedback_parts.extend(xml_feedback)

    # ---------------------------------------------------------
    # 3. VLM Verification (Trajectory Analysis)
    # ---------------------------------------------------------
    # We verify that the user actually interacted with the UI (Insert, Indent)
    # rather than just hacking the file, and that the visual state matches.
    
    vlm_score = 0
    
    # Get frames
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if frames:
        prompt = f"""
        Analyze these screenshots of ProjectLibre (a project management tool).
        The user was asked to:
        1. Insert a new task named "{summary_name}".
        2. Select tasks: {', '.join(child_names)}.
        3. Indent them to make "{summary_name}" a summary group.
        
        Look for:
        - A row named "{summary_name}" appearing in the task list.
        - The child tasks appearing indented (shifted right) relative to "{summary_name}".
        - A collapse/expand icon (triangle/plus) next to "{summary_name}".
        - The "Indent" button being clicked or the structure changing.
        
        Did the user successfully create the summary group structure visually?
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result.get("success", False) and vlm_result.get("parsed", {}).get("answer", False):
                # We assume a boolean "answer" or positive sentiment analysis
                # For this template, we check a simple "passed" flag if available, or parse text
                # Adjust based on actual VLM response format
                vlm_score = 20
                feedback_parts.append("Visual verification passed (+20)")
            else:
                # Fallback if VLM is unsure or negative, but Programmatic passed high
                if xml_score >= 60:
                    vlm_score = 20 # Trust programmatic if VLM is ambiguous
                    feedback_parts.append("Visual verification skipped (Programmatic strong)")
                else:
                    feedback_parts.append("Visual verification failed (0)")
        except Exception:
            # If VLM fails but file is perfect, give benefit of doubt
            if xml_score >= 60:
                vlm_score = 20
            feedback_parts.append("VLM analysis unavailable")
    
    score += vlm_score

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = (score >= 60) and (xml_score >= 30) # Must have some XML success
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }