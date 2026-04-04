#!/bin/bash
# Export results for defect_triage_and_escalation task
source /workspace/scripts/task_utils.sh

echo "=== Exporting defect_triage_and_escalation result ==="

take_screenshot /tmp/defect_end.png

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

# 1. Pagination bug - priority, status, comments
pagination_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "mobile-banking-app"); '
    'wp = WorkPackage.find_by(project: p, subject: "Fix transaction history pagination bug"); '
    'if wp; '
    '  notes = wp.journals.map { |j| j.notes.to_s }.reject(&:empty?); '
    '  puts JSON.generate({found: true, '
    '    priority: (wp.priority ? wp.priority.name : nil), '
    '    status: (wp.status ? wp.status.name : nil), '
    '    notes: notes}); '
    'else; puts JSON.generate({found: false}); end'
)

# 2. JWT audit - priority, comments
jwt_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "mobile-banking-app"); '
    'wp = WorkPackage.find_by(project: p, subject: "Security audit - JWT token expiration"); '
    'if wp; '
    '  notes = wp.journals.map { |j| j.notes.to_s }.reject(&:empty?); '
    '  puts JSON.generate({found: true, '
    '    priority: (wp.priority ? wp.priority.name : nil), '
    '    status: (wp.status ? wp.status.name : nil), '
    '    notes: notes}); '
    'else; puts JSON.generate({found: false}); end'
)

# 3. Emergency bug WP
emergency_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "mobile-banking-app"); '
    'wp = WorkPackage.find_by(project: p, subject: "Emergency: Token invalidation on user logout"); '
    'if wp; '
    '  assignee_obj = wp.respond_to?(:assigned_to) ? wp.assigned_to : nil; '
    '  puts JSON.generate({found: true, '
    '    type_name: (wp.type ? wp.type.name : nil), '
    '    priority: (wp.priority ? wp.priority.name : nil), '
    '    assignee: (assignee_obj ? assignee_obj.login : nil), '
    '    version_name: (wp.version ? wp.version.name : nil), '
    '    description: wp.description.to_s[0..500]}); '
    'else; puts JSON.generate({found: false}); end'
)

# 4. Wiki page
wiki_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "mobile-banking-app"); '
    'if p && p.wiki; '
    '  page = p.wiki.pages.find_by(title: "Incident Report - Transaction History"); '
    '  if page; '
    '    content_text = page.content ? page.content.text.to_s : ""; '
    '    puts JSON.generate({exists: true, '
    '      content_length: content_text.length, '
    '      has_pagination: content_text.downcase.include?("pagination") || content_text.downcase.include?("transaction"), '
    '      has_production: content_text.downcase.include?("production") || content_text.downcase.include?("incident"), '
    '      has_customer: content_text.downcase.include?("customer") || content_text.downcase.include?("user"), '
    '      has_escalation: content_text.downcase.include?("escalat") || content_text.downcase.include?("priority") || content_text.downcase.include?("p0"), '
    '      has_remediation: content_text.downcase.include?("remediat") || content_text.downcase.include?("fix") || content_text.downcase.include?("resolution")}); '
    '  else; puts JSON.generate({exists: false}); end; '
    'else; puts JSON.generate({exists: false}); end'
)

# 5. WP count
wp_count_raw = rails_query(
    'p = Project.find_by(identifier: "mobile-banking-app"); '
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
    "task_start": int(open("/tmp/defect_start_ts").read().strip()),
    "initial_wp_count": int(open("/tmp/defect_initial_wp_count").read().strip()),
    "pagination": safe_json(pagination_data),
    "jwt": safe_json(jwt_data),
    "emergency": safe_json(emergency_data),
    "wiki": safe_json(wiki_data),
    "current_wp_count": safe_int(wp_count_raw),
}

with open("/tmp/defect_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete: defect_triage_and_escalation ==="
