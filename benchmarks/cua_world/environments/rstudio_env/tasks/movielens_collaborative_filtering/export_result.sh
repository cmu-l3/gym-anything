#!/bin/bash
echo "=== Exporting MovieLens Recommender Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_end_screenshot.png

# Extract values using Python to create a comprehensive, robust JSON export
python3 << 'PYEOF'
import os, json, csv

# Get the exact start time recorded by setup_task.sh
try:
    with open('/tmp/task_start_ts', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

def get_file_info(path):
    if os.path.exists(path):
        st = os.stat(path)
        return {
            "exists": True,
            "size": st.st_size,
            "mtime": st.st_mtime,
            "is_new": st.st_mtime > task_start
        }
    return {"exists": False, "size": 0, "mtime": 0, "is_new": False}

res = {
    "task_start": task_start,
    "files": {
        "summary": get_file_info("/home/ga/RProjects/output/matrix_summary.csv"),
        "plot": get_file_info("/home/ga/RProjects/output/rating_distribution.png"),
        "eval": get_file_info("/home/ga/RProjects/output/model_evaluation.csv"),
        "recs": get_file_info("/home/ga/RProjects/output/user_42_recommendations.csv")
    },
    "data": {
        "eval_rows": [],
        "recs_rows": []
    }
}

# Safely read evaluation CSV 
if res["files"]["eval"]["exists"]:
    try:
        with open("/home/ga/RProjects/output/model_evaluation.csv", "r", encoding="utf-8", errors="replace") as f:
            reader = csv.reader(f)
            headers = next(reader, [])
            # Protect against empty or duplicate headers
            headers = [str(h).strip() if h else f"col_{i}" for i, h in enumerate(headers)]
            for row in reader:
                res["data"]["eval_rows"].append(dict(zip(headers, row)))
    except Exception as e:
        res["data"]["eval_error"] = str(e)

# Safely read recommendations CSV
if res["files"]["recs"]["exists"]:
    try:
        with open("/home/ga/RProjects/output/user_42_recommendations.csv", "r", encoding="utf-8", errors="replace") as f:
            reader = csv.reader(f)
            headers = next(reader, [])
            headers = [str(h).strip() if h else f"col_{i}" for i, h in enumerate(headers)]
            for row in reader:
                res["data"]["recs_rows"].append(dict(zip(headers, row)))
    except Exception as e:
        res["data"]["recs_error"] = str(e)

# Write output safely
with open("/tmp/task_result.json", "w", encoding="utf-8") as f:
    json.dump(res, f)
PYEOF

# Ensure permissions are open for the verifier to read it
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="