#!/bin/bash
# Setup for defect_triage_and_escalation task
# Resets mobile-banking-app WPs to their original seeded state:
# - pagination bug: New, Normal priority, alice
# - JWT audit: In progress, Normal priority, carol
# Removes any prior emergency bug WP, wiki page, and escalation comments

source /workspace/scripts/task_utils.sh

echo "=== Setting up defect_triage_and_escalation ==="

wait_for_openproject

# ---------- Reset pagination bug WP ----------
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  alice = User.find_by(login: 'alice.johnson')
  new_status = Status.find_by(name: 'New')
  normal = IssuePriority.find_by(name: 'Normal') || IssuePriority.find_by(is_default: true)
  wp = WorkPackage.find_by(project: p, subject: 'Fix transaction history pagination bug')
  if wp
    wp.status = new_status if new_status
    wp.priority = normal if normal
    wp.assigned_to = alice
    wp.save!(validate: false)
    wp.journals.each do |j|
      if j.notes.to_s.downcase.include?('production') ||
         j.notes.to_s.downcase.include?('escalat') ||
         j.notes.to_s.downcase.include?('p0')
        j.update_column(:notes, '') rescue nil
      end
    end
    puts 'Reset pagination bug WP'
  end
" 2>/dev/null || true

# ---------- Reset JWT audit WP ----------
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  carol = User.find_by(login: 'carol.williams')
  in_progress = Status.find_by(name: 'In progress')
  normal = IssuePriority.find_by(name: 'Normal') || IssuePriority.find_by(is_default: true)
  wp = WorkPackage.find_by(project: p, subject: 'Security audit - JWT token expiration')
  if wp
    wp.status = in_progress if in_progress
    wp.priority = normal if normal
    wp.assigned_to = carol
    wp.save!(validate: false)
    wp.journals.each do |j|
      if j.notes.to_s.downcase.include?('security vulnerability') ||
         j.notes.to_s.downcase.include?('jwt tokens persist')
        j.update_column(:notes, '') rescue nil
      end
    end
    puts 'Reset JWT audit WP'
  end
" 2>/dev/null || true

# ---------- Remove emergency bug WP if exists ----------
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  wp = WorkPackage.find_by(project: p, subject: 'Emergency: Token invalidation on user logout')
  if wp
    wp.destroy
    puts 'Removed emergency bug WP'
  end
" 2>/dev/null || true

# ---------- Remove wiki page if exists ----------
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  if p && p.wiki
    page = p.wiki.pages.find_by(title: 'Incident Report - Transaction History')
    page.destroy if page
    puts 'Removed wiki page if existed'
  end
" 2>/dev/null || true

# ---------- Record baselines ----------
INITIAL_WP_COUNT=$(op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  puts p ? WorkPackage.where(project: p).count : 0
" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_WP_COUNT:-0}" > /tmp/defect_initial_wp_count

date +%s > /tmp/defect_start_ts

# ---------- Launch Firefox to mobile-banking-app work packages ----------
launch_firefox_to "http://localhost:8080/projects/mobile-banking-app/work_packages" 5

take_screenshot /tmp/defect_start.png

echo "=== Setup complete: defect_triage_and_escalation ==="
