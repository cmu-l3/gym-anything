#!/bin/bash
# Setup for sprint_release_planning task
# Seeds a distinct starting state: ensures no Sprint 4 version exists,
# resets relevant WPs to their original state, and records baselines.

source /workspace/scripts/task_utils.sh

echo "=== Setting up sprint_release_planning ==="

wait_for_openproject

# ---------- Clean up any prior Sprint 4 version ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  if p
    v = Version.find_by(project: p, name: 'Sprint 4 - Payment Overhaul')
    if v
      # Unassign any WPs from this version first
      WorkPackage.where(version_id: v.id).update_all(version_id: nil)
      v.destroy
      puts 'Removed existing Sprint 4 version'
    end
  end
" 2>/dev/null || true

# ---------- Reset WP1 (Fix broken checkout) to New status, no time entries ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  new_status = Status.find_by(name: 'New')
  wp1 = WorkPackage.find_by(project: p, subject: 'Fix broken checkout on mobile Safari')
  if wp1
    wp1.status = new_status if new_status
    wp1.version = nil
    # Assign to Sprint 1 as original
    v1 = Version.find_by(project: p, name: 'Sprint 1 - Launch MVP')
    wp1.version = v1 if v1
    wp1.save!(validate: false)
    # Remove any time entries
    TimeEntry.where(work_package_id: wp1.id).destroy_all
    puts 'Reset WP1: checkout bug'
  end
" 2>/dev/null || true

# ---------- Reset WP2 (Add wishlist) to original sprint ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  wp2 = WorkPackage.find_by(project: p, subject: 'Add wishlist feature')
  if wp2
    v2 = Version.find_by(project: p, name: 'Sprint 2 - Search & Filters')
    wp2.version = v2 if v2
    wp2.save!(validate: false)
    puts 'Reset WP2: wishlist'
  end
" 2>/dev/null || true

# ---------- Remove any existing wiki page 'Sprint 4 Release Notes' ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  if p && p.wiki
    page = p.wiki.pages.find_by(title: 'Sprint 4 Release Notes')
    page.destroy if page
    puts 'Removed wiki page if existed'
  end
" 2>/dev/null || true

# ---------- Record baselines ----------
INITIAL_VERSION_COUNT=$(op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  puts p ? Version.where(project: p).count : 0
" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_VERSION_COUNT:-0}" > /tmp/sprint_release_planning_initial_version_count

INITIAL_TIME_ENTRIES=$(op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  wp = WorkPackage.find_by(project: p, subject: 'Fix broken checkout on mobile Safari')
  puts wp ? TimeEntry.where(work_package_id: wp.id).count : 0
" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_TIME_ENTRIES:-0}" > /tmp/sprint_release_planning_initial_time_entries

date +%s > /tmp/sprint_release_planning_start_ts

# ---------- Launch Firefox to project overview ----------
launch_firefox_to "http://localhost:8080/projects/ecommerce-platform" 5

take_screenshot /tmp/sprint_release_planning_start.png

echo "=== Setup complete: sprint_release_planning ==="
