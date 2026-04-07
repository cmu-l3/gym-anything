#!/usr/bin/env python3
"""
Verifier for Archive Inbox Emails task.

Verification Strategy:
1. Copy Thunderbird mail files (Inbox, Archives, prefs.js) and task metadata via copy_from_env.
2. Programmatically parse the mbox files to count remaining Inbox emails and new Archives emails.
3. Read prefs.js to verify the archive_granularity setting was changed to 0 (Single folder).
4. Perform anti-gaming checks (timestamps, subject preservation).
5. Hybrid VLM Verification: Sample trajectory frames to ensure the user interacted with 
   Account Settings -> Copies & Folders, and actually performed the archive action.
"""

import json
import os
import re
import tempfile
import mailbox
import logging
from pathlib import Path

# Try to import VLM utilities safely
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def count_mbox_emails(mbox_path):
    """Count emails in an mbox file safely."""
    if not os.path.exists(mbox_path) or os.path.getsize(mbox_path) == 0:
        return 0
    try:
        mbox = mailbox.mbox(mbox_path)
        count = len(mbox)
        mbox.close()
        return count
    except Exception as e:
        logger.warning(f"Error parsing mbox {mbox_path}: {e}")
        return 0

def get_mbox_subjects(mbox_path):
    """Extract subjects from an mbox file safely."""
    subjects = []
    if not os.path.exists(mbox_path) or os.path.getsize(mbox_path) == 0:
        return subjects
    try:
        mbox = mailbox.mbox(mbox_path)
        for msg in mbox:
            subj = msg.get('Subject', '')
            if subj:
                subjects.append(str(subj).strip())
        mbox.close()
    except Exception as e:
        logger.warning(f"Error extracting subjects from {mbox_path}: {e}")
    return subjects

