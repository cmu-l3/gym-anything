#!/usr/bin/env python3
"""
Verifier for legal_contract_review_comparison task.

Verifies:
1. Comparison document exists and contains tracked changes (proof of process).
2. Final document exists and contains specific clauses (proof of correct review).
3. Final document does NOT contain rejected clauses.
"""

import json
import os
import zipfile
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legal_contract_review(traj, env_info, task_info):
    """
    Verify the contract review task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_final_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    temp_comp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt').name

    try:
        # 1. Load basic result metadata
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

        score = 0
        feedback_parts = []
        
        # 2. Verify Comparison Document (Process Check)
        if result_data.get("comparison_exists") and result_data.get("comparison_created_during_task"):
            # Check for tracked changes in the ODT structure
            try:
                copy_from_env("/home/ga/Documents/contract_comparison.odt", temp_comp_odt)
                if zipfile.is_zipfile(temp_comp_odt):
                    with zipfile.ZipFile(temp_comp_odt, 'r') as z:
                        content_xml = z.read('content.xml').decode('utf-8')
                        # ODT tracked changes usually use <text:changed-region> or <text:change>
                        if "text:changed-region" in content_xml or "text:change-start" in content_xml:
                            score += 40
                            feedback_parts.append("Comparison document created with tracked changes (40/40)")
                        else:
                            score += 10
                            feedback_parts.append("Comparison document created but no tracked changes detected (10/40)")
                else:
                     feedback_parts.append("Comparison file is not a valid ODT")
            except Exception as e:
                feedback_parts.append(f"Failed to inspect comparison file: {e}")
        else:
            feedback_parts.append("Comparison document missing or not created during task (0/40)")

        # 3. Verify Final Resolved Document (Content Check)
        if result_data.get("final_exists") and result_data.get("final_created_during_task"):
            try:
                # Copy the converted text content
                copy_from_env("/tmp/final_content.txt", temp_final_txt)
                with open(temp_final_txt, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                content_score = 0
                content_feedback = []

                # Check 1: Payment Terms (Should be 45 days)
                if "45 days" in content:
                    content_score += 15
                    content_feedback.append("Payment terms correct (15/15)")
                elif "30 days" in content:
                    content_feedback.append("Payment terms incorrect (retained 30 days)")
                else:
                    content_feedback.append("Payment terms missing")

                # Check 2: Force Majeure (Should be present)
                if "Force Majeure" in content or "acts of God" in content:
                    content_score += 15
                    content_feedback.append("Force Majeure clause added (15/15)")
                else:
                    content_feedback.append("Force Majeure clause missing")

                # Check 3: Arbitration (Should be present - rejection of deletion)
                if "Arbitration" in content and "binding arbitration" in content:
                    content_score += 15
                    content_feedback.append("Arbitration clause retained (15/15)")
                else:
                    content_feedback.append("Arbitration clause missing (deletion was incorrectly accepted)")

                # Check 4: Liability Cap (Should be $1,000,000 - rejection of change)
                if "1,000,000" in content:
                    content_score += 15
                    content_feedback.append("Liability cap correct (15/15)")
                elif "500,000" in content:
                    content_feedback.append("Liability cap incorrect (accepted reduction to 500k)")
                else:
                    content_feedback.append("Liability cap missing")

                score += content_score
                feedback_parts.append(" | ".join(content_feedback))

            except Exception as e:
                feedback_parts.append(f"Failed to verify final content: {e}")
        else:
            feedback_parts.append("Final resolved document missing (0/60)")

        passed = score >= 85
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback_parts)
        }

    finally:
        # Cleanup
        for f in [temp_result_json, temp_final_txt, temp_comp_odt]:
            if os.path.exists(f):
                os.unlink(f)