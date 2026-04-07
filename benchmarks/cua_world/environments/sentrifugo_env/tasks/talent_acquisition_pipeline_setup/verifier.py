#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_talent_acquisition_pipeline_setup(traj, env_info, task_info):
    """
    Verify the Sentrifugo Talent Acquisition configuration task.
    
    1. Check Job Titles via SQL query results (20 points)
    2. Check Interview Rounds via Database full-text dump (30 points)
    3. Check Requisitions using VLM on trajectory frames OR DB dump fallback (50 points)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # ================================================================
    # 1. Job Titles (20 pts)
    # ================================================================
    jt_biomass = int(result.get('job_title_biomass_count', 0))
    jt_safety = int(result.get('job_title_safety_count', 0))
    
    if jt_biomass > 0:
        score += 10
        feedback_parts.append("Job Title 'Senior Biomass Process Engineer' created (10/10)")
    else:
        feedback_parts.append("Job Title 'Senior Biomass Process Engineer' missing (0/10)")

    if jt_safety > 0:
        score += 10
        feedback_parts.append("Job Title 'Field Safety Inspector' created (10/10)")
    else:
        feedback_parts.append("Job Title 'Field Safety Inspector' missing (0/10)")

    # ================================================================
    # 2. Interview Rounds (30 pts)
    # ================================================================
    ir_phone = int(result.get('ir_phone_found', 0))
    ir_tech = int(result.get('ir_tech_found', 0))
    ir_manager = int(result.get('ir_manager_found', 0))

    if ir_phone > 0:
        score += 10
        feedback_parts.append("Interview Round 'Initial Phone Screen' found in DB (10/10)")
    else:
        feedback_parts.append("Interview Round 'Initial Phone Screen' missing (0/10)")

    if ir_tech > 0:
        score += 10
        feedback_parts.append("Interview Round 'Technical Plant Assessment' found in DB (10/10)")
    else:
        feedback_parts.append("Interview Round 'Technical Plant Assessment' missing (0/10)")

    if ir_manager > 0:
        score += 10
        feedback_parts.append("Interview Round 'Plant Manager Interview' found in DB (10/10)")
    else:
        feedback_parts.append("Interview Round 'Plant Manager Interview' missing (0/10)")

    # ================================================================
    # 3. Requisitions (50 pts) - Checked via VLM on trajectory
    # ================================================================
    req1_pts = 0
    req2_pts = 0
    
    db_req1 = int(result.get('req_evidence_1', 0)) > 0
    db_req2 = int(result.get('req_evidence_2', 0)) > 0

    query_vlm = env_info.get('query_vlm')
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        vlm_available = query_vlm is not None
    except ImportError:
        vlm_available = False
        
    if vlm_available and traj:
        frames = sample_trajectory_frames(traj, n=6)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """
        Examine these screenshots from a Sentrifugo HRMS session.
        The user was tasked with creating Job Requisitions in the Talent Acquisition module.
        
        Check if the user successfully created these two Job Requisitions:
        
        Requisition 1:
        - Job Title: Senior Biomass Process Engineer
        - Department: Engineering
        - Number of Positions: 2
        
        Requisition 2:
        - Job Title: Field Safety Inspector
        - Department: Quality Assurance
        - Number of Positions: 3
        
        Respond with a JSON object containing boolean flags:
        {
            "req1_created": true/false,
            "req1_correct_positions_and_dept": true/false,
            "req2_created": true/false,
            "req2_correct_positions_and_dept": true/false
        }
        """
        
        try:
            vlm_result = query_vlm(prompt=prompt, images=images)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                req1_created = parsed.get("req1_created", False)
                req1_perfect = parsed.get("req1_correct_positions_and_dept", False)
                req2_created = parsed.get("req2_created", False)
                req2_perfect = parsed.get("req2_correct_positions_and_dept", False)
                
                if req1_created:
                    req1_pts += 15
                    if req1_perfect:
                        req1_pts += 10
                        feedback_parts.append("VLM verified Requisition 1 completely (25/25)")
                    else:
                        feedback_parts.append("VLM verified Requisition 1 partially (15/25)")
                elif db_req1:
                    req1_pts += 15
                    feedback_parts.append("DB evidence found for Requisition 1 (15/25)")
                else:
                    feedback_parts.append("Requisition 1 not found (0/25)")
                    
                if req2_created:
                    req2_pts += 15
                    if req2_perfect:
                        req2_pts += 10
                        feedback_parts.append("VLM verified Requisition 2 completely (25/25)")
                    else:
                        feedback_parts.append("VLM verified Requisition 2 partially (15/25)")
                elif db_req2:
                    req2_pts += 15
                    feedback_parts.append("DB evidence found for Requisition 2 (15/25)")
                else:
                    feedback_parts.append("Requisition 2 not found (0/25)")
            else:
                raise Exception("VLM call unsuccessful")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback
            if db_req1:
                req1_pts += 15
                feedback_parts.append("DB evidence found for Requisition 1 (15/25)")
            else:
                feedback_parts.append("Requisition 1 not found (0/25)")
                
            if db_req2:
                req2_pts += 15
                feedback_parts.append("DB evidence found for Requisition 2 (15/25)")
            else:
                feedback_parts.append("Requisition 2 not found (0/25)")
    else:
        # Fallback to DB hints completely if VLM fails to import/init
        if db_req1:
            req1_pts += 15
            feedback_parts.append("DB evidence found for Requisition 1 (15/25)")
        else:
            feedback_parts.append("Requisition 1 not found (0/25)")
            
        if db_req2:
            req2_pts += 15
            feedback_parts.append("DB evidence found for Requisition 2 (15/25)")
        else:
            feedback_parts.append("Requisition 2 not found (0/25)")

    score += req1_pts + req2_pts
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }