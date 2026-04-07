#!/bin/bash
# Do NOT use set -e
echo "=== Exporting quarterly_student_progress_report task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/quarterly_progress_end.png" 2>/dev/null || true

# Run comprehensive result collection and ground-truth computation
python3 << 'PYEOF'
import json
import os
import re
import csv
import zipfile
import math

result = {
    "task_start": 0,
    "script_exists": False,
    "script_size": 0,
    "script_content": "",
    "html_exists": False,
    "html_size": 0,
    "html_has_table": False,
    "html_text": "",
    "odt_exists": False,
    "odt_size": 0,
    "odt_has_table": False,
    "odt_text": "",
    "journal_found": False,
    "browse_used": False,
    "ground_truth": {},
    "error": None
}

# Read task start timestamp
try:
    with open("/tmp/quarterly_progress_start_ts", "r") as f:
        result["task_start"] = int(f.read().strip() or "0")
except:
    pass

# --- Check analysis script ---
script_path = "/home/ga/Documents/class_analysis.py"
if os.path.isfile(script_path):
    result["script_exists"] = True
    result["script_size"] = os.path.getsize(script_path)
    try:
        with open(script_path, "r") as f:
            result["script_content"] = f.read()[:5000]
    except:
        pass

# --- Check HTML dashboard ---
html_path = "/home/ga/Documents/class_dashboard.html"
if os.path.isfile(html_path):
    result["html_exists"] = True
    result["html_size"] = os.path.getsize(html_path)
    try:
        with open(html_path, "r") as f:
            html_raw = f.read()
        result["html_has_table"] = "<table" in html_raw.lower()
        result["html_text"] = re.sub(r'<[^>]+>', ' ', html_raw).lower()[:8000]
    except:
        pass

# --- Check ODT progress report ---
odt_path = "/home/ga/Documents/progress_report.odt"
if os.path.isfile(odt_path):
    result["odt_exists"] = True
    result["odt_size"] = os.path.getsize(odt_path)
    try:
        with zipfile.ZipFile(odt_path, "r") as z:
            with z.open("content.xml") as f:
                content = f.read().decode("utf-8", errors="replace")
        result["odt_has_table"] = "table:table" in content or "<table" in content.lower()
        plain = re.sub(r'<[^>]+>', ' ', content).lower()
        plain = plain.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
        result["odt_text"] = plain[:8000]
    except Exception as e:
        result["error"] = f"ODT parse error: {e}"

# --- Check Sugar Journal for "Q4 Progress Report" ---
journal_dir = "/home/ga/.sugar/default/datastore"
if os.path.isdir(journal_dir):
    for root, dirs, files in os.walk(journal_dir):
        if "title" in files:
            try:
                with open(os.path.join(root, "title"), "r") as f:
                    title = f.read().strip()
                if "q4 progress report" in title.lower():
                    result["journal_found"] = True
                    break
            except:
                pass

# --- Check if Browse was used ---
try:
    import subprocess
    log_dir = "/home/ga/.sugar/default/logs"
    if os.path.isdir(log_dir):
        ts = result["task_start"]
        for fname in os.listdir(log_dir):
            if "browse" in fname.lower() or "web" in fname.lower():
                fpath = os.path.join(log_dir, fname)
                if os.path.getmtime(fpath) > ts:
                    result["browse_used"] = True
                    break
    # Also check running processes
    proc = subprocess.run(["pgrep", "-f", "sugar-activity-web|Browse"],
                          capture_output=True, text=True)
    if proc.stdout.strip():
        result["browse_used"] = True
except:
    pass

