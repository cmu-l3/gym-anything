#!/usr/bin/env python3
"""
Verifier for process_qa_feedback_blitz task.

Scoring (100 points total):
- 20 points per User Story (5 stories total).
- For each story:
  - 10 points for correct State.
  - 10 points for correct Tags (or lack thereof).

Items and Rules:
1. "Update customer profile photo" -> Active + "QA-Fail"
2. "Export order history to CSV" -> Closed
3. "Mobile push notifications for delivery" -> Active + "Blocked"
4. "Dark mode toggle on settings" -> Closed
5. "Guest checkout flow" -> Active + "QA-Fail"
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_qa_feedback_blitz(traj, env_info, task_info):
    """Verify that user stories were updated correctly based on QA comments."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Define expectations
    expectations = {
        "Update customer profile photo": {
            "state": "Active",
            "required_tag": "QA-Fail",
            "forbidden_tag": "Blocked"
        },
        "Export order history to CSV": {
            "state": "Closed",
            "required_tag": None,
            "forbidden_tag": None
        },
        "Mobile push notifications for delivery": {
            "state": "Active",
            "required_tag": "Blocked",
            "forbidden_tag": "QA-Fail"
        },
        "Dark mode toggle on settings": {
            "state": "Closed",
            "required_tag": None,
            "forbidden_tag": None
        },
        "Guest checkout flow": {
            "state": "Active",
            "required_tag": "QA-Fail",
            "forbidden_tag": "Blocked"
        }
    }

    # Retrieve result file from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    temp_file.close()
    
    try:
        # Windows path in container -> local temp file
        # Note: Container path uses Windows backslashes
        result_path_win = r"C:\Users\Docker\task_results\process_qa_feedback_result.json"
        
        # Try copying (handle potential path format issues)
        try:
            copy_from_env(result_path_win, temp_file.name)
        except Exception:
            # Fallback for unix-style path if mounted differently
            copy_from_env("C:/Users/Docker/task_results/process_qa_feedback_result.json", temp_file.name)

        with open(temp_file.name, "r") as f:
            result_data = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve task results. Did the export script run? Error: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check if query was successful
    if not result_data.get("query_success", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Internal Error: The export script failed to query Azure DevOps."
        }

    items_data = result_data.get("items", {})
    score = 0
    feedback_lines = []
    
    # Check modification times for anti-gaming (optional but good practice)
    # Ensure items were modified AFTER task start
    task_start_time = float(result_data.get("task_start_time", 0))
    
    for title, rules in expectations.items():
        item = items_data.get(title)
        
        if not item:
            feedback_lines.append(f"❌ '{title}': Item not found in results.")
            continue

        item_score = 0
        feedback_parts = []
        
        # Check State (10 pts)
        actual_state = item.get("state", "Unknown")
        if actual_state == rules["state"]:
            item_score += 10
            feedback_parts.append(f"State correct ({actual_state})")
        else:
            feedback_parts.append(f"State mismatch (Expected: {rules['state']}, Got: {actual_state})")

        # Check Tags (10 pts)
        actual_tags_str = item.get("tags", "")
        # Handle null/None tags
        if actual_tags_str is None:
            actual_tags_str = ""
            
        actual_tags = [t.strip().lower() for t in actual_tags_str.split(";") if t.strip()]
        
        tag_score = 0
        if rules["required_tag"]:
            req_tag = rules["required_tag"].lower()
            if req_tag in actual_tags:
                tag_score = 10
                feedback_parts.append(f"Tag '{rules['required_tag']}' found")
            else:
                feedback_parts.append(f"Missing required tag '{rules['required_tag']}'")
        else:
            # For Closed items, we generally expect no failure tags, but existing tags might persist.
            # The prompt implied 'No new tags required', effectively we don't penalize extra tags 
            # unless they contradict the status, but let's stick to simple logic:
            # If it's closed, we just give the points if the state is correct.
            # Actually, let's verify no "QA-Fail" or "Blocked" tags are present if Closed.
            if "qa-fail" in actual_tags or "blocked" in actual_tags:
                 feedback_parts.append("Has conflicting failure tags")
                 tag_score = 0
            else:
                 tag_score = 10
                 feedback_parts.append("Tags OK")

        # Basic anti-gaming check: changed date
        # Parsing format like: "2023-10-27T10:00:00.123Z"
        last_changed_str = item.get("last_changed")
        if last_changed_str:
            try:
                # Basic ISO parsing
                last_changed_dt = datetime.fromisoformat(last_changed_str.replace("Z", "+00:00"))
                last_changed_ts = last_changed_dt.timestamp()
                
                # Allow a small buffer, but primarily check it's not ancient
                if last_changed_ts < task_start_time:
                    feedback_parts.append("(WARNING: Item not modified during task)")
                    # We penalize strictly? 
                    # If state is correct but not modified, it means it was already correct?
                    # But we set them to 'New' in setup. So if they are 'Closed'/'Active', they MUST have changed.
                    pass 
            except ValueError:
                pass

        item_score += tag_score
        score += item_score
        
        status_icon = "✅" if item_score == 20 else "⚠️" if item_score > 0 else "❌"
        feedback_lines.append(f"{status_icon} '{title}': {', '.join(feedback_parts)} ({item_score}/20 pts)")

    final_feedback = "\n".join(feedback_lines)
    
    passed = score >= 80 # Allow one mistake or minor tag errors
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }