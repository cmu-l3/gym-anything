#!/usr/bin/env python3
"""
Verifier for quarterly_data_review_message task.

Scoring (100 points total):
- Message sent in DHIS2 (30 pts) [MANDATORY]
- Subject contains required keywords ('Bo' AND ('Q4' OR '2023' OR 'Data Review')) (15 pts)
- Message body is substantive (>= 200 chars) (15 pts)
- Message has recipient(s) (15 pts)
- Local text file exists and created during task (15 pts)
- Local text file has content (>= 100 chars) (10 pts)

Pass threshold: 60 points
Mandatory: Message sent in DHIS2
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_quarterly_data_review_message(traj, env_info, task_info):
    """Verify DHIS2 message sent and local file saved."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/quarterly_data_review_message_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Check DHIS2 Messages
        dhis2_data = result.get('dhis2_messages', {})
        messages = dhis2_data.get('messages', [])
        
        # We need to find at least one valid message that meets criteria
        # If multiple messages sent, pick the best scoring one
        best_msg_score = 0
        best_msg_feedback = []
        message_sent = False
        
        for msg in messages:
            msg_score = 30 # Base score for existence
            msg_feedback = ["Message sent (+30)"]
            
            subject = msg.get('subject', '')
            body_len = msg.get('body_length', 0)
            has_recipients = msg.get('has_recipients', False)
            
            # Subject Check
            # Keywords: "Bo" AND ("Q4" OR "2023" OR "Data Review")
            subj_lower = subject.lower()
            has_bo = "bo" in subj_lower
            has_context = any(k in subj_lower for k in ["q4", "2023", "data review"])
            
            if has_bo and has_context:
                msg_score += 15
                msg_feedback.append("Subject keywords correct (+15)")
            else:
                msg_feedback.append(f"Subject '{subject}' missing keywords (need 'Bo' and context)")
                
            # Body Length Check
            if body_len >= 200:
                msg_score += 15
                msg_feedback.append("Body length sufficient (+15)")
            else:
                msg_feedback.append(f"Body too short ({body_len} chars)")
                
            # Recipient Check
            if has_recipients:
                msg_score += 15
                msg_feedback.append("Recipients included (+15)")
            else:
                msg_feedback.append("No recipients found")
            
            if msg_score > best_msg_score:
                best_msg_score = msg_score
                best_msg_feedback = msg_feedback
                message_sent = True

        if not message_sent:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No new messages found in DHIS2 sent during task."
            }
        
        score += best_msg_score
        feedback_parts.extend(best_msg_feedback)

        # 2. Check Local File
        file_data = result.get('local_file', {})
        file_exists = file_data.get('exists', False)
        created_during = file_data.get('created_during_task', False)
        file_size = file_data.get('size_bytes', 0)
        
        if file_exists and created_during:
            score += 15
            subscores["file_created"] = True
            feedback_parts.append("Local file created (+15)")
            
            if file_size >= 100:
                score += 10
                subscores["file_content"] = True
                feedback_parts.append("File content sufficient (+10)")
            else:
                subscores["file_content"] = False
                feedback_parts.append(f"File content too short ({file_size} bytes)")
        elif file_exists:
            subscores["file_created"] = False
            feedback_parts.append("File exists but timestamp indicates pre-existing (0)")
        else:
            subscores["file_created"] = False
            feedback_parts.append("Local file not found")

        # Final Evaluation
        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}