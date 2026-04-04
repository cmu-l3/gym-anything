#!/bin/bash
# Setup for project_retrospective_documentation task
# Ensures clean starting state:
# - db optimization WP: Closed status (seeded as Closed/resolved), clear retro comments
# - search WP: In progress (seeded), clear carry-over comments, clear time entries
# - Remove Sprint 2 Performance version if exists
# - Remove retro wiki page if exists

source /workspace/scripts/task_utils.sh

echo "=== Setting up project_retrospective_documentation ==="

wait_for_openproject

# ---------- Reset DB optimization WP to Closed, remove retro comments ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  closed_status = Status.find_by(name: 'Closed') || Status.find_by(name: 'Resolved')
  wp = WorkPackage.find_by(project: p, subject: 'Optimize database queries for category listing')
  if wp
    wp.status = closed_status if closed_status
    wp.save!(validate: false)
    wp.journals.each do |j|
      if j.notes.to_s.downcase.include?('verified in production') ||
         j.notes.to_s.downcase.include?('n+1 queries')
        j.update_column(:notes, '') rescue nil
      end
    end
    puts 'Reset DB optimization WP'
  end
" 2>/dev/null || true

# ---------- Reset search WP to In progress, original sprint, clear comments/time ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  in_progress = Status.find_by(name: 'In progress')
  alice = User.find_by(login: 'alice.johnson')
  v1 = Version.find_by(project: p, name: 'Sprint 1 - Launch MVP')
  wp = WorkPackage.find_by(project: p, subject: 'Implement product search with Elasticsearch')
  if wp
    wp.status = in_progress if in_progress
    wp.assigned_to = alice
    wp.version = v1 if v1
    wp.save!(validate: false)
    TimeEntry.where(work_package_id: wp.id).destroy_all
    wp.journals.each do |j|
      if j.notes.to_s.downcase.include?('carrying over') ||
         j.notes.to_s.downcase.include?('sprint 2') ||
         j.notes.to_s.downcase.include?('retrospective')
        j.update_column(:notes, '') rescue nil
      end
    end
    puts 'Reset search WP'
  end
" 2>/dev/null || true

# ---------- Remove Sprint 2 - Performance version if exists ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  if p
    v = Version.find_by(project: p, name: 'Sprint 2 - Performance & Search')
    if v
      WorkPackage.where(version_id: v.id).update_all(version_id: nil)
      v.destroy
      puts 'Removed Sprint 2 Performance version'
    end
  end
" 2>/dev/null || true

# ---------- Remove wiki page if exists ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  if p && p.wiki
    page = p.wiki.pages.find_by(title: 'Sprint 1 Retrospective')
    page.destroy if page
    puts 'Removed retro wiki page if existed'
  end
" 2>/dev/null || true

# ---------- Record baselines ----------
INITIAL_VERSION_COUNT=$(op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  puts p ? Version.where(project: p).count : 0
" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_VERSION_COUNT:-0}" > /tmp/retro_initial_version_count

INITIAL_TIME_ENTRIES=$(op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  wp = WorkPackage.find_by(project: p, subject: 'Implement product search with Elasticsearch')
  puts wp ? TimeEntry.where(work_package_id: wp.id).count : 0
" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_TIME_ENTRIES:-0}" > /tmp/retro_initial_time_entries

date +%s > /tmp/retro_start_ts

# ---------- Launch Firefox to ecommerce-platform work packages ----------
launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/work_packages" 5

take_screenshot /tmp/retro_start.png

echo "=== Setup complete: project_retrospective_documentation ==="
