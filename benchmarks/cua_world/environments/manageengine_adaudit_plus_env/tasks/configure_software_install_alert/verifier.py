#!/usr/bin/env python3
"""
Verifier for configure_software_install_alert task.

Verifies:
1. Alert Profile creation in ADAudit Plus.
2. Specific settings: Name, Category, Severity.
3. Evidence: Screenshot existence and timestamp.

Strategy:
- Use VLM to analyze the final screenshot captured by the agent.
- Verify file metadata (existence, creation time).
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))
# from vlm_utils import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_software_install_alert(traj, env_info, task_info):
    """
    Verify the software installation alert configuration.
    """
    # 1. Setup and Resource Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_profile_name = metadata.get('expected_profile_name', 'Unauthorized_Software_Detection')
    
    # 2. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        # Copy from the specific Windows path defined in export_result.ps1
        # Note: copy_from_env arguments are (container_path, local_path)
        # Windows paths in container usually work with forward slashes in some docker contexts,
        # or we might need to be careful. Assuming standard behavior for the env.
        copy_from_env("C:/workspace/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Retrieve Evidence Screenshot
    screenshot_path_in_container = result_data.get("screenshot_path")
    local_screenshot = None
    
    if result_data.get("output_exists") and screenshot_path_in_container:
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            # Normalize path separators if needed, though most copy impls handle it
            remote_path = screenshot_path_in_container.replace('\\', '/')
            copy_from_env(remote_path, temp_img.name)
            local_screenshot = temp_img.name
        except Exception as e:
            logger.warning(f"Failed to copy screenshot: {e}")

    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion A: File Evidence (20 points)
    if result_data.get("output_exists"):
        score += 10
        if result_data.get("file_created_during_task"):
            score += 10
            feedback_parts.append("Evidence screenshot created.")
        else:
            feedback_parts.append("Evidence screenshot exists but timestamp is old.")
    else:
        feedback_parts.append("No evidence screenshot found.")

    # Criterion B: VLM Analysis (80 points)
    # We rely on the `query_vlm` function injected into the verifier context or importable
    # If not available, we assume failure or mock for this generation
    
    vlm_passed = False
    if local_screenshot:
        try:
            # We assume query_vlm is available in the global scope or imported
            # If strictly following the 'no exec_in_env' rule and using standard libraries provided
            # The prompt implies we write the verifier code. We need to construct the VLM call.
            # Standard gym_anything pattern uses `query_vlm` from vlm_utils (not provided here but assumed available in runtime)
            # OR we mock it if we can't import. 
            # Based on previous examples (Example 1), verifier calls `query_vlm`.
            
            # Since I cannot import `query_vlm` (it's part of the framework), I will assume it's passed or importable.
            # I will check if it's in `env_info` or `task_info`? No, usually it's a utility.
            # I'll try to import it, and fail gracefully.
            
            from gym_anything.vlm import query_vlm
            
            prompt = f"""
            Analyze this screenshot of ManageEngine ADAudit Plus.
            
            Goal: Verify if an Alert Profile named '{expected_profile_name}' is correctly configured.
            
            Check for:
            1. The text '{expected_profile_name}' appears in the Name field or list.
            2. The Category/Report is related to 'Software Installation' or 'Software Installed'.
            3. The Severity is marked as 'Critical' (look for the word Critical or a Red icon).
            
            Return JSON:
            {{
                "profile_name_found": boolean,
                "category_correct": boolean,
                "severity_critical": boolean,
                "reasoning": "string"
            }}
            """
            
            vlm_response = query_vlm(images=[local_screenshot], prompt=prompt)
            
            # Parse VLM result
            # Assuming vlm_response is a dict or object with the JSON content
            # If it returns a string, we might need to parse. 
            # The framework usually returns a dict if we asked for JSON, or we check content.
            
            # Mocking parsing logic for robustness
            parsed = {}
            if isinstance(vlm_response, dict):
                parsed = vlm_response
            else:
                # Attempt to find JSON in text
                import re
                json_match = re.search(r'\{.*\}', str(vlm_response), re.DOTALL)
                if json_match:
                    parsed = json.loads(json_match.group(0))
            
            vlm_score = 0
            if parsed.get("profile_name_found"):
                vlm_score += 30
                feedback_parts.append("Profile name verified.")
            else:
                feedback_parts.append("Profile name NOT found in screenshot.")
                
            if parsed.get("category_correct"):
                vlm_score += 30
                feedback_parts.append("Category verified as Software Installation.")
            else:
                feedback_parts.append("Incorrect category detected.")

            if parsed.get("severity_critical"):
                vlm_score += 20
                feedback_parts.append("Severity verified as Critical.")
            else:
                feedback_parts.append("Severity is not Critical.")
                
            score += vlm_score
            vlm_passed = True
            
        except ImportError:
            # Fallback if VLM lib missing in dev environment
            feedback_parts.append("VLM verification skipped (library missing).")
            # For safety in generated code, we might fail or give partial credit if file exists
            pass
        except Exception as e:
            feedback_parts.append(f"VLM analysis failed: {str(e)}")
            
    finally:
        if local_screenshot and os.path.exists(local_screenshot):
            os.unlink(local_screenshot)

    # Final Pass/Fail
    # Pass if score >= 80 (Meaning at least File + Name + Category + Severity mostly correct)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }