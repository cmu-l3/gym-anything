#!/usr/bin/env python3
"""Verifier for improve_test_coverage task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_improve_test_coverage(traj, env_info, task_info):
    """
    Verify code coverage improvement task.
    
    Criteria:
    1. Tests Compile & Pass (20 pts)
    2. Source Integrity (Logic class not modified) (20 pts)
    3. Line Coverage >= 95% (40 pts)
    4. Branch Coverage >= 90% (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_line_cov = metadata.get('target_line_coverage', 0.95)
    target_branch_cov = metadata.get('target_branch_coverage', 0.90)

    score = 0
    feedback_parts = []
    
    # 1. Load Task Result JSON
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_json.close()
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # 2. Verify Tests Passed
    if result.get("tests_passed", False):
        score += 20
        feedback_parts.append("Tests compiled and passed")
    else:
        feedback_parts.append("Tests failed to compile or pass")
        return {"passed": False, "score": 0, "feedback": "Tests failed to compile/pass", "details": result}

    # 3. Verify Source Integrity (Anti-Gaming)
    if result.get("source_intact", False):
        score += 20
        feedback_parts.append("Source code intact")
    else:
        feedback_parts.append("CRITICAL: Source code was modified! (Anti-gaming check failed)")
        # If source is modified, fail the task immediately or cap score
        return {"passed": False, "score": 0, "feedback": "You modified the business logic class. This is not allowed."}

    # 4. Verify Coverage (Parse JaCoCo XML)
    if result.get("report_exists", False):
        try:
            tmp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
            tmp_xml.close()
            copy_from_env("/tmp/jacoco_report.xml", tmp_xml.name)
            
            tree = ET.parse(tmp_xml.name)
            root = tree.getroot()
            os.unlink(tmp_xml.name)

            # Find the LoanRiskCalculator class counter
            # We look for a 'class' element with name 'com/fintech/risk/LoanRiskCalculator'
            # Then check its children 'counter' elements
            
            line_missed = 0
            line_covered = 0
            branch_missed = 0
            branch_covered = 0

            # Iterate packages to find the class
            class_found = False
            for package in root.findall('package'):
                for cls in package.findall('class'):
                    if cls.get('name') == 'com/fintech/risk/LoanRiskCalculator':
                        class_found = True
                        for counter in cls.findall('counter'):
                            type_ = counter.get('type')
                            missed = int(counter.get('missed'))
                            covered = int(counter.get('covered'))
                            
                            if type_ == 'LINE':
                                line_missed = missed
                                line_covered = covered
                            elif type_ == 'BRANCH':
                                branch_missed = missed
                                branch_covered = covered
            
            if not class_found:
                feedback_parts.append("Coverage report generated but target class not found")
            else:
                # Calculate percentages
                total_lines = line_missed + line_covered
                line_pct = line_covered / total_lines if total_lines > 0 else 0
                
                total_branches = branch_missed + branch_covered
                branch_pct = branch_covered / total_branches if total_branches > 0 else 0
                
                # Score Line Coverage
                feedback_parts.append(f"Line Coverage: {line_pct:.1%}")
                if line_pct >= target_line_cov:
                    score += 40
                elif line_pct >= 0.70:
                    score += 20 # Partial credit
                
                # Score Branch Coverage
                feedback_parts.append(f"Branch Coverage: {branch_pct:.1%}")
                if branch_pct >= target_branch_cov:
                    score += 20
                elif branch_pct >= 0.70:
                    score += 10 # Partial credit

        except Exception as e:
            feedback_parts.append(f"Error parsing coverage report: {e}")
    else:
        feedback_parts.append("Coverage report not found (did Maven run successfully?)")

    # 5. Verify Test File Content (Quick Check)
    try:
        tmp_java = tempfile.NamedTemporaryFile(delete=False, suffix='.java')
        tmp_java.close()
        copy_from_env("/tmp/final_test_file.java", tmp_java.name)
        with open(tmp_java.name, 'r') as f:
            test_content = f.read()
        os.unlink(tmp_java.name)
        
        # Check for keywords indicating thorough testing
        keywords = ["REJECTED", "REFERRED", "APPROVED", "evaluate"]
        found_keywords = [k for k in keywords if k in test_content]
        if len(found_keywords) < 4:
            feedback_parts.append("Warning: Test file might miss some enum values")
            
    except Exception:
        pass

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }