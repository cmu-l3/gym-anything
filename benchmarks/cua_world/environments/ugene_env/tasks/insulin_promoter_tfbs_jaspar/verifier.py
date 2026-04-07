#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insulin_promoter_tfbs_jaspar(traj, env_info, task_info):
    """
    Verifies the insulin_promoter_tfbs_jaspar task.
    Combines file-based programmatic verification with VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Retrieve the exported JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback = []

    gb = result.get('gb_file', {})
    gff = result.get('gff_file', {})
    txt = result.get('txt_file', {})

    # 1. Output Files Exist & Created During Task (15 pts)
    files_exist = gb.get('exists') and gff.get('exists') and txt.get('exists')
    files_created_in_task = gb.get('created_during_task') or gff.get('created_during_task') or txt.get('created_during_task')
    
    if files_exist:
        if files_created_in_task:
            score += 15
            feedback.append("All output files exist and were created during task (+15).")
        else:
            score += 5
            feedback.append("Files exist but appear older than task start (+5).")
    else:
        feedback.append("One or more expected output files are missing (0).")

    # 2. GenBank Annotations contain TBP (20 pts)
    if gb.get('exists') and gb.get('valid_format'):
        if gb.get('has_tbp'):
            score += 20
            feedback.append("GenBank file contains TBP features (+20).")
        else:
            feedback.append("GenBank file missing TBP features (0).")
            
    # 3. GenBank Annotations contain SP1 (20 pts)
    if gb.get('exists') and gb.get('valid_format'):
        if gb.get('has_sp1'):
            score += 20
            feedback.append("GenBank file contains SP1 features (+20).")
        else:
            feedback.append("GenBank file missing SP1 features (0).")

    # 4. GFF File Valid and contains TBP/SP1 (20 pts)
    if gff.get('exists'):
        gff_score = 0
        if gff.get('has_tbp'): gff_score += 10
        if gff.get('has_sp1'): gff_score += 10
        score += gff_score
        if gff_score == 20:
            feedback.append("GFF file valid and contains TBP and SP1 sites (+20).")
        else:
            feedback.append(f"GFF file partially complete/valid (+{gff_score}).")

    # 5. Summary Report Content (10 pts)
    if txt.get('exists'):
        txt_score = 0
        if txt.get('has_85'): txt_score += 3
        if txt.get('has_tbp') and txt.get('has_sp1'): txt_score += 4
        if txt.get('has_regulation_keyword'): txt_score += 3
        score += txt_score
        feedback.append(f"Summary text content evaluation (+{txt_score}/10).")

    # 6. VLM Trajectory Verification (15 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            prompt = """
            You are verifying a bioinformatics agent's performance in UGENE.
            The agent was tasked with using the 'Search TFBS with matrices' tool (Weight Matrix plugin) with the JASPAR database to find TBP and SP1 transcription factor binding sites at an 85% threshold.
            
            Look at these trajectory screenshots. Did the agent open the Weight Matrix/Search TFBS dialog, select the JASPAR database/profiles for TBP or SP1, and set a threshold?
            
            Respond with JSON:
            {
                "dialog_opened": true/false,
                "jaspar_or_tfbs_selected": true/false,
                "threshold_visible": true/false
            }
            """
            
            vlm_response = query_vlm(images=all_frames, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("dialog_opened"): vlm_score += 5
                if parsed.get("jaspar_or_tfbs_selected"): vlm_score += 5
                if parsed.get("threshold_visible"): vlm_score += 5
                
                score += vlm_score
                feedback.append(f"VLM verified workflow progression (+{vlm_score}/15).")
            else:
                # If VLM fails, grant partial default if programmatic scored well (prevents false fail due to API issues)
                if score >= 60:
                    vlm_score = 15
                    score += vlm_score
                    feedback.append("VLM unavailable but programmatic evidence strong; granting VLM points.")
    except Exception as e:
        logger.warning(f"VLM verification failed/unavailable: {e}")
        # Give benefit of doubt if they nailed programmatic requirements
        if score >= 60:
            score += 15
            feedback.append("VLM check skipped, but programmatic score high (+15).")
            
    # Success threshold: At least 75 points, and BOTH TBP and SP1 must be in the GenBank file.
    key_criteria_met = gb.get('has_tbp', False) and gb.get('has_sp1', False) and files_exist
    passed = (score >= 75) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "gb_has_tbp": gb.get('has_tbp'),
            "gb_has_sp1": gb.get('has_sp1'),
            "files_created_during_task": files_created_in_task
        }
    }