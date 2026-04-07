#!/usr/bin/env python3
"""
Verifier for create_saved_traceability_view task.

Verification Strategy:
1. Primary (JSON Analysis):
   - Read the SRS.json file from the project.
   - Check if a view named "RTM_Audit" exists in the 'views' list.
   - Verify the view has columns for ID, Description, Status.
   - Verify the view has a Traceability column linking to 'TESTS'.
   
2. Secondary (VLM):
   - Analyze trajectory/final screenshot to confirm the visual presence of the view.
   - Look for link tokens (e.g., 'TESTS-12') in the table.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_saved_traceability_view(traj, env_info, task_info):
    """
    Verify that the agent created and saved the 'RTM_Audit' view with traceability.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    target_view_name = metadata.get('target_view_name', 'RTM_Audit')
    linked_doc_id = metadata.get('linked_doc_id', 'TESTS')
    
    # Get paths from the export result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    srs_path = export_result.get("srs_path", "/home/ga/Documents/ReqView/rtm_view_task_project/documents/SRS.json")
    file_modified = export_result.get("srs_file_modified", False)

    # Scoring accumulator
    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. JSON Configuration Verification
    # ------------------------------------------------------------------
    
    # Copy SRS.json
    temp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    srs_data = None
    try:
        copy_from_env(srs_path, temp_srs.name)
        with open(temp_srs.name, 'r') as f:
            srs_data = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read SRS document file: {str(e)}")
    finally:
        if os.path.exists(temp_srs.name):
            os.unlink(temp_srs.name)

    view_found = False
    traceability_col_found = False
    standard_cols_found = 0
    
    if srs_data:
        # Check for saved views
        views = srs_data.get("views", [])
        target_view = None
        
        # Find view by name
        for v in views:
            if v.get("name") == target_view_name:
                target_view = v
                view_found = True
                break
        
        if view_found:
            score += 40
            feedback.append(f"View '{target_view_name}' found in project configuration.")
            
            # Analyze columns
            columns = target_view.get("columns", [])
            for col in columns:
                # Check for standard columns (fuzzy match on attribute name)
                # ReqView stores simple cols as string or dict with 'attr'
                col_attr = col.get("attr", "") if isinstance(col, dict) else str(col)
                if col_attr in ["id", "description", "status", "heading"]:
                    standard_cols_found += 1
                
                # Check for traceability column
                # Traceability columns often have 'source' or 'docId' pointing to linked doc
                # Or 'linkType'
                # Example JSON structure: { "source": "TESTS", "attr": "links", ... }
                if (isinstance(col, dict) and 
                   (col.get("source") == linked_doc_id or 
                    col.get("docId") == linked_doc_id or
                    linked_doc_id in str(col))):
                    traceability_col_found = True

            if traceability_col_found:
                score += 30
                feedback.append(f"Traceability column linking to '{linked_doc_id}' verified.")
            else:
                feedback.append(f"View exists but missing traceability column for '{linked_doc_id}'.")
                
            if standard_cols_found >= 2: # At least ID and Desc usually
                score += 10
                feedback.append("Standard columns (ID, Description, Status) present.")
        else:
            feedback.append(f"View '{target_view_name}' NOT found in project.")
    
    # Bonus for file modification (anti-gaming)
    if file_modified:
        score += 10
        feedback.append("Project file was modified during task.")

    # ------------------------------------------------------------------
    # 2. VLM Verification (Visual Confirmation)
    # ------------------------------------------------------------------
    final_screen = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screen:
        prompt = f"""
        Analyze this screenshot of the ReqView software.
        1. Is the currently active view named '{target_view_name}'? (Look at the view dropdown/selector)
        2. Is there a table column showing links to '{linked_doc_id}'? (Look for column headers like 'Links', 'Traceability', 'Verifies', or 'Tests')
        3. Do you see any link IDs in that column (e.g., 'TESTS-12', 'TESTS-5')?
        
        Return JSON: {{ "view_active": boolean, "trace_column_visible": boolean, "links_visible": boolean }}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=[final_screen])
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("view_active"):
                vlm_score += 5
            if parsed.get("trace_column_visible") or parsed.get("links_visible"):
                vlm_score += 5
                
            score += vlm_score
            if vlm_score > 0:
                feedback.append("Visual verification passed.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = (view_found and traceability_col_found) or (score >= 70)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }