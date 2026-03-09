#!/usr/bin/env python3
"""
Verifier for Profile Slow Script task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_profile_slow_script(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Added timing instrumentation to data_processor.py
    2. Executed the script successfully
    3. Identified the validation stage as the bottleneck
    4. Documented findings in performance_analysis.md
    
    Scoring:
    - Timing import (15 pts)
    - Timing measurements added (25 pts)
    - Script executed successfully (20 pts)
    - Documentation created (15 pts)
    - Bottleneck correctly identified (15 pts)
    - Evidence provided in doc (10 pts)
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='profile_verify_')

    try:
        # Copy exported files
        script_local = os.path.join(temp_dir, "data_processor.py")
        doc_local = os.path.join(temp_dir, "performance_analysis.md")
        output_local = os.path.join(temp_dir, "processed_data.csv")

        try:
            copy_from_env("/tmp/data_processor.py", script_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy script: {str(e)}"}

        try:
            copy_from_env("/tmp/performance_analysis.md", doc_local)
        except:
            pass  # Documentation might not exist

        try:
            copy_from_env("/tmp/processed_data.csv", output_local)
        except:
            pass  # Output might not exist if script wasn't run

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Read script content
        if not os.path.exists(script_local):
            return {"passed": False, "score": 0, "feedback": "Script file not found"}
        
        script_content = read_file_content(script_local)
        if not script_content:
            return {"passed": False, "score": 0, "feedback": "Script file is empty"}

        # Criterion 1: Timing import present (15 pts)
        has_time_import = (
            "import time" in script_content or 
            "from time import" in script_content
        )
        if has_time_import:
            criteria_passed += 1
            feedback_parts.append("✅ Timing module imported")
        else:
            feedback_parts.append("❌ No time module import found")

        # Criterion 2: Timing measurements added (25 pts)
        # Look for time.perf_counter() or time.time() calls
        timing_patterns = [
            r'time\.perf_counter\(\)',
            r'time\.time\(\)',
            r'perf_counter\(\)',
        ]
        timing_calls = 0
        for pattern in timing_patterns:
            timing_calls += len(re.findall(pattern, script_content))
        
        # Need at least 4 timing calls (start/end for at least 2 stages)
        has_timing = timing_calls >= 4
        if has_timing:
            criteria_passed += 1
            feedback_parts.append(f"✅ Timing measurements added ({timing_calls} timing calls)")
        else:
            feedback_parts.append(f"❌ Insufficient timing measurements (found {timing_calls}, need ≥4)")

        # Criterion 3: Script executed successfully (20 pts)
        script_ran = os.path.exists(output_local) and os.path.getsize(output_local) > 0
        if script_ran:
            criteria_passed += 1
            feedback_parts.append("✅ Script executed successfully (output file created)")
        else:
            feedback_parts.append("❌ Script not executed or failed (no output file)")

        # Criterion 4: Documentation created (15 pts)
        doc_exists = os.path.exists(doc_local) and os.path.getsize(doc_local) > 0
        if doc_exists:
            criteria_passed += 1
            feedback_parts.append("✅ Documentation file created (performance_analysis.md)")
        else:
            feedback_parts.append("❌ Documentation file not created")

        # Criterion 5: Bottleneck correctly identified (15 pts)
        bottleneck_identified = False
        if doc_exists:
            doc_content = read_file_content(doc_local).lower()
            
            # Check for bottleneck identification keywords
            bottleneck_keywords = [
                "validat",  # validation, validate, validator
                "bottleneck",
                "slow",
                "slowest",
            ]
            
            # Must mention validation-related terms
            validation_mentioned = any(
                keyword in doc_content 
                for keyword in ["validat"]
            )
            
            # Check if it's identified as slow/bottleneck
            problem_mentioned = any(
                keyword in doc_content 
                for keyword in ["slow", "bottleneck", "problem", "issue"]
            )
            
            if validation_mentioned and problem_mentioned:
                bottleneck_identified = True
                criteria_passed += 1
                feedback_parts.append("✅ Bottleneck correctly identified (validation stage)")
            else:
                if validation_mentioned:
                    feedback_parts.append("⚠️ Validation mentioned but not identified as bottleneck")
                else:
                    feedback_parts.append("❌ Bottleneck not correctly identified (should be validation)")
        else:
            feedback_parts.append("❌ Cannot check bottleneck (no documentation)")

        # Criterion 6: Evidence provided (10 pts)
        evidence_provided = False
        if doc_exists:
            doc_content = read_file_content(doc_local)
            
            # Look for timing evidence: numbers with time units
            timing_evidence_patterns = [
                r'\d+\.?\d*\s*(second|sec|s\b|ms|millisecond)',
                r'\d+\.?\d*s\b',
                r'took\s+\d+\.?\d*',
                r'\d+\.?\d*\s*seconds?',
            ]
            
            for pattern in timing_evidence_patterns:
                if re.search(pattern, doc_content, re.IGNORECASE):
                    evidence_provided = True
                    break
            
            if evidence_provided:
                criteria_passed += 1
                feedback_parts.append("✅ Timing evidence provided in documentation")
            else:
                feedback_parts.append("❌ No timing evidence (numbers) in documentation")
        else:
            feedback_parts.append("❌ Cannot check evidence (no documentation)")

        # Calculate score
        # Weighted scoring:
        # - Import: 15%
        # - Timing added: 25%
        # - Executed: 20%
        # - Doc created: 15%
        # - Bottleneck found: 15%
        # - Evidence: 10%
        score = 0
        if has_time_import:
            score += 15
        if has_timing:
            score += 25
        if script_ran:
            score += 20
        if doc_exists:
            score += 15
        if bottleneck_identified:
            score += 15
        if evidence_provided:
            score += 10

        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
