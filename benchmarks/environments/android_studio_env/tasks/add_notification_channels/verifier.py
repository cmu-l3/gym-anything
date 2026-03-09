#!/usr/bin/env python3
"""
Verifier for add_notification_channels task.

Scoring Criteria (Total 100):
- NotificationHelper.kt exists & correct package (8 pts)
- Channel IDs defined correctly (14 pts)
- createNotificationChannels method implemented (10 pts)
- Importance levels set correctly (10 pts)
- Notification builder method implemented (8 pts)
- NotepadApplication.kt extends Application (10 pts)
- NotepadApplication calls channel creation (8 pts)
- Manifest declares Application class (10 pts)
- Manifest declares POST_NOTIFICATIONS permission (7 pts)
- Project builds successfully (15 pts)
"""

import json
import logging
import re
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_notification_channels(traj, env_info, task_info):
    """Verify that notification infrastructure was added correctly."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Load result from export_result.sh
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    score = 0
    feedback = []
    
    helper_content = result.get("helper_content", "")
    app_class_content = result.get("app_class_content", "")
    manifest_content = result.get("manifest_content", "")
    build_success = result.get("build_success", False)

    # --- 1. NotificationHelper Analysis (40 pts) ---
    if helper_content:
        score += 8
        feedback.append("PASS: NotificationHelper.kt exists")
        
        # Check Channel IDs
        if "note_reminders" in helper_content:
            score += 7
            feedback.append("PASS: 'note_reminders' channel ID found")
        else:
            feedback.append("FAIL: 'note_reminders' channel ID missing")
            
        if "app_updates" in helper_content:
            score += 7
            feedback.append("PASS: 'app_updates' channel ID found")
        else:
            feedback.append("FAIL: 'app_updates' channel ID missing")

        # Check Creation Method
        if "createNotificationChannels" in helper_content and "NotificationChannel" in helper_content:
            score += 10
            feedback.append("PASS: createNotificationChannels method found")
        else:
            feedback.append("FAIL: createNotificationChannels method missing or incomplete")

        # Check Importance
        if "IMPORTANCE_HIGH" in helper_content:
            score += 5
            feedback.append("PASS: IMPORTANCE_HIGH usage found")
        else:
            feedback.append("FAIL: IMPORTANCE_HIGH missing")
            
        if "IMPORTANCE_DEFAULT" in helper_content:
            score += 5
            feedback.append("PASS: IMPORTANCE_DEFAULT usage found")
        else:
            feedback.append("FAIL: IMPORTANCE_DEFAULT missing")

        # Check Builder Method
        if "NotificationCompat.Builder" in helper_content or "Notification.Builder" in helper_content:
            if "buildReminderNotification" in helper_content:
                score += 8
                feedback.append("PASS: buildReminderNotification method found")
            else:
                score += 4
                feedback.append("PARTIAL: Notification builder usage found, but method name differs")
        else:
            feedback.append("FAIL: Notification builder missing")
            
    else:
        feedback.append("FAIL: NotificationHelper.kt not found")

    # --- 2. NotepadApplication Analysis (18 pts) ---
    if app_class_content:
        # Check inheritance
        if re.search(r':\s*Application\(\)|:\s*android\.app\.Application', app_class_content) or "extends Application" in app_class_content:
            score += 10
            feedback.append("PASS: NotepadApplication extends Application")
        else:
            feedback.append("FAIL: NotepadApplication does not extend Application")

        # Check wiring
        if "createNotificationChannels" in app_class_content:
            score += 8
            feedback.append("PASS: createNotificationChannels called in Application")
        else:
            feedback.append("FAIL: Channel creation not called in Application")
    else:
        feedback.append("FAIL: NotepadApplication.kt not found")

    # --- 3. Manifest Analysis (17 pts) ---
    if manifest_content:
        # Check Application declaration
        if 'android:name=".NotepadApplication"' in manifest_content or 'android:name="com.example.notepadapp.NotepadApplication"' in manifest_content:
            score += 10
            feedback.append("PASS: Application class registered in Manifest")
        else:
            feedback.append("FAIL: Application class not registered in Manifest")

        # Check Permission
        if "android.permission.POST_NOTIFICATIONS" in manifest_content:
            score += 7
            feedback.append("PASS: POST_NOTIFICATIONS permission found")
        else:
            feedback.append("FAIL: POST_NOTIFICATIONS permission missing")
    else:
        feedback.append("FAIL: AndroidManifest.xml not read")

    # --- 4. Build Status (15 pts) ---
    if build_success:
        score += 15
        feedback.append("PASS: Project builds successfully")
    else:
        feedback.append("FAIL: Project build failed or was not attempted")

    # --- 5. VLM / Anti-Gaming Check (10 pts implicit) ---
    # We use trajectory verification to confirm valid workflow if programmatic score is borderline
    # But for now, we'll verify "Do Nothing" via file counts
    
    # Get initial count
    tmp_init = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    initial_kt_count = 0
    try:
        copy_from_env("/tmp/initial_kt_count.txt", tmp_init.name)
        with open(tmp_init.name, 'r') as f:
            initial_kt_count = int(f.read().strip())
    except Exception:
        pass
    finally:
        if os.path.exists(tmp_init.name):
            os.unlink(tmp_init.name)

    final_kt_count = result.get("final_kt_count", 0)
    
    if final_kt_count <= initial_kt_count:
        feedback.append("WARNING: No new Kotlin files detected.")
        if score > 0:
            score = 0 # Fail if no files created
            feedback.append("FAIL: Anti-gaming triggered (no new files).")

    # VLM Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=3)
        if env_info.get("query_vlm"):
            vlm_res = env_info["query_vlm"](
                prompt="Does this trajectory show a user editing Kotlin code and Android Manifest files in Android Studio? Answer YES or NO.",
                images=frames
            )
            if vlm_res and vlm_res.get("parsed", {}).get("answer", "").upper() == "YES":
                feedback.append("VLM: Workflow verified visually.")
    except Exception:
        pass

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "\n".join(feedback)
    }