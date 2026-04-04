#!/bin/bash
# Export results for project_retrospective_documentation task
source /workspace/scripts/task_utils.sh

echo "=== Exporting project_retrospective_documentation result ==="

take_screenshot /tmp/retro_end.png

python3 << 'PYEOF'
import json, subprocess, re, sys

def rails_query(code):
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
    except:
        return ""

# 1. DB optimization WP - status and comments
db_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'wp = WorkPackage.find_by(project: p, subject: "Optimize database queries for category listing"); '
    'if wp; '
    '  notes = wp.journals.map { |j| j.notes.to_s }.reject(&:empty?); '
    '  puts JSON.generate({found: true, '
    '    status: (wp.status ? wp.status.name : nil), '
    '    notes: notes}); '
    'else; puts JSON.generate({found: false}); end'
)

# 2. Search WP - comments, time entries, version
search_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'wp = WorkPackage.find_by(project: p, subject: "Implement product search with Elasticsearch"); '
    'if wp; '
    '  notes = wp.journals.map { |j| j.notes.to_s }.reject(&:empty?); '
    '  entries = TimeEntry.where(work_package_id: wp.id); '
    '  puts JSON.generate({found: true, '
    '    status: (wp.status ? wp.status.name : nil), '
    '    version_name: (wp.version ? wp.version.name : nil), '
    '    notes: notes, '
    '    time_entry_count: entries.count, '
    '    total_hours: entries.sum(:hours).to_f, '
    '    time_comments: entries.map { |e| e.comments.to_s }}); '
    'else; puts JSON.generate({found: false}); end'
)

# 3. New version
version_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'v = p ? Version.find_by(project: p, name: "Sprint 2 - Performance & Search") : nil; '
    'if v; '
    '  puts JSON.generate({exists: true, status: v.status, '
    '    start_date: v.start_date.to_s, due_date: v.effective_date.to_s}); '
    'else; puts JSON.generate({exists: false}); end'
)

# 4. Wiki page
wiki_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'if p && p.wiki; '
    '  page = p.wiki.pages.find_by(title: "Sprint 1 Retrospective"); '
    '  if page; '
    '    content_text = page.content ? page.content.text.to_s : ""; '
    '    puts JSON.generate({exists: true, '
    '      content_length: content_text.length, '
    '      has_went_well: content_text.downcase.include?("went well") || content_text.downcase.include?("success") || content_text.downcase.include?("achieved"), '
    '      has_didnt_go_well: content_text.downcase.include?("didn") || content_text.downcase.include?("challenge") || content_text.downcase.include?("improve"), '
    '      has_database: content_text.downcase.include?("database") || content_text.downcase.include?("query") || content_text.downcase.include?("optimization"), '
    '      has_search: content_text.downcase.include?("search") || content_text.downcase.include?("elasticsearch"), '
    '      has_estimation: content_text.downcase.include?("estimat") || content_text.downcase.include?("velocity") || content_text.downcase.include?("underestim"), '
    '      has_action_items: content_text.downcase.include?("action") || content_text.downcase.include?("next step") || content_text.downcase.include?("carry")}); '
    '  else; puts JSON.generate({exists: false}); end; '
    'else; puts JSON.generate({exists: false}); end'
)

# 5. Version count
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
    "task_start": int(open("/tmp/retro_start_ts").read().strip()),
    "initial_version_count": int(open("/tmp/retro_initial_version_count").read().strip()),
    "initial_time_entries": int(open("/tmp/retro_initial_time_entries").read().strip()),
    "db_optimize": safe_json(db_data),
    "search": safe_json(search_data),
    "version": safe_json(version_data),
    "wiki": safe_json(wiki_data),
    "current_version_count": safe_int(version_count_raw),
}

with open("/tmp/retro_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete: project_retrospective_documentation ==="
