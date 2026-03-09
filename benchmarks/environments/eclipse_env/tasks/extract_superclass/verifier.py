#!/usr/bin/env python3
"""Verifier for Extract Superclass task."""

import json
import tempfile
import os
import re
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_superclass(traj, env_info, task_info):
    """
    Verify the Extract Superclass refactoring task.

    Criteria:
    1. AbstractNotificationService.java exists (10 pts)
    2. AbstractNotificationService is abstract (5 pts)
    3. Contains shared fields (15 pts)
    4. Contains shared methods (15 pts)
    5. Subclasses extend superclass (16 pts total)
    6. Subclasses do not contain duplicated code (14 pts total)
    7. Project compiles (10 pts)
    8. Tests pass (10 pts)
    9. VLM verification (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/eclipse-workspace/notification-system')
    package_path = metadata.get('package_path', 'src/main/java/com/acme/notify')

    score = 0
    feedback_parts = []
    details = {}

    # Load result JSON from export_result.sh
    task_result = {}
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env('/tmp/task_result.json', tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        logger.warning(f"Failed to read task result: {e}")

    # Helper to read remote file content
    def read_remote_file(path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    # --- Structural Verification ---

    # 1. Check Superclass existence (10 pts)
    superclass_content = read_remote_file(f"{project_dir}/{package_path}/AbstractNotificationService.java")
    if superclass_content:
        score += 10
        feedback_parts.append("AbstractNotificationService.java created")
        
        # 2. Check Abstract keyword (5 pts)
        if re.search(r'public\s+abstract\s+class\s+AbstractNotificationService', superclass_content):
            score += 5
            feedback_parts.append("Class is abstract")
        else:
            feedback_parts.append("Class is NOT abstract")

        # 3. Check Shared Fields (15 pts)
        fields = metadata.get('shared_fields', [])
        found_fields = 0
        for field in fields:
            if re.search(rf'(private|protected)\s+\w+\s+{field}\b', superclass_content):
                found_fields += 1
        
        field_score = int(15 * (found_fields / len(fields))) if fields else 15
        score += field_score
        feedback_parts.append(f"Shared fields: {found_fields}/{len(fields)}")

        # 4. Check Shared Methods (15 pts)
        methods = metadata.get('shared_methods', [])
        found_methods = 0
        for method in methods:
            if re.search(rf'(public|protected)\s+\w+\s+{method}\s*\(', superclass_content):
                found_methods += 1
        
        method_score = int(15 * (found_methods / len(methods))) if methods else 15
        score += method_score
        feedback_parts.append(f"Shared methods: {found_methods}/{len(methods)}")

    else:
        feedback_parts.append("AbstractNotificationService.java NOT found")

    # 5. Check Subclasses Inheritance (16 pts)
    email_content = read_remote_file(f"{project_dir}/{package_path}/EmailNotificationService.java")
    sms_content = read_remote_file(f"{project_dir}/{package_path}/SMSNotificationService.java")

    if email_content and "extends AbstractNotificationService" in email_content:
        score += 8
        feedback_parts.append("EmailService extends superclass")
    else:
        feedback_parts.append("EmailService inheritance missing")

    if sms_content and "extends AbstractNotificationService" in sms_content:
        score += 8
        feedback_parts.append("SMSService extends superclass")
    else:
        feedback_parts.append("SMSService inheritance missing")

    # 6. Check Code Removal from Subclasses (14 pts)
    # The fields should NOT be in the subclasses anymore
    duplication_penalty = 0
    if email_content:
        if "private String serviceName" in email_content: duplication_penalty += 3
        if "private boolean enabled" in email_content: duplication_penalty += 2
        if "public boolean isEnabled()" in email_content: duplication_penalty += 2
    
    if sms_content:
        if "private String serviceName" in sms_content: duplication_penalty += 3
        if "private boolean enabled" in sms_content: duplication_penalty += 2
        if "public boolean isEnabled()" in sms_content: duplication_penalty += 2

    deduction = min(14, duplication_penalty)
    score += (14 - deduction)
    if deduction > 0:
        feedback_parts.append(f"Code duplication found (-{deduction} pts)")
    else:
        feedback_parts.append("Duplicated code removed successfully")

    # 7. Check Compilation (10 pts)
    if task_result.get('compile_exit_code') == 0:
        score += 10
        feedback_parts.append("Project compiles")
    else:
        feedback_parts.append("Compilation FAILED")

    # 8. Check Tests (10 pts)
    tests_run = task_result.get('tests_run', 0)
    tests_failed = task_result.get('tests_failed', 0)
    tests_errors = task_result.get('tests_errors', 0)

    if tests_run > 0 and tests_failed == 0 and tests_errors == 0:
        score += 10
        feedback_parts.append(f"All {tests_run} tests passed")
    elif tests_run > 0:
        # Partial credit if some tests ran but failed
        score += 5
        feedback_parts.append(f"Tests failed: {tests_failed}/{tests_run}")
    else:
        feedback_parts.append("No tests run")

    # 9. VLM Verification (5 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        from utils.eclipse_verification_utils import vlm_verify_eclipse_task
        
        # We reuse the utility pattern but adapted here since we need env_info
        vlm_res = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Extract Superclass refactoring in Eclipse",
            checklist_items=[
                "Eclipse IDE is visible",
                "Refactoring dialog (Extract Superclass) was opened",
                "New AbstractNotificationService class appears in package explorer",
                "JUnit test runner shows green bar (all tests passed)"
            ]
        )
        
        if vlm_res and vlm_res.get('vlm_passed'):
            score += 5
            feedback_parts.append("VLM verified workflow")
    except ImportError:
        feedback_parts.append("VLM verification skipped")
    except Exception as e:
        logger.debug(f"VLM error: {e}")

    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }