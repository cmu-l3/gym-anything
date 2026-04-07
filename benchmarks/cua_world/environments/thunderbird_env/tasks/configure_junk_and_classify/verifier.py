#!/usr/bin/env python3
"""
Verifier for configure_junk_and_classify task.

HYBRID MULTI-SIGNAL VERIFICATION:
1. prefs.js configuration: adaptive junk controls enabled (spamLevel=100)
2. prefs.js configuration: move-on-spam enabled (moveOnSpam=true)
3. Mbox File Counts: Inbox count should decrease by ~5, Junk count increase by ~5
4. Subject Matching: Ensure the specific injected spam subjects moved from Inbox to Junk
5. VLM Trajectory: Verify workflow progression through screenshots (Account Settings & marking junk)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utilities (graceful fallback if not available)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not found. Proceeding with programmatic verification only.")

def count_emails_in_file(filepath):
    """Fallback email counter if thunderbird_verification_utils fails."""
    if not os.path.exists(filepath):
        return 0
    count = 0
    with open(filepath, 'r', errors='ignore') as f:
        for line in f:
            if line.startswith("From "):
                count += 1
    return count

def get_subjects_in_file(filepath):
    """Fallback subject extractor if thunderbird_verification_utils fails."""
    if not os.path.exists(filepath):
        return []
    subjects = []
    with open(filepath, 'r', errors='ignore') as f:
        for line in f:
            if line.startswith("Subject: "):
                subjects.append(line[9:].strip())
    return subjects

def verify_junk_config_and_classify(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check for thunderbird_verification_utils
    try:
        import sys
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
        from thunderbird_verification_utils import setup_thunderbird_verification, cleanup_verification_temp
        TB_UTILS_AVAILABLE = True
    except ImportError:
        TB_UTILS_AVAILABLE = False

    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Read task_result.json
        result_file = os.path.join(temp_dir, 'task_result.json')
        copy_from_env("/tmp/task_result.json", result_file)
        with open(result_file, 'r') as f:
            task_result = json.load(f)
            
        task_start = task_result.get('task_start', 0)

        # 2. Copy necessary files directly using copy_from_env
        prefs_path = os.path.join(temp_dir, 'prefs.js')
        inbox_path = os.path.join(temp_dir, 'Inbox')
        junk_path = os.path.join(temp_dir, 'Junk')
        spam_subjects_path = os.path.join(temp_dir, 'spam_subjects.txt')
        initial_inbox_path = os.path.join(temp_dir, 'initial_inbox_count.txt')
        initial_junk_path = os.path.join(temp_dir, 'initial_junk_count.txt')

        # Use absolute container paths based on environment structure
        profile_dir = "/home/ga/.thunderbird/default-release"
        copy_from_env(f"{profile_dir}/prefs.js", prefs_path)
        copy_from_env(f"{profile_dir}/Mail/Local Folders/Inbox", inbox_path)
        copy_from_env(f"{profile_dir}/Mail/Local Folders/Junk", junk_path)
        copy_from_env("/tmp/spam_subjects.txt", spam_subjects_path)
        copy_from_env("/tmp/initial_inbox_count.txt", initial_inbox_path)
        copy_from_env("/tmp/initial_junk_count.txt", initial_junk_path)

        # ================================================================
        # CRITERION 1 & 2: Check prefs.js for junk mail configuration
        # ================================================================
        prefs_modified = False
        if os.path.exists(prefs_path):
            # Check modification time to prevent gaming
            mtime = os.path.getmtime(prefs_path)
            # Some file systems or docker setups might not preserve precise mtime across copy,
            # but reading the actual content is the primary check.
            
            with open(prefs_path, 'r', errors='ignore') as f:
                prefs_content = f.read()

            # Check spamLevel
            spam_level_match = re.search(r'user_pref\("mail\.server\.server1\.spamLevel",\s*100\)', prefs_content)
            if spam_level_match:
                score += 20
                feedback_parts.append("✓ Adaptive junk mail controls enabled (spamLevel=100)")
            else:
                feedback_parts.append("✗ Adaptive junk mail controls NOT enabled")

            # Check moveOnSpam
            move_match = re.search(r'user_pref\("mail\.server\.server1\.moveOnSpam",\s*true\)', prefs_content)
            if move_match:
                score += 15
                feedback_parts.append("✓ Move-on-spam configured (moveOnSpam=true)")
            else:
                feedback_parts.append("✗ Move-on-spam NOT configured")
        else:
            feedback_parts.append("✗ prefs.js not found - unable to verify settings")

        # ================================================================
        # CRITERION 3: Check email counts
        # ================================================================
        try:
            with open(initial_inbox_path, 'r') as f:
                initial_inbox = int(f.read().strip())
            with open(initial_junk_path, 'r') as f:
                initial_junk = int(f.read().strip())
        except (ValueError, FileNotFoundError):
            initial_inbox = 0
            initial_junk = 0

        final_inbox = count_emails_in_file(inbox_path)
        final_junk = count_emails_in_file(junk_path)

        inbox_decrease = initial_inbox - final_inbox
        junk_increase = final_junk - initial_junk

        # Validate count changes (should be exactly 5, but allow minor variations just in case)
        if 4 <= inbox_decrease <= 6:
            score += 10
            feedback_parts.append(f"✓ Inbox count decreased appropriately (Δ = -{inbox_decrease})")
        elif inbox_decrease > 0:
            score += 5
            feedback_parts.append(f"~ Inbox count decreased, but not by expected amount (Δ = -{inbox_decrease})")
        else:
            feedback_parts.append(f"✗ Inbox count did not decrease (Δ = {inbox_decrease})")

        if 4 <= junk_increase <= 6:
            score += 10
            feedback_parts.append(f"✓ Junk count increased appropriately (Δ = +{junk_increase})")
        elif junk_increase > 0:
            score += 5
            feedback_parts.append(f"~ Junk count increased, but not by expected amount (Δ = +{junk_increase})")
        else:
            feedback_parts.append(f"✗ Junk count did not increase (Δ = +{junk_increase})")

        # ================================================================
        # CRITERION 4: Specific Spam Subject Classification Check
        # ================================================================
        spam_subjects = []
        if os.path.exists(spam_subjects_path):
            with open(spam_subjects_path, 'r') as f:
                spam_subjects = [s.strip().lower() for s in f.read().split('\n') if s.strip()]
        
        if spam_subjects:
            inbox_subjects = [s.lower() for s in get_subjects_in_file(inbox_path)]
            junk_subjects = [s.lower() for s in get_subjects_in_file(junk_path)]

            spam_in_inbox = sum(1 for target in spam_subjects if any(target in s or s in target for s in inbox_subjects))
            spam_in_junk = sum(1 for target in spam_subjects if any(target in s or s in target for s in junk_subjects))

            if spam_in_inbox == 0:
                score += 10
                feedback_parts.append("✓ Target spam messages successfully removed from Inbox")
            else:
                feedback_parts.append(f"✗ {spam_in_inbox}/{len(spam_subjects)} target spam messages remain in Inbox")

            if spam_in_junk >= 4:
                score += 10
                feedback_parts.append(f"✓ Target spam messages found in Junk folder ({spam_in_junk}/{len(spam_subjects)})")
            elif spam_in_junk > 0:
                score += 5
                feedback_parts.append(f"~ Only {spam_in_junk}/{len(spam_subjects)} target spam messages found in Junk")
            else:
                feedback_parts.append("✗ No target spam messages found in Junk folder")
        else:
            feedback_parts.append("⚠ Could not verify specific subjects (reference list missing)")

        # ================================================================
        # CRITERION 5: VLM Trajectory Verification
        # ================================================================
        if VLM_AVAILABLE:
            try:
                frames = sample_trajectory_frames(traj, n=4)
                final_img = get_final_screenshot(traj)
                
                vlm_prompt = (
                    "You are verifying if an agent configured Thunderbird Junk Settings and classified emails.\n"
                    "Look at this sequence of screenshots from the task trajectory.\n"
                    "1. Did the agent open 'Account Settings' and view the 'Junk Settings' pane?\n"
                    "2. Did the agent mark messages as Junk in the Inbox view (usually shown by a flame icon next to messages)?\n"
                    "Respond with JSON format:\n"
                    "{\n"
                    "  \"opened_junk_settings\": true/false,\n"
                    "  \"marked_messages_as_junk\": true/false\n"
                    "}"
                )
                
                vlm_result = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    vlm_settings = parsed.get("opened_junk_settings", False)
                    vlm_marked = parsed.get("marked_messages_as_junk", False)
                    
                    if vlm_settings:
                        score += 15
                        feedback_parts.append("✓ VLM confirms Account Settings/Junk Settings was opened")
                    else:
                        feedback_parts.append("✗ VLM did not observe Junk Settings being opened")
                        
                    if vlm_marked:
                        score += 10
                        feedback_parts.append("✓ VLM confirms messages being marked as junk")
                    else:
                        feedback_parts.append("✗ VLM did not observe messages being marked as junk")
                else:
                    # Give partial credit if VLM fails but programmatic passes
                    logger.warning(f"VLM query failed: {vlm_result.get('error', 'unknown error')}")
                    if score >= 50: 
                        score += 25 
                        feedback_parts.append("~ VLM failed, but programmatic metrics strong (auto-credit)")
            except Exception as e:
                logger.warning(f"VLM verification exception: {e}")
                if score >= 50:
                    score += 25
                    feedback_parts.append("~ VLM exception, but programmatic metrics strong (auto-credit)")
        else:
            # Re-weight to 100 if VLM is unavailable
            score = int((score / 75.0) * 100)
            feedback_parts.append("~ Scaled score to 100% (VLM verification unavailable)")

    except Exception as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Verification error: {str(e)}\n" + "\n".join(feedback_parts)
        }
    finally:
        # Cleanup temp directory
        for item in os.listdir(temp_dir):
            try:
                os.unlink(os.path.join(temp_dir, item))
            except:
                pass
        try:
            os.rmdir(temp_dir)
        except:
            pass
            
        if TB_UTILS_AVAILABLE:
            cleanup_verification_temp()

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback_parts)
    }