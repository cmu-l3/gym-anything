#!/usr/bin/env python3
"""Verifier for apply_source_cleanup task."""

import json
import tempfile
import os
import re
import logging
import glob

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_apply_source_cleanup(traj, env_info, task_info):
    """Verify that code quality issues were resolved in the InventoryManager project.

    Criteria:
    1. Clean compilation (0 errors, 0 warnings) - 30 pts
    2. Code analysis (using patterns) - 50 pts
       - No unused imports
       - No raw types
       - No '==' for strings
       - No unnecessary boxing
       - @Override present
    3. VLM verification of UI usage - 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    forbidden_patterns = metadata.get('forbidden_patterns', {})
    required_patterns = metadata.get('required_patterns', {})

    score = 0
    feedback_parts = []

    # --- Step 1: Check Compilation Result (30 pts) ---
    compile_result = {}
    try:
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_res.close()
        copy_from_env("/tmp/task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            compile_result = json.load(f)
        os.unlink(tmp_res.name)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")

    error_count = compile_result.get('error_count', 999)
    warning_count = compile_result.get('warning_count', 999)

    if error_count == 0:
        score += 15
        feedback_parts.append("Project compiles successfully (0 errors)")
        if warning_count == 0:
            score += 15
            feedback_parts.append("No compiler warnings remaining")
        else:
            feedback_parts.append(f"Compiler warnings still present: {warning_count}")
    else:
        feedback_parts.append(f"Compilation failed with {error_count} errors")

    # --- Step 2: Source Code Analysis (50 pts) ---
    # Copy source files
    src_files = {
        "Product.java": "/tmp/export_src/Product.java",
        "Category.java": "/tmp/export_src/Category.java",
        "InventoryService.java": "/tmp/export_src/InventoryService.java"
    }
    
    local_src_content = {}
    
    for fname, remote_path in src_files.items():
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.java')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                local_src_content[fname] = f.read()
            os.unlink(tmp.name)
        except Exception:
            local_src_content[fname] = ""

    # Check Forbidden Patterns
    violations = 0
    
    # Unused Imports (10 pts)
    import_violation = False
    for pattern in forbidden_patterns.get('unused_imports', []):
        for content in local_src_content.values():
            if pattern in content:
                import_violation = True
                violations += 1
                break
    if not import_violation:
        score += 10
        feedback_parts.append("Unused imports removed")
    else:
        feedback_parts.append("Some unused imports still present")

    # Raw Types (10 pts)
    raw_type_violation = False
    for pattern in forbidden_patterns.get('raw_types', []):
        for content in local_src_content.values():
            if pattern in content:
                raw_type_violation = True
                violations += 1
                break
    if not raw_type_violation:
        score += 10
        feedback_parts.append("Raw types fixed")
    else:
        feedback_parts.append("Raw types still present")

    # String Equality (10 pts)
    string_eq_violation = False
    for pattern in forbidden_patterns.get('string_equality', []):
        for content in local_src_content.values():
            if pattern in content:
                string_eq_violation = True
                violations += 1
                break
    if not string_eq_violation:
        score += 10
        feedback_parts.append("String equality (==) fixed")
    else:
        feedback_parts.append("String comparison using '==' found")

    # Unnecessary Boxing (10 pts)
    boxing_violation = False
    for pattern in forbidden_patterns.get('unnecessary_boxing', []):
        for content in local_src_content.values():
            if pattern in content:
                boxing_violation = True
                violations += 1
                break
    if not boxing_violation:
        score += 10
        feedback_parts.append("Unnecessary boxing removed")
    else:
        feedback_parts.append("Unnecessary boxing still present")

    # Check Required Patterns (@Override) (10 pts)
    override_missing = False
    for pattern in required_patterns.get('override_annotation', []):
        found = False
        for content in local_src_content.values():
            if re.search(pattern, content):
                found = True
                break
        if not found:
            override_missing = True
    
    if not override_missing:
        score += 10
        feedback_parts.append("@Override annotations added")
    else:
        feedback_parts.append("Missing @Override annotations")

    # --- Step 3: VLM Verification (20 pts) ---
    try:
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task
        import sys

        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Clean up Java source code using Eclipse 'Source > Clean Up' wizard and fix warnings in Problems view.",
            checklist_items=[
                "Eclipse IDE is open",
                "Problems view is visible (showing warnings)",
                "Source > Clean Up... menu or dialog is visible",
                "Clean Up profile configuration dialog is visible",
                "Agent is editing Java source files",
                "Final state shows 0 warnings in Problems view"
            ]
        )
        
        if vlm_result:
            vlm_score = vlm_result.get('vlm_score', 0)
            # Scale 0-100 to 0-20
            score += int(vlm_score * 0.2)
            feedback_parts.append(f"VLM Analysis: {vlm_result.get('vlm_feedback', '')}")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback points if VLM fails but code is perfect
        if score >= 70:
            score += 10
            feedback_parts.append("VLM skipped, bonus for perfect code")

    passed = score >= 60 and error_count == 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }