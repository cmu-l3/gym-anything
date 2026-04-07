#!/usr/bin/env python3
"""
Verifier for Audit Consult Services task in VistA.

Verification Strategy:
1. File Verification: Check if `consult_services_audit.txt` exists and was created during the task.
2. Content Verification: Read the file and match listed names against the actual VistA database (ground truth).
3. Visual Verification: Use VLM to confirm the agent navigated to ^GMR(123.5).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_consult_services(traj, env_info, task_info):
    """
    Verify the agent audited consult services correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    metadata = task_info.get('metadata', {})
    min_services = metadata.get('min_services_required', 3)

    score = 0
    feedback_parts = []
    subscores = {}

    # ================================================================
    # 1. Retrieve Result Files from Environment
    # ================================================================
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        user_output_path = os.path.join(temp_dir, "consult_services_audit.txt")
        ground_truth_path = os.path.join(temp_dir, "valid_consult_services.txt")

        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Retrieve user output file if it exists
        if result.get('file_exists'):
            try:
                copy_from_env(result['output_file_path'], user_output_path)
            except Exception as e:
                logger.warning(f"Could not copy user output file: {e}")

        # Retrieve ground truth file
        try:
            copy_from_env(result['ground_truth_path'], ground_truth_path)
        except Exception as e:
            logger.warning(f"Could not copy ground truth file: {e}")

        # ================================================================
        # 2. Verify File Creation (10 Points)
        # ================================================================
        if result.get('file_exists') and result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("Report file created successfully")
            subscores['file_creation'] = True
        elif result.get('file_exists'):
            score += 5
            feedback_parts.append("Report file exists but timestamp is old")
            subscores['file_creation'] = False
        else:
            feedback_parts.append("Report file NOT found")
            subscores['file_creation'] = False

        # ================================================================
        # 3. Verify Content - Match Names (50 Points)
        # ================================================================
        valid_services_set = set()
        if os.path.exists(ground_truth_path):
            with open(ground_truth_path, 'r') as f:
                # Normalize ground truth to uppercase for case-insensitive matching
                valid_services_set = {line.strip().upper() for line in f if line.strip()}
        
        valid_count = 0
        reported_services = []

        if os.path.exists(user_output_path):
            with open(user_output_path, 'r') as f:
                for line in f:
                    clean_line = line.strip().upper()
                    if not clean_line:
                        continue
                    reported_services.append(clean_line)
                    
                    # Check exact match or substring match (e.g., "CARDIOLOGY" matching "CARDIOLOGY SERVICE")
                    # We check if the reported name appears in any valid service name
                    is_valid = False
                    if clean_line in valid_services_set:
                        is_valid = True
                    else:
                        for valid in valid_services_set:
                            if clean_line in valid: # Relaxed matching
                                is_valid = True
                                break
                    
                    if is_valid:
                        valid_count += 1
        
        # Scoring Logic for Content
        # Cap at min_services required
        points_per_service = 50 / min_services
        content_score = min(valid_count, min_services) * points_per_service
        score += int(content_score)
        
        feedback_parts.append(f"Found {valid_count} valid service names in report (required: {min_services})")
        subscores['content_validity'] = valid_count >= min_services

        # ================================================================
        # 4. VLM Verification - Trajectory Analysis (40 Points)
        # ================================================================
        vlm_success = False
        # Use trajectory frames for robust verification
        from gym_anything.vlm import sample_trajectory_frames
        
        frames = sample_trajectory_frames(traj, n=4) # Sample 4 frames from history
        final_frame = traj.get('final_screenshot') or (frames[-1] if frames else None)
        
        if query_vlm and frames:
            # We want to see if they accessed ^GMR(123.5)
            # We check multiple frames to catch the navigation
            
            prompt = """
            Analyze this sequence of screenshots from a VistA database task.
            
            The user should be navigating to the global '^GMR(123.5)' (Request Services file).
            
            Look for:
            1. The text "^GMR" or "123.5" in a Global Viewer or search box.
            2. A list of service names like "MEDICINE", "SURGERY", "CARDIOLOGY".
            3. The browser title containing "Global" or "YDBGui".
            
            Does the user appear to have successfully navigated to the Request Services global?
            Return JSON: {"navigated": boolean, "evidence": "string"}
            """
            
            # Send frames to VLM
            try:
                # We combine frames into a single query or query the most likely frame
                # For simplicity/cost, let's check the final frame + one middle frame
                check_frames = [frames[len(frames)//2], final_frame] if final_frame else frames
                
                # Check frames individually or as a set depending on VLM capability. 
                # Assuming standard query_vlm handles single image, we iterate or select best.
                # Here we check the final frame primarily.
                
                vlm_resp = query_vlm(image=final_frame, prompt=prompt)
                
                if vlm_resp and vlm_resp.get('parsed', {}).get('navigated', False):
                    vlm_success = True
                elif len(frames) > 1:
                     # Fallback: check a middle frame if final frame doesn't show it (maybe they closed it)
                     vlm_resp_mid = query_vlm(image=frames[len(frames)//2], prompt=prompt)
                     if vlm_resp_mid and vlm_resp_mid.get('parsed', {}).get('navigated', False):
                         vlm_success = True
                
                if vlm_success:
                    score += 40
                    feedback_parts.append("Visual verification passed: ^GMR(123.5) accessed")
                else:
                    feedback_parts.append("Visual verification failed: Could not confirm navigation to ^GMR(123.5)")
                    
            except Exception as e:
                logger.error(f"VLM error: {e}")
                feedback_parts.append("VLM verification skipped due to error")

        # ================================================================
        # Final Score Calculation
        # ================================================================
        passed = (score >= 65) and (valid_count >= 1)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "file_exists": result.get('file_exists'),
                "valid_names_found": valid_count,
                "vlm_passed": vlm_success,
                "reported_names": reported_services[:5] # Log first 5 for debug
            }
        }