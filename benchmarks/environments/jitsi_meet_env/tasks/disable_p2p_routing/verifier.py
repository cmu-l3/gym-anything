#!/usr/bin/env python3
"""
Verifier for disable_p2p_routing task.

Verifies:
1. Config file exists and contains correct P2P disable settings (30 pts)
2. Web server is serving the new config (implies restart) (20 pts)
3. Evidence screenshot exists (10 pts)
4. VLM: Evidence screenshot shows 2 participants (20 pts)
5. VLM: Evidence screenshot shows JVB/Bridge connection status (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_p2p_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Config File Check (30 pts)
    if result.get("config_correct_fs", False):
        score += 30
        feedback.append("Config file correctly modified (Filesystem).")
    elif result.get("config_exists", False):
        score += 10
        feedback.append("Config file exists but content incorrect.")
    else:
        feedback.append("Config file not created.")

    # 2. HTTP Serving Check (20 pts)
    # This proves the container was restarted and changes applied
    if result.get("config_correct_http", False):
        score += 20
        feedback.append("Jitsi web server is serving new config (Restart confirmed).")
    else:
        feedback.append("Jitsi web server NOT serving new config (Did you restart?).")

    # 3. Evidence Screenshot Exists (10 pts)
    evidence_exists = result.get("evidence_exists", False)
    if evidence_exists:
        score += 10
        feedback.append("Evidence screenshot created.")
    else:
        feedback.append("Evidence screenshot missing.")

    # 4 & 5. VLM Verification of Evidence (40 pts total)
    # We verify the screenshot the AGENT took, as it captures the specific popover state
    vlm_score = 0
    if evidence_exists:
        # Retrieve the evidence image
        local_evidence_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            # The export script copies evidence to /tmp/agent_evidence.png
            copy_from_env("/tmp/agent_evidence.png", local_evidence_path)
            
            prompt = """
            Analyze this screenshot of a Jitsi Meet video call.
            
            Check for two specific things:
            1. MULTI_PARTY: Are there at least two participants visible in the meeting (e.g. two video tiles, or a 'Patient' and 'Doctor')?
            2. CONNECTION_MODE: Is a "Connection Status" popover or dialog open? If so, does it indicate "JVB", "Bridge", or "UDP"? It should NOT say "P2P".
            
            Return JSON:
            {
                "two_participants_visible": true/false,
                "connection_details_visible": true/false,
                "uses_jvb_bridge": true/false,
                "uses_p2p": true/false,
                "reasoning": "..."
            }
            """
            
            vlm_response = query_vlm(prompt=prompt, image=local_evidence_path)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                # Criteria 4: Two participants (20 pts)
                if parsed.get("two_participants_visible"):
                    vlm_score += 20
                    feedback.append("VLM confirmed 2 participants visible.")
                else:
                    feedback.append("VLM did not see 2 participants.")

                # Criteria 5: JVB Connection confirmed (20 pts)
                if parsed.get("connection_details_visible"):
                    if parsed.get("uses_jvb_bridge") and not parsed.get("uses_p2p"):
                        vlm_score += 20
                        feedback.append("VLM confirmed JVB/Bridge connection status.")
                    elif parsed.get("uses_p2p"):
                        feedback.append("VLM detected P2P connection (Failed).")
                    else:
                        feedback.append("VLM saw connection details but could not determine type.")
                else:
                    feedback.append("VLM did not see Connection Status popover.")
            
            else:
                feedback.append(f"VLM analysis failed: {vlm_response.get('error')}")

        except Exception as e:
            feedback.append(f"Failed to retrieve evidence for VLM: {e}")
        finally:
            if os.path.exists(local_evidence_path):
                os.unlink(local_evidence_path)
    
    score += vlm_score

    # Final Pass/Fail
    # Pass requires: Config Correct (FS) + Server Updated (HTTP) + VLM confirms JVB (at least partially)
    # Threshold: 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }