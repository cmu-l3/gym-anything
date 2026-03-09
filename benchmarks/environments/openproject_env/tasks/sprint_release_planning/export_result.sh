#!/bin/bash
# Export results for sprint_release_planning task
source /workspace/scripts/task_utils.sh

echo "=== Exporting sprint_release_planning result ==="

take_screenshot /tmp/sprint_release_planning_end.png

TASK_START=$(cat /tmp/sprint_release_planning_start_ts 2>/dev/null || echo "0")
INITIAL_VERSION_COUNT=$(cat /tmp/sprint_release_planning_initial_version_count 2>/dev/null || echo "0")
INITIAL_TIME_ENTRIES=$(cat /tmp/sprint_release_planning_initial_time_entries 2>/dev/null || echo "0")

# Query all subtask states via Rails
python3 << 'PYEOF'
import json, subprocess, re, sys

def rails_query(code):
    """Run Ruby code in OpenProject container and return stdout."""
    cmd = [
        "docker", "exec", "openproject", "bash", "-lc",
        f"cd /app && bin/rails runner -e production '{code}'"
    ]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            cmd2 = [
                "docker", "exec", "openproject", "bash", "-lc",
                f"cd /app && bundle exec rails runner -e production '{code}'"
            ]
            r = subprocess.run(cmd2, capture_output=True, text=True, timeout=120)
        return (r.stdout or "").strip()
    except Exception as e:
        return ""

# 1. Check version exists
version_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'v = p ? Version.find_by(project: p, name: "Sprint 4 - Payment Overhaul") : nil; '
    'if v; '
    '  puts JSON.generate({exists: true, status: v.status, '
    '    start_date: v.start_date.to_s, due_date: v.effective_date.to_s}); '
    'else; puts JSON.generate({exists: false}); end'
)

# 2. Check WP1 version assignment and status
wp1_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'wp = WorkPackage.find_by(project: p, subject: "Fix broken checkout on mobile Safari"); '
    'if wp; '
    '  puts JSON.generate({found: true, '
    '    version_name: (wp.version ? wp.version.name : nil), '
    '    status: (wp.status ? wp.status.name : nil)}); '
    'else; puts JSON.generate({found: false}); end'
)

# 3. Check WP2 version assignment
wp2_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'wp = WorkPackage.find_by(project: p, subject: "Add wishlist feature"); '
    'if wp; '
    '  puts JSON.generate({found: true, '
    '    version_name: (wp.version ? wp.version.name : nil)}); '
    'else; puts JSON.generate({found: false}); end'
)

# 4. Check time entries on WP1
time_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'wp = WorkPackage.find_by(project: p, subject: "Fix broken checkout on mobile Safari"); '
    'if wp; '
    '  entries = TimeEntry.where(work_package_id: wp.id); '
    '  puts JSON.generate({count: entries.count, '
    '    total_hours: entries.sum(:hours).to_f, '
    '    comments: entries.map { |e| e.comments.to_s }}); '
    'else; puts JSON.generate({count: 0, total_hours: 0.0, comments: []}); end'
)

# 5. Check wiki page
wiki_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'if p && p.wiki; '
    '  page = p.wiki.pages.find_by(title: "Sprint 4 Release Notes"); '
    '  if page; '
    '    content_text = page.content ? page.content.text.to_s : ""; '
    '    puts JSON.generate({exists: true, title: page.title, '
    '      content_length: content_text.length, '
    '      has_sprint_name: content_text.include?("Payment Overhaul"), '
    '      has_checkout_ref: (content_text.downcase.include?("checkout") || content_text.downcase.include?("safari")), '
    '      has_wishlist_ref: content_text.downcase.include?("wishlist")}); '
    '  else; puts JSON.generate({exists: false}); end; '
    'else; puts JSON.generate({exists: false}); end'
)

# 6. Count current versions
version_count_raw = rails_query(
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'puts p ? Version.where(project: p).count : 0'
)

def safe_json(s):
    """Extract JSON from Rails output that may contain INFO log lines."""
    for line in reversed((s or "").strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except:
                continue
    return {}

def safe_int(s, default=0):
    """Extract last pure-integer line from Rails output."""
    for line in reversed((s or "").strip().splitlines()):
        line = line.strip()
        if re.match(r'^\d+$', line):
            return int(line)
    return default

result = {
    "task_start": int(open("/tmp/sprint_release_planning_start_ts").read().strip()),
    "initial_version_count": int(open("/tmp/sprint_release_planning_initial_version_count").read().strip()),
    "initial_time_entries": int(open("/tmp/sprint_release_planning_initial_time_entries").read().strip()),
    "version": safe_json(version_data),
    "wp1": safe_json(wp1_data),
    "wp2": safe_json(wp2_data),
    "time_entries": safe_json(time_data),
    "wiki": safe_json(wiki_data),
    "current_version_count": safe_int(version_count_raw),
}

with open("/tmp/sprint_release_planning_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete: sprint_release_planning ==="
