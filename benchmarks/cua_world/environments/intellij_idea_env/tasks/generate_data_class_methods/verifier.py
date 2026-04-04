#!/usr/bin/env python3
"""Verifier for generate_data_class_methods task."""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_data_class_methods(traj, env_info, task_info):
    """
    Verify that the agent generated the required boilerplate methods for 3 Java classes.
    
    Scoring Breakdown (Total 100):
    - 20 pts: Project compiles successfully
    - 5 pts: Files modified after start
    - 5 pts: .class files exist
    - 60 pts: Code Structure Analysis (20 pts per class)
      - 4 pts: Constructor with correct params
      - 8 pts: Getters/Setters for all fields
      - 4 pts: equals() and hashCode()
      - 4 pts: toString()
    - 10 pts: VLM Trajectory Verification (Agent used UI)
    """
    
    # 1. Setup access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_path = metadata.get('project_path', '/home/ga/IdeaProjects/data-models')
    classes_meta = metadata.get('classes', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Temporary helper to copy file content
    def get_file_content(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.warning(f"Failed to read {remote_path}: {e}")
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    # 2. Read Compilation Result
    try:
        result_content = get_file_content("/tmp/task_result.json")
        if result_content:
            res_json = json.loads(result_content)
        else:
            res_json = {}
    except json.JSONDecodeError:
        res_json = {}
        feedback_parts.append("Failed to parse result JSON")

    # Score: Compilation (20 pts)
    if res_json.get("compile_success", False):
        score += 20
        feedback_parts.append("Project compiles (20/20)")
    else:
        feedback_parts.append("Project compilation FAILED (0/20)")
        # If it doesn't compile, we still check code but with a warning
        
    # Score: Files Modified (5 pts)
    if res_json.get("files_modified", False):
        score += 5
        feedback_parts.append("Files modified (5/5)")
    else:
        feedback_parts.append("Files NOT modified (0/5)")
        
    # Score: Class Files Exist (5 pts)
    if res_json.get("class_files_exist", False):
        score += 5
        feedback_parts.append("Class artifacts found (5/5)")

    # 3. Analyze Source Code (60 pts total)
    for class_info in classes_meta:
        cls_name = class_info['name']
        fields = class_info['fields']
        cls_path = f"{project_path}/{class_info['path']}"
        
        content = get_file_content(cls_path)
        if not content:
            feedback_parts.append(f"{cls_name}: File not found (-20)")
            continue
            
        cls_score = 0
        
        # Check Constructor (4 pts)
        # Regex looks for: public ClassName(Type param, Type param...)
        # Simplified check: public ClassName followed by params
        ctor_pattern = rf"public\s+{cls_name}\s*\("
        has_ctor = bool(re.search(ctor_pattern, content))
        if has_ctor:
            # Check if it has arguments (not default no-arg ctor)
            # We assume generated ctor has arguments corresponding to fields
            if len(fields) > 0:
                # Roughly check if fields appear in ctor
                # Very rough check: does the line/block contain types or field names?
                # A robust generated ctor usually looks like: public Person(String firstName, ...)
                if re.search(ctor_pattern + r".+[\w]+\s+[\w]+", content):
                    cls_score += 4
                else:
                    feedback_parts.append(f"{cls_name}: Constructor appears empty/no-arg")
            else:
                cls_score += 4 # No fields, no arg ctor is fine
        else:
            feedback_parts.append(f"{cls_name}: Constructor missing")
            
        # Check Getters/Setters (8 pts total)
        # 1 pt per accessor pair if we strictly count, but let's bundle
        accessors_found = 0
        expected_accessors = len(fields) * 2
        for f in fields:
            # Capitalize field name for method (firstName -> FirstName)
            cap_field = f[0].upper() + f[1:]
            
            # Check getter
            if re.search(rf"(public|protected)\s+[\w<>]+\s+(get|is){cap_field}\s*\(", content):
                accessors_found += 1
                
            # Check setter
            if re.search(rf"(public|protected)\s+void\s+set{cap_field}\s*\(", content):
                accessors_found += 1
                
        # Scale score: 8 points * (found / expected)
        if expected_accessors > 0:
            accessor_points = int(8 * (accessors_found / expected_accessors))
            cls_score += accessor_points
            if accessor_points < 8:
                feedback_parts.append(f"{cls_name}: Missing some getters/setters ({accessors_found}/{expected_accessors})")
        else:
            cls_score += 8
            
        # Check equals/hashCode (4 pts)
        has_equals = "public boolean equals(Object" in content
        has_hash = "public int hashCode()" in content
        if has_equals and has_hash:
            cls_score += 4
        elif has_equals or has_hash:
            cls_score += 2
            feedback_parts.append(f"{cls_name}: Missing equals or hashCode")
        else:
            feedback_parts.append(f"{cls_name}: Missing equals/hashCode")
            
        # Check toString (4 pts)
        if "public String toString()" in content:
            cls_score += 4
        else:
            feedback_parts.append(f"{cls_name}: Missing toString")
            
        score += cls_score

    # 4. VLM Verification (10 pts)
    # Import VLM helpers safely
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames
        
        # We check trajectory for the "Generate" popup or Alt+Insert menu
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, num_samples=5)
            if frames:
                prompt = """
                You are verifying if a user used the IntelliJ IDEA "Generate" menu.
                Look for these visual indicators in the screenshots:
                1. A small popup menu titled "Generate".
                2. Menu items like "Constructor", "Getter and Setter", "equals() and hashCode()", "toString()".
                3. Dialog windows asking to "Select Fields" to include in generation.
                
                Did the user use the code generation features?
                Respond YES or NO.
                """
                
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res and vlm_res.get('success'):
                    # Simple heuristic: if VLM says YES or positive, give points
                    resp_text = vlm_res.get('response', '').lower()
                    if "yes" in resp_text:
                        vlm_score = 10
                        feedback_parts.append("VLM: Code generation UI usage detected (+10)")
                    else:
                        feedback_parts.append("VLM: No code generation UI detected")
                else:
                    feedback_parts.append("VLM query failed")
            else:
                feedback_parts.append("No trajectory frames for VLM")
        else:
            # If VLM not available, give benefit of doubt if code is perfect
            if score >= 90: 
                vlm_score = 10
                feedback_parts.append("VLM unavailable, assuming success due to perfect code")
    except ImportError:
        feedback_parts.append("VLM module missing")
        # Fallback points if code is good
        if score >= 90: vlm_score = 10

    score += vlm_score
    
    # 5. Final Result
    passed = score >= 60 and res_json.get("compile_success", False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback_parts)
    }