# --- Compute ground truth from actual CSV ---
csv_path = "/home/ga/Documents/class_records.csv"
gt = {}
if os.path.isfile(csv_path):
    try:
        # Parse CSV
        student_data = {}  # sid -> {name, q_scores: {q: [scores]}, attendance: [vals], study: [vals]}
        subject_q_scores = {}  # (subject, quarter) -> [scores]

        with open(csv_path, "r") as f:
            reader = csv.DictReader(f, delimiter=";")
            for row in reader:
                sid = row["StudentID"].strip()
                name = row["Name"].strip()
                subj = row["Subject"].strip()
                q = row["Quarter"].strip()

                if sid not in student_data:
                    student_data[sid] = {"name": name, "q_scores": {}, "attendance": [], "study": []}

                # Score
                try:
                    score = float(row["Score"].strip())
                    student_data[sid]["q_scores"].setdefault(q, []).append(score)
                    subject_q_scores.setdefault((subj, q), []).append(score)
                except (ValueError, KeyError):
                    pass

                # Attendance
                att_str = row.get("Attendance", "").strip()
                if att_str and att_str.upper() != "NA":
                    try:
                        student_data[sid]["attendance"].append(float(att_str))
                    except ValueError:
                        pass

                # StudyHoursWeekly
                study_str = row.get("StudyHoursWeekly", "").strip()
                if study_str and study_str.upper() != "NA":
                    try:
                        student_data[sid]["study"].append(float(study_str))
                    except ValueError:
                        pass

        # Compute at-risk students
        at_risk = []
        for sid, data in sorted(student_data.items(), key=lambda x: int(x[0])):
            q1_scores = data["q_scores"].get("Q1", [])
            q4_scores = data["q_scores"].get("Q4", [])
            q1_avg = sum(q1_scores) / len(q1_scores) if q1_scores else 0
            q4_avg = sum(q4_scores) / len(q4_scores) if q4_scores else 0
            att_avg = sum(data["attendance"]) / len(data["attendance"]) if data["attendance"] else 100

            is_at_risk = (q1_avg - q4_avg > 10) or (att_avg < 75)
            if is_at_risk:
                at_risk.append({
                    "name": data["name"],
                    "q1_avg": round(q1_avg, 1),
                    "q4_avg": round(q4_avg, 1),
                    "attendance": round(att_avg, 1),
                    "drop": round(q1_avg - q4_avg, 1)
                })

        gt["at_risk"] = at_risk
        gt["at_risk_names"] = [s["name"] for s in at_risk]
        gt["at_risk_count"] = len(at_risk)

        # Compute subject-quarter averages
        subj_q_avgs = {}
        for (subj, q), scores in sorted(subject_q_scores.items()):
            avg = round(sum(scores) / len(scores), 1) if scores else 0
            subj_q_avgs[f"{subj}_{q}"] = avg
        gt["subject_quarter_avgs"] = subj_q_avgs

        # Find subject with lowest Q4 average
        q4_avgs = {}
        for (subj, q), scores in subject_q_scores.items():
            if q == "Q4":
                q4_avgs[subj] = round(sum(scores) / len(scores), 1)
        if q4_avgs:
            gt["lowest_q4_subject"] = min(q4_avgs, key=q4_avgs.get)
            gt["lowest_q4_avg"] = q4_avgs[gt["lowest_q4_subject"]]
            gt["q4_subject_avgs"] = q4_avgs

        # Compute Pearson correlation (StudyHoursWeekly vs average Score)
        student_avg_scores = []
        student_study_hours = []
        for sid, data in student_data.items():
            all_scores = []
            for q_scores in data["q_scores"].values():
                all_scores.extend(q_scores)
            if all_scores and data["study"]:
                student_avg_scores.append(sum(all_scores) / len(all_scores))
                student_study_hours.append(sum(data["study"]) / len(data["study"]))

        if len(student_avg_scores) >= 2:
            n = len(student_avg_scores)
            mean_x = sum(student_study_hours) / n
            mean_y = sum(student_avg_scores) / n
            num = sum((x - mean_x) * (y - mean_y) for x, y in zip(student_study_hours, student_avg_scores))
            den_x = math.sqrt(sum((x - mean_x) ** 2 for x in student_study_hours))
            den_y = math.sqrt(sum((y - mean_y) ** 2 for y in student_avg_scores))
            if den_x > 0 and den_y > 0:
                gt["correlation"] = round(num / (den_x * den_y), 4)
            else:
                gt["correlation"] = 0.0
        else:
            gt["correlation"] = 0.0

    except Exception as e:
        result["error"] = f"Ground truth computation error: {e}"

result["ground_truth"] = gt

# --- Check if at-risk names appear in HTML ---
if result["html_text"]:
    found_in_html = []
    for name in gt.get("at_risk_names", []):
        if name.lower() in result["html_text"]:
            found_in_html.append(name)
    result["at_risk_found_in_html"] = found_in_html
    result["at_risk_html_count"] = len(found_in_html)

# --- Check if at-risk names appear in ODT ---
if result["odt_text"]:
    found_in_odt = []
    for name in gt.get("at_risk_names", []):
        if name.lower() in result["odt_text"]:
            found_in_odt.append(name)
    result["at_risk_found_in_odt"] = found_in_odt
    result["at_risk_odt_count"] = len(found_in_odt)

# --- Check if correlation value appears in HTML ---
corr = gt.get("correlation")
if corr is not None and result["html_text"]:
    corr_str = f"{corr:.2f}"
    corr_str_short = f"{corr:.1f}"
    result["correlation_in_html"] = (corr_str in result["html_text"]) or (corr_str_short in result["html_text"]) or (str(round(corr, 2)) in result["html_text"])

# --- Check if correlation value appears in ODT ---
if corr is not None and result["odt_text"]:
    corr_str = f"{corr:.2f}"
    corr_str_short = f"{corr:.1f}"
    result["correlation_in_odt"] = (corr_str in result["odt_text"]) or (corr_str_short in result["odt_text"]) or (str(round(corr, 2)) in result["odt_text"])

with open("/tmp/quarterly_progress_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result exported successfully")
PYEOF

chmod 666 /tmp/quarterly_progress_result.json
echo "Result saved to /tmp/quarterly_progress_result.json"
cat /tmp/quarterly_progress_result.json
echo "=== Export complete ==="
