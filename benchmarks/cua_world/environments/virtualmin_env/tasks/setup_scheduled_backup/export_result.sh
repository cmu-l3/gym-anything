#!/bin/bash
echo "=== Exporting setup_scheduled_backup result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

# Get scheduled backups info
BACKUP_LIST=$(virtualmin list-scheduled-backups --multiline 2>/dev/null)
BACKUP_COUNT=$(echo "$BACKUP_LIST" | grep -ci "destination\|dest" || echo "0")

# Check if backup directory exists
BACKUP_DIR_EXISTS="false"
if [ -d "/backup/virtualmin" ]; then
    BACKUP_DIR_EXISTS="true"
fi

# Parse backup details using Python for reliability
python3 << 'PYEOF'
import json
import subprocess
import re

# Get scheduled backups in multiline format
try:
    result = subprocess.run(
        ['virtualmin', 'list-scheduled-backups', '--multiline'],
        capture_output=True, text=True, timeout=30
    )
    backup_text = result.stdout
except Exception as e:
    backup_text = ""

# Also try JSON format
try:
    result_json = subprocess.run(
        ['virtualmin', 'list-scheduled-backups', '--json'],
        capture_output=True, text=True, timeout=30
    )
    backup_json_text = result_json.stdout
except Exception:
    backup_json_text = ""

# Parse the backup info
backup_found = False
has_acmecorp = False
has_brightstar = False
has_greenvalley = False
has_all_domains = False
dest_is_local = False
dest_path = ""
schedule_daily = False
has_dir_feature = False
has_mail_feature = False
has_mysql_feature = False
has_dns_feature = False
retention_count = 0

# Try JSON parsing first
if backup_json_text:
    try:
        backups = json.loads(backup_json_text)
        if isinstance(backups, dict):
            backups = backups.get('data', [backups])
        if isinstance(backups, list) and len(backups) > 0:
            b = backups[0]  # Check first backup
            backup_found = True

            # Check domains
            domains = str(b.get('domains', b.get('domain', '')))
            has_acmecorp = 'acmecorp' in domains.lower()
            has_brightstar = 'brightstar' in domains.lower()
            has_greenvalley = 'greenvalley' in domains.lower()

            # Check for "all domains" flag
            all_doms = str(b.get('all_domains', b.get('all', '')))
            if all_doms.lower() in ('1', 'true', 'yes'):
                has_all_domains = True
                has_acmecorp = has_brightstar = has_greenvalley = True

            # Check destination
            dest = str(b.get('dest', b.get('destination', '')))
            if '/backup/virtualmin' in dest:
                dest_is_local = True
                dest_path = dest

            # Check schedule
            sched = str(b.get('schedule', b.get('enabled', b.get('when', ''))))
            if 'daily' in sched.lower() or 'day' in sched.lower():
                schedule_daily = True
            # Also check individual schedule fields
            period = str(b.get('period', ''))
            if period.lower() in ('daily', 'day', '1'):
                schedule_daily = True

            # Check features
            features = str(b.get('features', b.get('feature', '')))
            has_dir_feature = 'dir' in features.lower() or 'home' in features.lower()
            has_mail_feature = 'mail' in features.lower()
            has_mysql_feature = 'mysql' in features.lower() or 'db' in features.lower()
            has_dns_feature = 'dns' in features.lower()

            # Retention
            try:
                retention_count = int(b.get('strftime', b.get('purge', b.get('retention', 0))))
            except (ValueError, TypeError):
                retention_count = 0
    except (json.JSONDecodeError, Exception):
        pass

# Fall back to multiline text parsing
if not backup_found and backup_text:
    lines = backup_text.strip().split('\n')
    if len(lines) > 1:
        backup_found = True
        text_lower = backup_text.lower()

        has_acmecorp = 'acmecorp' in text_lower
        has_brightstar = 'brightstar' in text_lower
        has_greenvalley = 'greenvalley' in text_lower

        if 'all domains' in text_lower or 'all virtual' in text_lower:
            has_all_domains = True
            has_acmecorp = has_brightstar = has_greenvalley = True

        if '/backup/virtualmin' in text_lower:
            dest_is_local = True
            for line in lines:
                if '/backup/virtualmin' in line.lower():
                    dest_path = line.strip()
                    break

        if 'daily' in text_lower or 'every day' in text_lower:
            schedule_daily = True

        has_dir_feature = 'dir' in text_lower or 'home' in text_lower
        has_mail_feature = 'mail' in text_lower
        has_mysql_feature = 'mysql' in text_lower or 'database' in text_lower
        has_dns_feature = 'dns' in text_lower

        # Look for retention/purge number
        for line in lines:
            if 'purge' in line.lower() or 'keep' in line.lower() or 'retention' in line.lower() or 'strftime' in line.lower():
                nums = re.findall(r'\d+', line)
                if nums:
                    retention_count = int(nums[-1])

import os
backup_dir_exists = os.path.isdir('/backup/virtualmin')

data = {
    "backup_found": backup_found,
    "has_acmecorp": has_acmecorp,
    "has_brightstar": has_brightstar,
    "has_greenvalley": has_greenvalley,
    "has_all_domains": has_all_domains,
    "dest_is_local": dest_is_local,
    "dest_path": dest_path,
    "schedule_daily": schedule_daily,
    "has_dir_feature": has_dir_feature,
    "has_mail_feature": has_mail_feature,
    "has_mysql_feature": has_mysql_feature,
    "has_dns_feature": has_dns_feature,
    "retention_count": retention_count,
    "backup_dir_exists": backup_dir_exists,
    "raw_backup_text": backup_text[:2000],
    "raw_backup_json": backup_json_text[:2000]
}

with open("/tmp/setup_scheduled_backup_result.json", "w") as f:
    json.dump(data, f, indent=2)

print(json.dumps(data, indent=2))
PYEOF

echo "=== Export Complete ==="
