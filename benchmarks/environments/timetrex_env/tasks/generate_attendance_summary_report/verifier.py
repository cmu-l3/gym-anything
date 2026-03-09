import json
import os
import tempfile


def verify_generate_attendance_summary_report(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "generate_attendance_summary_report"
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON invalid: {e}"}

    score = 0
    parts = []

    file_exists = result.get("file_exists", False)
    file_is_new = result.get("file_is_new", False)
    has_content = result.get("has_content", False)
    line_count = int(result.get("line_count", 0))
    file_size = int(result.get("file_size_bytes", 0))
    downloads_fallback = result.get("downloads_fallback", False)

    # Criterion 1 (30 pts): File exists at the correct Desktop path and was created after task start
    if file_exists and file_is_new:
        score += 30
        parts.append("File found on Desktop with correct timestamp (30/30)")
    elif file_exists and not file_is_new:
        parts.append("File exists but was NOT created after task start — may be stale (0/30)")
    elif downloads_fallback:
        # Partial credit: file in Downloads instead of Desktop
        score += 15
        parts.append("File found in Downloads (not Desktop) — partial credit (15/30)")
    else:
        parts.append("File not found at /home/ga/Desktop/attendance_feb2026.csv (0/30)")

    # Criterion 2 (40 pts): File has actual content (more than just a header row)
    if has_content and file_is_new:
        score += 40
        parts.append(f"File has content ({line_count} lines) (40/40)")
    elif file_exists and line_count == 1:
        score += 10
        parts.append("File has only 1 line (header only — no data rows) (10/40)")
    elif file_exists and line_count == 0:
        parts.append("File is empty (0/40)")
    elif not file_exists and not downloads_fallback:
        parts.append("No file to evaluate content (0/40)")

    # Criterion 3 (30 pts): File is CSV format and reasonably sized
    if file_exists and file_is_new and file_size > 100:
        score += 30
        parts.append(f"File is non-trivially sized ({file_size} bytes) (30/30)")
    elif file_exists and file_is_new and file_size > 0:
        score += 15
        parts.append(f"File is very small ({file_size} bytes) — may be incomplete (15/30)")
    elif downloads_fallback:
        score += 10
        parts.append("Downloads fallback file found — partial (10/30)")

    # Also try to copy and inspect the CSV directly for richer feedback
    try:
        csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
        csv_tmp.close()
        copy_from_env("/home/ga/Desktop/attendance_feb2026.csv", csv_tmp.name)
        with open(csv_tmp.name, "r", encoding="utf-8-sig", errors="replace") as f:
            first_lines = [f.readline() for _ in range(3)]
        os.unlink(csv_tmp.name)
        preview = " | ".join(ln.strip()[:60] for ln in first_lines if ln.strip())
        if preview:
            parts.append(f"CSV preview: {preview}")
    except Exception:
        pass

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts) if parts else "No criteria met",
    }
