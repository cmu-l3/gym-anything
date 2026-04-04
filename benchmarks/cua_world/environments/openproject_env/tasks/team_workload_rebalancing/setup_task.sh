#!/bin/bash
# Setup for team_workload_rebalancing task
# Resets devops-automation WPs to their original seeded state:
# - SSL cert assigned to carol, status New
# - K8s autoscaling assigned to carol, status In progress
# - Blue-green assigned to alice, status New
# Removes any prior capacity planning WP, wiki page, time entries

source /workspace/scripts/task_utils.sh

echo "=== Setting up team_workload_rebalancing ==="

wait_for_openproject

# ---------- Reset SSL cert WP to carol, New status ----------
op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  carol = User.find_by(login: 'carol.williams')
  new_status = Status.find_by(name: 'New')
  wp = WorkPackage.find_by(project: p, subject: 'Automate SSL certificate renewal with Certbot')
  if wp
    wp.assigned_to = carol
    wp.status = new_status if new_status
    wp.save!(validate: false)
    puts 'Reset SSL cert WP to carol/New'
  end
" 2>/dev/null || true

# ---------- Ensure K8s autoscaling WP is carol / In progress ----------
op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  carol = User.find_by(login: 'carol.williams')
  in_progress = Status.find_by(name: 'In progress')
  wp = WorkPackage.find_by(project: p, subject: 'Kubernetes cluster autoscaling misconfigured')
  if wp
    wp.assigned_to = carol
    wp.status = in_progress if in_progress
    wp.save!(validate: false)
    TimeEntry.where(work_package_id: wp.id).destroy_all
    puts 'Reset K8s WP and cleared time entries'
  end
" 2>/dev/null || true

# ---------- Ensure blue-green WP is alice / New, clear comments ----------
op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  alice = User.find_by(login: 'alice.johnson')
  new_status = Status.find_by(name: 'New')
  wp = WorkPackage.find_by(project: p, subject: 'Implement blue-green deployment strategy')
  if wp
    wp.assigned_to = alice
    wp.status = new_status if new_status
    wp.save!(validate: false)
    wp.journals.each do |j|
      if j.notes.to_s.downcase.include?('workload review')
        j.update_column(:notes, '') rescue nil
      end
    end
    puts 'Reset blue-green WP'
  end
" 2>/dev/null || true

# ---------- Remove capacity planning WP if exists ----------
op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  wp = WorkPackage.find_by(project: p, subject: 'Sprint capacity planning review')
  if wp
    wp.destroy
    puts 'Removed capacity planning WP'
  end
" 2>/dev/null || true

# ---------- Remove wiki page if exists ----------
op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  if p && p.wiki
    page = p.wiki.pages.find_by(title: 'Sprint Workload Review')
    page.destroy if page
    puts 'Removed wiki page if existed'
  end
" 2>/dev/null || true

# ---------- Record baselines ----------
INITIAL_WP_COUNT=$(op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  puts p ? WorkPackage.where(project: p).count : 0
" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_WP_COUNT:-0}" > /tmp/workload_initial_wp_count

INITIAL_TIME_ENTRIES=$(op_rails "
  p = Project.find_by(identifier: 'devops-automation')
  wp = WorkPackage.find_by(project: p, subject: 'Kubernetes cluster autoscaling misconfigured')
  puts wp ? TimeEntry.where(work_package_id: wp.id).count : 0
" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "${INITIAL_TIME_ENTRIES:-0}" > /tmp/workload_initial_time_entries

date +%s > /tmp/workload_start_ts

# ---------- Launch Firefox to devops-automation work packages ----------
launch_firefox_to "http://localhost:8080/projects/devops-automation/work_packages" 5

take_screenshot /tmp/workload_start.png

echo "=== Setup complete: team_workload_rebalancing ==="
