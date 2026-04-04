#!/usr/bin/env python3
"""Verifier for Refactor Parameter Object task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_introduce_parameter_object(traj, env_info, task_info):
    """
    Verify that the Introduce Parameter Object refactoring was applied correctly.
    
    Criteria:
    1. SeatDetails.java exists (20 pts)
    2. SeatDetails contains the 5 correct fields (20 pts)
    3. BookingService.java method signature uses SeatDetails (20 pts)
    4. BookingService.java method signature removed old params (10 pts)
    5. BookingApp.java call sites updated (20 pts)
    6. Project compiles (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Read result
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 1. Check New Class Existence (20 pts)
    if result.get("new_class_exists", False):
        score += 20
        feedback_parts.append("SeatDetails.java created")
        
        # 2. Check New Class Content (20 pts)
        content = result.get("new_class_content", "")
        required_fields = ["seatRow", "seatLetter", "window", "aisle", "exitRow"]
        missing_fields = [f for f in required_fields if f not in content]
        
        if not missing_fields:
            score += 20
            feedback_parts.append("SeatDetails has all required fields")
        else:
            # Partial credit
            found = len(required_fields) - len(missing_fields)
            points = int((found / 5.0) * 20)
            score += points
            feedback_parts.append(f"SeatDetails missing fields: {missing_fields}")
    else:
        feedback_parts.append("SeatDetails.java NOT found")

    # 3 & 4. Check BookingService Signature (30 pts total)
    service_content = result.get("service_content", "")
    if "SeatDetails" in service_content:
        score += 20
        feedback_parts.append("BookingService uses SeatDetails")
        
        # Check if old params are gone from signature
        # We look for the method definition line(s)
        # Simple check: "String seatRow" should NOT be present in the signature
        # But allow for it in comments or variable assignments, so regex is tricky.
        # However, checking if "String seatRow" appears *less* than before is hard without baseline.
        # Better: check if signature contains SeatDetails AND DOES NOT contain "boolean window" etc in signature part.
        
        # Heuristic: Check for absence of specific type-name pairs that should have moved
        leftover_params = []
        if "String seatRow" in service_content and "createBooking" in service_content:
            leftover_params.append("seatRow")
        if "boolean window" in service_content and "createBooking" in service_content:
            leftover_params.append("window")
            
        if not leftover_params:
            score += 10
            feedback_parts.append("Old parameters removed from signature")
        else:
            feedback_parts.append("Old parameters still present in code (signature might be incomplete)")
    else:
        feedback_parts.append("BookingService does NOT seem to use SeatDetails")

    # 5. Check Call Site Update (20 pts)
    app_content = result.get("app_content", "")
    if "new SeatDetails" in app_content or "SeatDetails " in app_content:
        score += 20
        feedback_parts.append("BookingApp updated to instantiate SeatDetails")
    else:
        feedback_parts.append("BookingApp does not instantiate SeatDetails")

    # 6. Check Compilation (10 pts)
    if result.get("compile_success", False):
        score += 10
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append(f"Compilation failed: {result.get('compile_log', '')}")

    # VLM Verification (Bonus/Confirmation)
    # We check if the refactoring dialog was used
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Refactor 'createBooking' method to introduce 'SeatDetails' parameter object",
            checklist_items=[
                "FlightSystem project is imported",
                "BookingService.java is open",
                "Introduce Parameter Object dialog visible",
                "SeatDetails class name entered",
                "Correct parameters selected for extraction",
                "Refactoring applied successfully"
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            # VLM confirms UI interaction, good validation
            feedback_parts.append("VLM confirms refactoring workflow")
    except Exception:
        pass

    passed = score >= 90
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }