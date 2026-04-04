#!/usr/bin/env python3
"""Verification script for add_foreground_service task."""

import logging
import re
import sys
import os
import tempfile
import json

sys.path.insert(0, '/workspace/utils')
from android_studio_verification_utils import vlm_verify_android_studio_task

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text_from_env(copy_from_env, container_path: str) -> str:
    """Copy a text file out of the container and return its contents."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except Exception as exc:
        logger.debug("Could not read %s: %s", container_path, exc)
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_add_foreground_service(traj, env_info, task_info):
    """Main verification function for add_foreground_service."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/SyncApp')
    default_service_path = metadata.get('service_path', 'app/src/main/java/com/example/syncapp/service/DataSyncService.kt')
    manifest_path_rel = metadata.get('manifest_path', 'app/src/main/AndroidManifest.xml')
    
    manifest_abs_path = f"{project_dir}/{manifest_path_rel}"
    service_abs_path = f"{project_dir}/{default_service_path}"

    score = 0
    feedback = []
    details = {}
    
    # Check export result for supplementary info
    result_data = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    # Determine correct service path (export script might have found it elsewhere)
    if result_data.get('service_exists', False) and result_data.get('service_path'):
        service_abs_path = result_data['service_path']

    # ===== 1. Check DataSyncService.kt exists (10 pts) =====
    service_content = _read_text_from_env(copy_from_env, service_abs_path)
    
    if service_content:
        score += 10
        feedback.append("[PASS] DataSyncService.kt file exists (+10)")
        details["service_file_exists"] = True
    else:
        feedback.append("[FAIL] DataSyncService.kt not found")
        details["service_file_exists"] = False

    # ===== 2. Check class extends Service (10 pts) =====
    if service_content:
        # Check inheritance: class DataSyncService ... : Service
        extends_service = bool(re.search(
            r'class\s+DataSyncService\s*.*:\s*(android\.app\.)?Service',
            service_content
        ))

        if extends_service:
            score += 10
            feedback.append("[PASS] DataSyncService extends Service (+10)")
            details["extends_service"] = True
        else:
            feedback.append("[FAIL] DataSyncService does not appear to extend Service")
            details["extends_service"] = False

    # ===== 3. Check NotificationChannel with correct ID (15 pts) =====
    if service_content:
        # Check for channel ID 'data_sync_channel'
        has_channel_id = 'data_sync_channel' in service_content
        has_notification_channel = 'NotificationChannel' in service_content

        if has_channel_id and has_notification_channel:
            score += 15
            feedback.append("[PASS] NotificationChannel with ID 'data_sync_channel' found (+15)")
            details["notification_channel"] = True
        elif has_notification_channel:
            score += 5
            feedback.append("[PARTIAL] NotificationChannel found but channel ID 'data_sync_channel' not found (+5)")
            details["notification_channel"] = "partial"
        else:
            feedback.append("[FAIL] NotificationChannel not found in service")
            details["notification_channel"] = False

    # ===== 4. Check startForeground called (15 pts) =====
    if service_content:
        has_start_foreground = 'startForeground' in service_content
        has_syncing_title = 'Syncing Data' in service_content

        if has_start_foreground and has_syncing_title:
            score += 15
            feedback.append("[PASS] startForeground() with 'Syncing Data' notification (+15)")
            details["start_foreground"] = True
        elif has_start_foreground:
            score += 10
            feedback.append("[PARTIAL] startForeground() found but notification title 'Syncing Data' not found (+10)")
            details["start_foreground"] = "partial"
        else:
            feedback.append("[FAIL] startForeground() not found in service")
            details["start_foreground"] = False

    # ===== 5. Check onBind returns null (5 pts) =====
    if service_content:
        # Match patterns like: override fun onBind(...): IBinder? = null
        # or: override fun onBind(...) { return null }
        has_on_bind_null = bool(re.search(
            r'override\s+fun\s+onBind\s*\([^)]*\)\s*[^{]*=\s*null',
            service_content
        )) or bool(re.search(
            r'override\s+fun\s+onBind\s*\([^)]*\)[^{]*\{[^}]*return\s+null',
            service_content
        ))

        if has_on_bind_null:
            score += 5
            feedback.append("[PASS] onBind() returns null (+5)")
            details["on_bind_null"] = True
        elif 'onBind' in service_content:
            # onBind exists but might not return null
            score += 2
            feedback.append("[PARTIAL] onBind() found but return null not confirmed (+2)")
            details["on_bind_null"] = "partial"
        else:
            feedback.append("[FAIL] onBind() not found in service")
            details["on_bind_null"] = False

    # ===== 6. Check AndroidManifest.xml for service declaration (15 pts) =====
    manifest_content = _read_text_from_env(copy_from_env, manifest_abs_path)

    if not manifest_content:
        feedback.append("[FAIL] Could not read AndroidManifest.xml")
        details["manifest_readable"] = False
    else:
        details["manifest_readable"] = True

        # Check service declaration
        has_service_decl = bool(re.search(
            r'<service\s[^>]*DataSyncService',
            manifest_content
        ))

        if has_service_decl:
            score += 15
            feedback.append("[PASS] Service declared in AndroidManifest.xml (+15)")
            details["service_declared"] = True
        else:
            feedback.append("[FAIL] DataSyncService not declared in AndroidManifest.xml")
            details["service_declared"] = False

        # ===== 7. Check FOREGROUND_SERVICE permission (10 pts) =====
        has_fg_permission = bool(re.search(
            r'<uses-permission\s[^>]*android\.permission\.FOREGROUND_SERVICE\s*"',
            manifest_content
        )) or ('FOREGROUND_SERVICE' in manifest_content and 'uses-permission' in manifest_content)

        if has_fg_permission:
            score += 10
            feedback.append("[PASS] FOREGROUND_SERVICE permission declared (+10)")
            details["foreground_service_perm"] = True
        else:
            feedback.append("[FAIL] FOREGROUND_SERVICE permission not found in manifest")
            details["foreground_service_perm"] = False

        # ===== 8. Check FOREGROUND_SERVICE_DATA_SYNC permission (10 pts) =====
        has_datasync_permission = 'FOREGROUND_SERVICE_DATA_SYNC' in manifest_content

        if has_datasync_permission:
            score += 10
            feedback.append("[PASS] FOREGROUND_SERVICE_DATA_SYNC permission declared (+10)")
            details["foreground_service_datasync_perm"] = True
        else:
            feedback.append("[FAIL] FOREGROUND_SERVICE_DATA_SYNC permission not found in manifest")
            details["foreground_service_datasync_perm"] = False

        # ===== 9. Check foregroundServiceType="dataSync" (10 pts) =====
        has_service_type = bool(re.search(
            r'foregroundServiceType\s*=\s*"dataSync"',
            manifest_content
        )) or bool(re.search(
            r'android:foregroundServiceType\s*=\s*"dataSync"',
            manifest_content
        ))

        if has_service_type:
            score += 10
            feedback.append("[PASS] foregroundServiceType=\"dataSync\" found (+10)")
            details["foreground_service_type"] = True
        else:
            feedback.append("[FAIL] foregroundServiceType=\"dataSync\" not found in manifest")
            details["foreground_service_type"] = False

    # ===== 10. Anti-gaming: Check timestamps =====
    # We verify if the manifest was actually changed from initial state
    manifest_changed = result_data.get('manifest_changed', True)
    if not manifest_changed:
        feedback.append("[ANTI-GAMING] Manifest was NOT modified — score zeroed")
        score = 0
    
    # ===== 11. VLM Verification (Bonus/Confirmation) =====
    vlm_result = vlm_verify_android_studio_task(
        traj, env_info,
        task_description="Add a foreground service DataSyncService with notification channel to the SyncApp Android project",
        checklist_items=[
            "Agent created or edited a DataSyncService.kt file in Android Studio",
            "Agent edited the AndroidManifest.xml file to add service declaration",
            "Agent added permission entries to the manifest",
            "The Android Studio editor shows Kotlin/XML code being modified",
        ]
    )

    if vlm_result:
        details["vlm_result"] = vlm_result
        if vlm_result.get("vlm_passed"):
            feedback.append(f"[VLM] Trajectory verification passed: {vlm_result.get('vlm_feedback', '')}")
        else:
            feedback.append(f"[VLM] Trajectory verification: {vlm_result.get('vlm_feedback', 'N/A')}")
    
    # Check compilation success from export result
    if result_data.get("build_success", False):
        feedback.append("[INFO] Project built successfully")
    else:
        feedback.append("[INFO] Project failed to build (check logs)")

    passed = score >= 70

    return {
        "score": score,
        "passed": passed,
        "feedback": "\n".join(feedback),
        "details": details,
    }