def verify_archive_inbox(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    max_score = 100

    # Paths inside container
    profile_dir = "/home/ga/.thunderbird/default-release"
    container_inbox = f"{profile_dir}/Mail/Local Folders/Inbox"
    container_archives = f"{profile_dir}/Mail/Local Folders/Archives"
    container_prefs = f"{profile_dir}/prefs.js"
    container_result = "/tmp/task_result.json"
    container_subjects = "/tmp/initial_inbox_subjects.txt"

    # Temporary directory on host
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_dir_path = Path(temp_dir)
        
        # 1. Fetch Task Metadata
        task_start = 0
        initial_count = 0
        try:
            res_path = temp_dir_path / "task_result.json"
            copy_from_env(container_result, str(res_path))
            with open(res_path, 'r') as f:
                res_data = json.load(f)
                task_start = res_data.get("task_start", 0)
                initial_count = res_data.get("initial_inbox_count", 0)
        except Exception:
            logger.warning("Failed to load task metadata")

        # 2. Fetch Initial Subjects
        initial_subjects = []
        try:
            subj_path = temp_dir_path / "initial_subjects.txt"
            copy_from_env(container_subjects, str(subj_path))
            with open(subj_path, 'r') as f:
                initial_subjects = [line.strip() for line in f.readlines() if line.strip()]
        except Exception:
            pass

        # 3. Fetch Inbox & Archives
        inbox_path = temp_dir_path / "Inbox"
        archives_path = temp_dir_path / "Archives"
        prefs_path = temp_dir_path / "prefs.js"
        
        try:
            copy_from_env(container_inbox, str(inbox_path))
        except Exception:
            pass
            
        try:
            copy_from_env(container_archives, str(archives_path))
        except Exception:
            pass
            
        try:
            copy_from_env(container_prefs, str(prefs_path))
        except Exception:
            pass

        # ==========================================
        # CRITERION 1: Archives folder exists (15 pts)
        # ==========================================
        archives_exist = archives_path.exists() and archives_path.stat().st_size > 0
        if archives_exist:
            # Check modification time against task start (Anti-gaming)
            archives_mtime = archives_path.stat().st_mtime
            if archives_mtime >= task_start:
                score += 15
                feedback_parts.append("✓ Archives folder created during task (15 pts)")
            else:
                feedback_parts.append("✗ Archives folder is stale (created before task start) (0/15 pts)")
                archives_exist = False # Invalidate for future checks
        else:
            feedback_parts.append("✗ Archives single-folder not found (Did agent use yearly subfolders?) (0/15 pts)")

        # ==========================================
        # CRITERION 2: Emails archived (25 pts)
        # ==========================================
        archive_count = count_mbox_emails(archives_path) if archives_exist else 0
        if archive_count >= 35:
            score += 25
            feedback_parts.append(f"✓ Archives contains {archive_count} emails (25 pts)")
        elif archive_count > 0:
            score += 10
            feedback_parts.append(f"~ Archives contains only {archive_count}/{initial_count} emails (10/25 pts)")
        else:
            feedback_parts.append("✗ Archives folder is empty (0/25 pts)")

        # ==========================================
        # CRITERION 3: Inbox Depleted (25 pts)
        # ==========================================
        inbox_count = count_mbox_emails(inbox_path)
        if inbox_count <= 2:
            score += 25
            feedback_parts.append(f"✓ Inbox successfully emptied ({inbox_count} remaining) (25 pts)")
        elif inbox_count < initial_count:
            score += 10
            feedback_parts.append(f"~ Inbox partially depleted ({inbox_count} remaining out of {initial_count}) (10/25 pts)")
        else:
            feedback_parts.append(f"✗ Inbox unchanged ({inbox_count} remaining) (0/25 pts)")

        # ==========================================
        # CRITERION 4: Preferences Configured (15 pts)
        # ==========================================
        granularity_configured = False
        if prefs_path.exists():
            content = prefs_path.read_text(errors='ignore')
            # Look for archive_granularity set to 0
            match = re.search(r'archive_granularity["\s,]+(\d+)', content)
            if match and int(match.group(1)) == 0:
                granularity_configured = True
                score += 15
                feedback_parts.append("✓ Archive granularity properly set to Single folder (0) (15 pts)")
            else:
                feedback_parts.append("✗ Archive granularity not set to Single folder (0/15 pts)")
        else:
            feedback_parts.append("✗ Could not read preferences file (0/15 pts)")

        # ==========================================
        # CRITERION 5: Content Preservation (10 pts)
        # ==========================================
        total_after = archive_count + inbox_count
        if initial_count > 0:
            if total_after >= (initial_count * 0.90):
                score += 10
                feedback_parts.append(f"✓ Emails preserved ({total_after}/{initial_count}) (10 pts)")
            else:
                feedback_parts.append(f"✗ Emails lost during transfer ({total_after}/{initial_count}) (0/10 pts)")
        
        # Anti-gaming: Verify specific subjects survived
        if archives_exist and initial_subjects:
            archived_subjects = get_mbox_subjects(archives_path)
            found_subjects = 0
            for subj in initial_subjects:
                if any(subj in a_subj for a_subj in archived_subjects):
                    found_subjects += 1
            if found_subjects == 0 and archive_count > 0:
                feedback_parts.append("⚠ WARNING: Original emails not found in Archive. Possible spoofing.")
                score = max(0, score - 30)

    # ==========================================
    # CRITERION 6: VLM Trajectory Verification (10 pts)
    # ==========================================
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames

            if images:
                prompt = """Analyze this sequence of screenshots from a user performing an archiving task in Thunderbird.
                Did the user perform these actions?
                1. Open Account Settings and view 'Copies & Folders'
                2. Change archive settings (e.g. interacting with 'Keep message archives in')
                3. Select multiple emails in the Inbox
                
                Respond ONLY in valid JSON:
                {"account_settings_viewed": true/false, "emails_selected": true/false}"""
                
                vlm_res = query_vlm(prompt=prompt, images=images)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("account_settings_viewed"):
                        vlm_score += 5
                        feedback_parts.append("✓ VLM: Account Settings workflow verified (5 pts)")
                    if parsed.get("emails_selected"):
                        vlm_score += 5
                        feedback_parts.append("✓ VLM: Bulk email selection verified (5 pts)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            
    score += vlm_score

    # Determine passing status
    # Must have configured granularity AND actually moved majority of emails
    passed = score >= 70 and archive_count >= 35 and granularity_configured

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }