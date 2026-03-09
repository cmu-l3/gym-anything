#!/usr/bin/env python3
"""Verifier for Encapsulate Field Refactoring task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_encapsulate_field(traj, env_info, task_info):
    """
    Verify the Encapsulate Field refactoring.
    
    Criteria:
    1. Project compiles successfully (30 pts)
    2. Product class fields are PRIVATE (20 pts)
    3. Product class has Getter/Setter methods (20 pts)
    4. InventoryManager uses methods, NOT direct field access (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # --- Helper to read remote files ---
    def read_remote_file(path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            tmp.close()
            copy_from_env(path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception:
            return ""

    # --- 1. Check Compilation (30 pts) ---
    result_json = read_remote_file("/tmp/task_result.json")
    compilation_success = False
    if result_json:
        try:
            res = json.loads(result_json)
            if res.get("compilation_success"):
                compilation_success = True
                score += 30
                feedback_parts.append("Project compiles successfully")
            else:
                feedback_parts.append("Project compilation FAILED")
                # If compilation fails, we can't really verify bytecode, so return early
                return {
                    "passed": False, 
                    "score": 0, 
                    "feedback": f"Critical Failure: Project does not compile. {res.get('compilation_output', '')}"
                }
        except json.JSONDecodeError:
            feedback_parts.append("Failed to parse result JSON")
    else:
        feedback_parts.append("No result JSON found")

    # --- 2. Verify Product Class Structure (40 pts total) ---
    product_bytecode = read_remote_file("/tmp/product_javap.txt")
    if product_bytecode:
        # Check Fields are Private (20 pts)
        fields = ["sku", "name", "price", "stockQuantity"]
        private_count = 0
        for field in fields:
            # Regex: look for 'private [Type] [field];'
            # Note: javap output format is like: "private java.lang.String sku;"
            if re.search(rf"private\s+.*{field};", product_bytecode):
                private_count += 1
            else:
                feedback_parts.append(f"Field '{field}' is NOT private")
        
        if private_count == 4:
            score += 20
            feedback_parts.append("All fields are private")
        else:
            partial = int((private_count / 4) * 20)
            score += partial
            feedback_parts.append(f"{private_count}/4 fields are private")

        # Check Getters/Setters Exist (20 pts)
        methods = [
            "getSku", "setSku", 
            "getName", "setName", 
            "getPrice", "setPrice", 
            "getStockQuantity", "setStockQuantity"
        ]
        method_count = 0
        for method in methods:
            if re.search(rf"public\s+.*{method}\(", product_bytecode):
                method_count += 1
        
        if method_count == 8:
            score += 20
            feedback_parts.append("All getters/setters present")
        else:
            partial = int((method_count / 8) * 20)
            score += partial
            feedback_parts.append(f"{method_count}/8 accessors present")
    else:
        feedback_parts.append("Could not read Product class bytecode")

    # --- 3. Verify References Updated (30 pts) ---
    manager_bytecode = read_remote_file("/tmp/manager_javap.txt")
    if manager_bytecode:
        # We look for direct field access instructions: getfield/putfield targeting Product fields
        # Example: Field com/inventory/core/Product.price:D
        
        # We expect ZERO direct accesses
        direct_accesses = re.findall(r"Field com/inventory/core/Product\.(sku|name|price|stockQuantity):", manager_bytecode)
        
        # We expect SOME method calls (invokevirtual)
        # Example: Method com/inventory/core/Product.getPrice:()D
        method_calls = re.findall(r"Method com/inventory/core/Product\.(get|set)", manager_bytecode)
        
        if len(direct_accesses) == 0:
            if len(method_calls) > 0:
                score += 30
                feedback_parts.append("References updated correctly (no direct access)")
            else:
                # Suspicious: No direct access but no method calls? Did they delete the code?
                score += 0
                feedback_parts.append("Warning: No interactions with Product found in Manager (code deleted?)")
        else:
            unique_violations = set(direct_accesses)
            feedback_parts.append(f"Failed: Direct field access detected for {unique_violations}")
    else:
        feedback_parts.append("Could not read InventoryManager class bytecode")

    # --- VLM Trajectory Verification (Bonus Check) ---
    # This helps confirm they used the UI tool and didn't just type it all manually (optional but good)
    # For this strict code task, code correctness is paramount, so we stick to bytecode scoring mostly.
    
    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }