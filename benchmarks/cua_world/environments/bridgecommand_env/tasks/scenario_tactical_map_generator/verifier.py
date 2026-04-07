#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tactical_map(traj, env_info, task_info):
    """
    Verifies the Scenario Tactical Map Generator task.
    
    Strategy:
    1. Functional: Did the agent's script run on the hidden scenario? (Crucial for generalization)
    2. Visual (Public): Did it generate a map for the Portsmouth scenario?
    3. Visual (Hidden): VLM check on the map generated from the hidden scenario.
    4. Code Analysis: Does it take CLI args?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy artifacts
    result_path = tempfile.mktemp(suffix=".json")
    public_img_path = tempfile.mktemp(suffix=".png")
    hidden_img_path = tempfile.mktemp(suffix=".png")
    
    try:
        copy_from_env("/tmp/task_result.json", result_path)
        # Try to copy images if they exist
        try: copy_from_env("/tmp/public_map.png", public_img_path) 
        except: pass
        try: copy_from_env("/tmp/hidden_map.png", hidden_img_path) 
        except: pass
        
        with open(result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(result_path): os.unlink(result_path)

    score = 0
    feedback = []
    
    # 1. Script Existence (10 pts)
    if result.get("script_found"):
        score += 10
        feedback.append("Script found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Script 'generate_tactical_map.py' not found on Desktop or home."}

    # 2. Argument Handling (10 pts)
    # Simple check: did it pass the public run? The public run uses CLI args.
    # Also check code snippet for sys.argv or argparse
    code_snippet = result.get("script_content_snippet", "")
    if "sys.argv" in code_snippet or "argparse" in code_snippet:
        score += 10
        feedback.append("CLI argument handling detected.")
    else:
        feedback.append("Warning: CLI argument handling not explicitly detected in snippet.")

    # 3. Public Scenario Execution (20 pts)
    if result.get("public_run_success"):
        score += 10
        feedback.append("Script executed successfully on Portsmouth scenario.")
        if result.get("public_image_exists"):
            score += 10
            feedback.append("Public tactical map image generated.")
        else:
            feedback.append("Public run finished but no image found.")
    else:
        feedback.append("Script failed to run on Portsmouth scenario.")

    # 4. Hidden Scenario Execution (Generalization) (30 pts)
    # This proves the script isn't hardcoded
    if result.get("hidden_run_success"):
        score += 15
        feedback.append("Script executed successfully on HIDDEN validation scenario.")
        if result.get("hidden_image_exists"):
            score += 15
            feedback.append("Hidden tactical map image generated.")
        else:
            feedback.append("Hidden run finished but no image found.")
    else:
        feedback.append("Script failed to run on HIDDEN scenario (Parsing logic likely fragile).")

    # 5. VLM Content Verification (30 pts)
    # We verify the HIDDEN map because we know exactly what it should look like (3 ships total)
    # Secret Ownship (0,0), Secret Traffic 1 (0.01, 0.01), Secret Traffic 2 (-0.01, -0.01)
    # It's a diagonal arrangement.
    
    vlm_score = 0
    if result.get("hidden_image_exists") and os.path.exists(hidden_img_path):
        from gym_anything.vlm import query_vlm
        
        prompt = """
        You are verifying a generated tactical map from a ship simulator.
        The map should display:
        1. Three distinct vessels (arrows or points).
        2. Text labels next to the vessels.
        3. A blue arrow (Ownship) and red arrows (Traffic), though colors might vary.
        
        Does this image look like a valid tactical map with exactly 3 vessels plotted?
        Respond JSON: {"valid_map": bool, "vessel_count_approx": int, "has_labels": bool}
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=hidden_img_path)
            if vlm_resp and vlm_resp.get("success"):
                data = vlm_resp.get("parsed", {})
                if data.get("valid_map"):
                    vlm_score += 10
                    feedback.append("VLM confirms valid map structure.")
                if data.get("has_labels"):
                    vlm_score += 10
                    feedback.append("VLM confirms text labels present.")
                
                count = data.get("vessel_count_approx", 0)
                if 2 <= count <= 4: # Tolerance for VLM counting
                    vlm_score += 10
                    feedback.append(f"VLM counted {count} vessels (Expected 3).")
                else:
                    feedback.append(f"VLM counted {count} vessels (Expected 3).")
            else:
                feedback.append("VLM verification failed to parse.")
        except Exception as e:
            feedback.append(f"VLM verification error: {str(e)}")
            # Fallback points if image exists and script ran
            vlm_score += 10 
            
    score += vlm_score

    # Final tally
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }