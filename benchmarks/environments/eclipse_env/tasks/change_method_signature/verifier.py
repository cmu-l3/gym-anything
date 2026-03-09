#!/usr/bin/env python3
"""Verifier for change_method_signature task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_method_signature(traj, env_info, task_info):
    """Verify that the PaymentService.processPayment signature was changed correctly.
    
    Criteria:
    1. PaymentService.java signature updated (20 pts)
    2. 'currency' parameter present (10 pts)
    3. 'priority' parameter present (10 pts)
    4. Call sites updated across 6+ files (40 pts)
    5. Project compiles (10 pts)
    6. VLM Verification (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    files = result.get('files', {})
    
    # 1. Verify Method Signature in PaymentService.java
    service_code = files.get("PaymentService.java", "")
    
    # We look for: processPayment(String ..., double ..., String currency, boolean priority)
    # The order of original params usually stays, new ones added. Refactoring tool allows reordering but task implies adding.
    # Regex allows for flexibility in variable names of first two, but demands specific types and names for new ones.
    
    sig_pattern = r'public\s+PaymentResult\s+processPayment\s*\(\s*String\s+\w+\s*,\s*double\s+\w+\s*,\s*String\s+currency\s*,\s*boolean\s+priority\s*\)'
    
    if re.search(sig_pattern, service_code):
        score += 40  # 20 for sig + 10 currency + 10 priority
        feedback_parts.append("Method signature updated correctly")
    else:
        # Partial credit checks
        if "String currency" in service_code:
            score += 10
            feedback_parts.append("currency parameter found")
        if "boolean priority" in service_code:
            score += 10
            feedback_parts.append("priority parameter found")
        feedback_parts.append("Method signature incorrect or incomplete")

    # 2. Verify Compilation
    if result.get("compilation_success"):
        score += 10
        feedback_parts.append("Project compiles")
    else:
        feedback_parts.append("Project compilation FAILED")

    # 3. Verify Call Sites (Total 40 pts)
    # We check a few key files to ensure the refactoring propagated
    
    # Expected pattern: .processPayment(arg1, arg2, "USD", false)
    # We'll allow mild whitespace variations
    call_pattern = r'\.processPayment\s*\([^,]+,[^,]+,\s*"USD"\s*,\s*false\s*\)'
    
    callers = [
        "OrderProcessor.java", 
        "SubscriptionManager.java", 
        "RefundHandler.java",
        "BatchProcessor.java",
        "CheckoutController.java",
        "PaymentServiceTest.java"
    ]
    
    updated_files = 0
    for filename in callers:
        content = files.get(filename, "")
        # Check if the file contains the UPDATED call
        if re.search(call_pattern, content):
            updated_files += 1
        # Check if it contains OLD call (bad!)
        elif re.search(r'\.processPayment\s*\([^,]+,[^,]+\)', content):
            feedback_parts.append(f"{filename} still has old call style")

    # Calculate points for callers (capped at 40)
    # 6 files * ~6.6 pts = 40 pts. Let's do simple scaling.
    caller_points = int((updated_files / len(callers)) * 40)
    score += caller_points
    feedback_parts.append(f"{updated_files}/{len(callers)} files updated correctly")

    # 4. VLM Verification (10 pts)
    # Check if the refactoring dialog was used
    try:
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info, 
            task_description="Use 'Change Method Signature' refactoring to add currency and priority parameters",
            checklist_items=[
                "Eclipse Refactoring menu or context menu opened",
                "Change Method Signature dialog visible",
                "Parameters 'currency' and 'priority' being added in dialog",
                "Default value 'USD' or 'false' being entered"
            ]
        )
        
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 10, 100) # Bonus/Gap filler
            feedback_parts.append("VLM: Refactoring dialog usage verified")
    except Exception:
        pass

    passed = score >= 70 and result.get("compilation_success")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }