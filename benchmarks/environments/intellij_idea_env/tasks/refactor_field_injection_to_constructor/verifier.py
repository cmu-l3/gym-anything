#!/usr/bin/env python3
"""
Verifier for refactor_field_injection_to_constructor task.

Criteria:
1. Compilation Success (20 pts)
2. Tests Pass (20 pts)
3. Fields are 'private final' (20 pts)
4. Constructor Injection used (public constructor with args) (20 pts)
5. @Autowired removed from fields (20 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_field_injection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Compilation (20 pts)
    if result.get('build_success', False):
        score += 20
        feedback.append("Project compiles successfully.")
    else:
        feedback.append("Project compilation failed.")

    # 2. Tests (20 pts)
    if result.get('tests_passed', False):
        score += 20
        feedback.append("Tests passed.")
    else:
        feedback.append("Tests failed.")

    # Content Analysis
    content = result.get('target_file_content', '')
    if not content:
        return {"passed": False, "score": 0, "feedback": "Target file not found or empty."}

    # 3. Check for final fields (20 pts)
    # Regex to find 'private final Type name' or 'private final name'
    # The original fields were: private InventoryService inventoryService;
    # We expect: private final InventoryService inventoryService;
    fields = ['InventoryService', 'PaymentGateway', 'NotificationService']
    final_score = 0
    for field in fields:
        # Look for "private final InventoryService" or "final InventoryService"
        pattern = r'private\s+final\s+' + field
        if re.search(pattern, content):
            final_score += 1
    
    if final_score == 3:
        score += 20
        feedback.append("All dependency fields are marked 'final'.")
    elif final_score > 0:
        partial = int(20 * (final_score / 3))
        score += partial
        feedback.append(f"Some fields marked final ({final_score}/3).")
    else:
        feedback.append("Fields are not marked 'final'.")

    # 4. Check for Constructor (20 pts)
    # Expect public OrderProcessingService(Type a, Type b, Type c)
    # Loose check: public ClassName followed by params
    ctor_pattern = r'public\s+OrderProcessingService\s*\([^)]*InventoryService[^)]*\)'
    if re.search(ctor_pattern, content):
        score += 20
        feedback.append("Constructor with dependencies found.")
    else:
        feedback.append("No suitable constructor found.")

    # 5. Check @Autowired removal (20 pts)
    # We check that @Autowired is NOT present above fields
    # It might be present on the constructor (which is allowed/optional)
    
    # Find field declarations
    field_block_pattern = r'(@Autowired\s+)?private\s+(final\s+)?(InventoryService|PaymentGateway|NotificationService)'
    matches = re.findall(field_block_pattern, content)
    
    autowired_on_fields = 0
    for match in matches:
        if '@Autowired' in match[0]:
            autowired_on_fields += 1
            
    if autowired_on_fields == 0:
        score += 20
        feedback.append("@Autowired annotation removed from fields.")
    else:
        feedback.append(f"Found @Autowired on {autowired_on_fields} fields.")

    # Check for "Do Nothing"
    if not result.get('file_modified', False):
        score = 0
        feedback = ["File was not modified. No work done."]

    # VLM Verification (Bonus/Safety)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, num_samples=3)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
        
        prompt = """
        You are verifying a Java refactoring task in IntelliJ IDEA.
        The user should have:
        1. Removed @Autowired from fields.
        2. Added a constructor.
        
        Look at the code in the editor. Does it look like they performed these actions?
        Reply with YES or NO and a brief reason.
        """
        # We don't strictly use the VLM score here unless code analysis is ambiguous,
        # but we log it.
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            feedback.append(f"VLM Observation: {vlm_res.get('response', 'No response')}")
        except:
            pass

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }