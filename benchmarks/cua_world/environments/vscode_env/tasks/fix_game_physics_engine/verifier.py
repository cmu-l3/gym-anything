#!/usr/bin/env python3
"""
Verifier for the fix_game_physics_engine task.

Checks whether the agent identified and fixed 5 mathematical bugs in
the 2D physics engine. Uses a hybrid approach: static code analysis 
(to prevent gaming the tests) + checking test output + VLM trajectory check.

Max score: 100
Pass threshold: 60 (AND at least 3 bugs fixed programmatically)
"""

import sys
import os
import json
import re
import logging
import tempfile

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass  # Handle gracefully if running isolated

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_physics_engine(traj, env_info, task_info):
    """
    Verify physics engine bug fixes.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/physics_engine_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    bugs_fixed = 0

    # ==========================================================
    # 1. Check Vector Cross Product Sign (16 pts)
    # ==========================================================
    vec_src = result.get("engine/vector2d.py", "")
    if "ERROR" in vec_src:
        feedback_parts.append("[-] vector2d.py: File error")
    else:
        bug_pattern = re.search(r'return\s*-\s*\(', vec_src)
        fix_pattern = re.search(r'return\s+(self\.x\s*\*\s*other\.y\s*-\s*self\.y\s*\*\s*other\.x)', vec_src)
        
        if not bug_pattern and fix_pattern:
            score += 16
            bugs_fixed += 1
            feedback_parts.append("[+] vector2d.py: Cross product sign fixed")
        elif not bug_pattern and "cross" in vec_src:
            # Partial credit if they rewrote it differently but removed the obvious minus sign
            score += 8
            feedback_parts.append("[~] vector2d.py: Cross product altered but not exactly matched")
        else:
            feedback_parts.append("[-] vector2d.py: Cross product sign remains negated")

    # ==========================================================
    # 2. Check Semi-Implicit Euler Integration Order (16 pts)
    # ==========================================================
    int_src = result.get("engine/integrator.py", "")
    if "ERROR" in int_src:
        feedback_parts.append("[-] integrator.py: File error")
    else:
        # Find index of position update vs velocity update
        pos_update = re.search(r'body\.position\.x\s*\+=', int_src)
        vel_update = re.search(r'body\.velocity\.x\s*\+=', int_src)
        
        if pos_update and vel_update:
            if vel_update.start() < pos_update.start():
                score += 16
                bugs_fixed += 1
                feedback_parts.append("[+] integrator.py: Semi-Implicit Euler fixed (velocity before position)")
            else:
                feedback_parts.append("[-] integrator.py: Explicit Euler remains (position before velocity)")
        else:
            feedback_parts.append("[-] integrator.py: Could not detect standard integration lines")

    # ==========================================================
    # 3. Check AABB Boundary Operator (16 pts)
    # ==========================================================
    col_src = result.get("engine/collision.py", "")
    if "ERROR" in col_src:
        feedback_parts.append("[-] collision.py: File error")
    else:
        has_gte = ">=" in col_src
        has_lte = "<=" in col_src
        has_strict = re.search(r'[^=]>[^=]', col_src)
        
        if has_gte and has_lte:
            score += 16
            bugs_fixed += 1
            feedback_parts.append("[+] collision.py: AABB boundaries use inclusive inequalities")
        elif not has_strict and "aabb_intersect" in col_src:
            score += 8
            feedback_parts.append("[~] collision.py: Strict inequalities removed but standard inclusive operators not found")
        else:
            feedback_parts.append("[-] collision.py: Strict inequalities (>) still in use")

    # ==========================================================
    # 4. Check Resolver Inverse Mass (16 pts)
    # ==========================================================
    res_src = result.get("engine/resolver.py", "")
    if "ERROR" in res_src:
        feedback_parts.append("[-] resolver.py: File error")
    else:
        bug_pattern = "body_a.mass + body_b.mass" in res_src
        fix_inv_mass = "body_a.inv_mass + body_b.inv_mass" in res_src
        fix_fraction = "1.0 / body_a.mass + 1.0 / body_b.mass" in res_src
        fix_fraction2 = "1 / body_a.mass + 1 / body_b.mass" in res_src
        
        if (fix_inv_mass or fix_fraction or fix_fraction2) and not bug_pattern:
            score += 16
            bugs_fixed += 1
            feedback_parts.append("[+] resolver.py: Reduced mass uses correct inverse mass sum")
        else:
            feedback_parts.append("[-] resolver.py: Inverse mass calculation remains buggy")

    # ==========================================================
    # 5. Check Moment of Inertia (16 pts)
    # ==========================================================
    rb_src = result.get("engine/rigid_body.py", "")
    if "ERROR" in rb_src:
        feedback_parts.append("[-] rigid_body.py: File error")
    else:
        bug_pattern = "self.width + self.height" in rb_src
        has_square = "**" in rb_src or "width * self.width" in rb_src or "width*self.width" in rb_src
        
        if has_square and not bug_pattern:
            score += 16
            bugs_fixed += 1
            feedback_parts.append("[+] rigid_body.py: Moment of inertia uses squares")
        else:
            feedback_parts.append("[-] rigid_body.py: Moment of inertia still adds width and height")

    # ==========================================================
    # 6. VLM Trajectory Verification (20 pts)
    # ==========================================================
    vlm_points = 0
    if query_vlm and 'sample_trajectory_frames' in sys.modules:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
                
            prompt = """Look at these screenshots of a VS Code environment.
Did the user run the test suite (e.g., 'python3 run_tests.py' or 'python run_tests.py') in the terminal?
Are the tests passing? (Look for 'OK' or 'Ran 5 tests in...' with no failures at the bottom).

Return JSON: {"tests_run": true/false, "tests_passed": true/false}
"""
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("tests_run") and parsed.get("tests_passed"):
                    vlm_points = 20
                    feedback_parts.append("[+] VLM: Test suite visually confirmed passing")
                elif parsed.get("tests_run"):
                    vlm_points = 10
                    feedback_parts.append("[~] VLM: Tests run, but visually failed")
                else:
                    feedback_parts.append("[-] VLM: Could not verify tests were run in terminal")
            else:
                feedback_parts.append("[?] VLM: Query failed, relying on static code analysis")
                # Fallback to test output from JSON
                if result.get("tests_passed"):
                    vlm_points = 20
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            if result.get("tests_passed"):
                vlm_points = 20
    else:
        # Fallback if VLM unavailable
        if result.get("tests_passed"):
            vlm_points = 20
            feedback_parts.append("[+] Tests passed successfully in container")
            
    score += vlm_points

    # Calculate final status
    key_criteria_met = (bugs_fixed >= 3)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": {
            "bugs_fixed": bugs_fixed,
            "vlm_points": vlm_points,
            "tests_passed_internally": result.get("tests_passed", False)
        }
    }