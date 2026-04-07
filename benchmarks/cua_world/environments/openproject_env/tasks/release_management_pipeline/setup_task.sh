#!/bin/bash
# Setup for release_management_pipeline task
# Ensures a clean slate: removes any prior Release Coordination project,
# custom statuses, custom field, and associated workflow transitions.

echo "=== Setting up release_management_pipeline ==="

source /workspace/scripts/task_utils.sh

wait_for_openproject

# ── Idempotent cleanup (BEFORE recording timestamp) ──

# 1. Delete "Release Coordination" project (cascades WPs, wiki, boards, members)
op_rails "Project.find_by(identifier: 'release-coordination')&.destroy" 2>/dev/null || true

# 2. Delete custom statuses (reassign any WPs using them first, then remove workflows)
for status_name in "Ready for QA" "QA Passed" "Staging Deployed"; do
  op_rails "
    s = Status.find_by(name: '$status_name')
    if s
      new_s = Status.find_by(name: 'New')
      WorkPackage.where(status_id: s.id).update_all(status_id: new_s.id) if new_s
      Workflow.where(old_status_id: s.id).destroy_all
      Workflow.where(new_status_id: s.id).destroy_all
      s.destroy
    end
  " 2>/dev/null || true
done

# 3. Delete "Target Release" custom field (removes all associated custom values too)
op_rails "CustomField.where(name: 'Target Release', type: 'WorkPackageCustomField').destroy_all" 2>/dev/null || true

# ── Record timestamp ──
date +%s > /tmp/task_start_time.txt

# ── Record baselines for anti-gaming ──
INITIAL_STATUS_COUNT=$(op_rails "puts Status.count" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_STATUS_COUNT:-0}" > /tmp/rmp_initial_status_count

INITIAL_PROJECT_COUNT=$(op_rails "puts Project.count" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_PROJECT_COUNT:-0}" > /tmp/rmp_initial_project_count

# ── Launch Firefox to OpenProject home (agent must navigate to Admin) ──
launch_firefox_to "http://localhost:8080/" 5

take_screenshot /tmp/task_initial.png

echo "=== Setup complete: release_management_pipeline ==="
