#!/bin/bash
# Export results for cross_project_dependency_audit task
source /workspace/scripts/task_utils.sh

echo "=== Exporting cross_project_dependency_audit result ==="

take_screenshot /tmp/cross_project_end.png

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

# 1. Check biometric WP status and comments
biometric_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "mobile-banking-app"); '
    'wp = WorkPackage.find_by(project: p, subject: "Implement biometric login (Face ID / Fingerprint)"); '
    'if wp.nil?; '
    '  wp = WorkPackage.where(project: p).where("subject LIKE ?", "%biometric%").first; '
    'end; '
    'if wp; '
    '  notes = wp.journals.map { |j| j.notes.to_s }.reject(&:empty?); '
    '  puts JSON.generate({found: true, subject: wp.subject, '
    '    status: (wp.status ? wp.status.name : nil), '
    '    notes: notes, '
    '    has_blocked_prefix: wp.subject.include?("[BLOCKED]")}); '
    'else; puts JSON.generate({found: false}); end'
)

# 2. Check new WP in devops-automation
dashboard_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "devops-automation"); '
    'wp = WorkPackage.find_by(project: p, subject: "Cross-project dependency tracking dashboard"); '
    'if wp; '
    '  puts JSON.generate({found: true, subject: wp.subject, '
    '    type_name: (wp.type ? wp.type.name : nil), '
    '    assignee: (wp.assigned_to ? wp.assigned_to.login : nil), '
    '    version_name: (wp.version ? wp.version.name : nil), '
    '    description: wp.description.to_s[0..500]}); '
    'else; puts JSON.generate({found: false}); end'
)

# 3. Check checkout bug priority
priority_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "ecommerce-platform"); '
    'wp = WorkPackage.find_by(project: p, subject: "Fix broken checkout on mobile Safari"); '
    'if wp; '
    '  puts JSON.generate({found: true, '
    '    priority: (wp.priority ? wp.priority.name : nil)}); '
    'else; puts JSON.generate({found: false}); end'
)

# 4. Check wiki page
wiki_data = rails_query(
    'require "json"; '
    'p = Project.find_by(identifier: "mobile-banking-app"); '
    'if p && p.wiki; '
    '  page = p.wiki.pages.find_by(title: "Cross-Project Dependencies"); '
    '  if page; '
    '    content_text = page.content ? page.content.text.to_s : ""; '
    '    puts JSON.generate({exists: true, title: page.title, '
    '      content_length: content_text.length, '
    '      has_biometric: content_text.downcase.include?("biometric"), '
    '      has_checkout: (content_text.downcase.include?("checkout") || content_text.downcase.include?("safari")), '
    '      has_ecommerce: content_text.downcase.include?("ecommerce"), '
    '      has_blocking: (content_text.downcase.include?("block") || content_text.downcase.include?("depend"))}); '
    '  else; puts JSON.generate({exists: false}); end; '
    'else; puts JSON.generate({exists: false}); end'
)

# 5. Current WP count in devops
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
    "task_start": int(open("/tmp/cross_project_start_ts").read().strip()),
    "initial_wp_count_devops": int(open("/tmp/cross_project_initial_wp_count_devops").read().strip()),
    "biometric": safe_json(biometric_data),
    "dashboard": safe_json(dashboard_data),
    "priority": safe_json(priority_data),
    "wiki": safe_json(wiki_data),
    "current_wp_count_devops": safe_int(wp_count_raw),
}

with open("/tmp/cross_project_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete: cross_project_dependency_audit ==="
