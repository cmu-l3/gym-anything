#!/bin/bash
# Setup for cross_project_dependency_audit task
# Ensures clean starting state: resets biometric WP to In progress,
# removes any prior dashboard WP, removes wiki page, resets priority.

source /workspace/scripts/task_utils.sh

echo "=== Setting up cross_project_dependency_audit ==="

wait_for_openproject

# ---------- Reset biometric login WP to In progress, remove comments about dependency ----------
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  in_progress = Status.find_by(name: 'In progress')
  wp = WorkPackage.find_by(project: p, subject: 'Implement biometric login (Face ID / Fingerprint)')
  if wp
    wp.status = in_progress if in_progress
    # Remove any [BLOCKED] prefix from subject
    wp.subject = wp.subject.gsub(/^\[BLOCKED\]\s*/, '')
    wp.save!(validate: false)
    # Remove journals/comments containing 'cross-project' or 'blocked by ecommerce'
    wp.journals.each do |j|
      if j.notes.to_s.downcase.include?('blocked by ecommerce') ||
         j.notes.to_s.downcase.include?('cross-project')
        j.update_column(:notes, '') rescue nil
      end
    end
    puts 'Reset biometric WP'
  end
" 2>/dev/null || true

# ---------- Remove any existing dashboard WP in devops-automation ----------
op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  wp = WorkPackage.find_by(project: p, subject: 'Cross-project dependency tracking dashboard')
  if wp
    wp.destroy
    puts 'Removed dashboard WP'
  end
" 2>/dev/null || true

# ---------- Reset checkout bug priority to Normal ----------
op_rails "
  p = Project.find_by(identifier: 'ecommerce-platform')
  wp = WorkPackage.find_by(project: p, subject: 'Fix broken checkout on mobile Safari')
  normal = IssuePriority.find_by(name: 'Normal') || IssuePriority.find_by(is_default: true)
  if wp && normal
    wp.priority = normal
    wp.save!(validate: false)
    puts 'Reset checkout priority to Normal'
  end
" 2>/dev/null || true

# ---------- Remove wiki page if exists ----------
op_rails "
  p = Project.find_by(identifier: 'mobile-banking-app')
  if p && p.wiki
    page = p.wiki.pages.find_by(title: 'Cross-Project Dependencies')
    page.destroy if page
    puts 'Removed wiki page if existed'
  end
" 2>/dev/null || true

# ---------- Record baselines ----------
INITIAL_WP_COUNT_DEVOPS=$(op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  puts p ? WorkPackage.where(project: p).count : 0
" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_WP_COUNT_DEVOPS:-0}" > /tmp/cross_project_initial_wp_count_devops

date +%s > /tmp/cross_project_start_ts

# ---------- Launch Firefox to mobile-banking-app project ----------
launch_firefox_to "http://localhost:8080/projects/mobile-banking-app/work_packages" 5

take_screenshot /tmp/cross_project_start.png

echo "=== Setup complete: cross_project_dependency_audit ==="
