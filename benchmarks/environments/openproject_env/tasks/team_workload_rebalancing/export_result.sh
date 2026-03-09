#!/bin/bash
# Export results for team_workload_rebalancing task
source /workspace/scripts/task_utils.sh

echo "=== Exporting team_workload_rebalancing result ==="

take_screenshot /tmp/workload_end.png

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

# 1. SSL cert WP - assignee and status
ssl_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "devops-automation"); '
    'wp = WorkPackage.find_by(project: p, subject: "Automate SSL certificate renewal with Certbot"); '
    'if wp; '
    '  assignee_obj = wp.respond_to?(:assigned_to) ? wp.assigned_to : nil; '
    '  puts JSON.generate({found: true, '
    '    assignee: (assignee_obj ? assignee_obj.login : nil), '
    '    status: (wp.status ? wp.status.name : nil)}); '
    'else; puts JSON.generate({found: false}); end'
)

# 2. K8s WP - time entries
k8s_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "devops-automation"); '
    'wp = WorkPackage.find_by(project: p, subject: "Kubernetes cluster autoscaling misconfigured"); '
    'if wp; '
    '  entries = TimeEntry.where(work_package_id: wp.id); '
    '  puts JSON.generate({found: true, '
    '    time_entry_count: entries.count, '
    '    total_hours: entries.sum(:hours).to_f, '
    '    comments: entries.map { |e| e.comments.to_s }}); '
    'else; puts JSON.generate({found: false}); end'
)

# 3. New capacity planning WP
capacity_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "devops-automation"); '
    'wp = WorkPackage.find_by(project: p, subject: "Sprint capacity planning review"); '
    'if wp; '
    '  assignee_obj = wp.respond_to?(:assigned_to) ? wp.assigned_to : nil; '
    '  puts JSON.generate({found: true, '
    '    type_name: (wp.type ? wp.type.name : nil), '
    '    assignee: (assignee_obj ? assignee_obj.login : nil), '
    '    version_name: (wp.version ? wp.version.name : nil), '
    '    description: wp.description.to_s[0..500]}); '
    'else; puts JSON.generate({found: false}); end'
)

# 4. Blue-green WP - comments
bluegreen_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "devops-automation"); '
    'wp = WorkPackage.find_by(project: p, subject: "Implement blue-green deployment strategy"); '
    'if wp; '
    '  notes = wp.journals.map { |j| j.notes.to_s }.reject(&:empty?); '
    '  puts JSON.generate({found: true, notes: notes}); '
    'else; puts JSON.generate({found: false}); end'
)

# 5. Wiki page
wiki_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "devops-automation"); '
    'if p && p.wiki; '
    '  page = p.wiki.pages.find_by(title: "Sprint Workload Review"); '
    '  if page; '
    '    content_text = page.content ? page.content.text.to_s : ""; '
    '    puts JSON.generate({exists: true, '
    '      content_length: content_text.length, '
    '      has_ssl: content_text.downcase.include?("ssl") || content_text.downcase.include?("certbot") || content_text.downcase.include?("certificate"), '
    '      has_carol: content_text.downcase.include?("carol"), '
    '      has_bob: content_text.downcase.include?("bob"), '
    '      has_reassign: content_text.downcase.include?("reassign") || content_text.downcase.include?("transfer") || content_text.downcase.include?("moved"), '
    '      has_overload: content_text.downcase.include?("overload") || content_text.downcase.include?("capacity") || content_text.downcase.include?("workload")}); '
    '  else; puts JSON.generate({exists: false}); end; '
    'else; puts JSON.generate({exists: false}); end'
)

# 6. WP count
wp_count_raw = rails_query(
    'p = Project.find_by(identifier: "devops-automation"); '
    'puts p ? WorkPackage.where(project: p).count : 0'
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
    "task_start": int(open("/tmp/workload_start_ts").read().strip()),
    "initial_wp_count": int(open("/tmp/workload_initial_wp_count").read().strip()),
    "initial_time_entries": int(open("/tmp/workload_initial_time_entries").read().strip()),
    "ssl": safe_json(ssl_data),
    "k8s": safe_json(k8s_data),
    "capacity": safe_json(capacity_data),
    "bluegreen": safe_json(bluegreen_data),
    "wiki": safe_json(wiki_data),
    "current_wp_count": safe_int(wp_count_raw),
}

with open("/tmp/workload_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete: team_workload_rebalancing ==="
