#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Setting up refactor_document_categories task ==="

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Redmine to be ready
wait_for_http "$REDMINE_BASE_URL/login" 120

# 3. Seed data via Rails runner
# We need to ensure specific categories exist and a document is assigned to the one we will delete.
echo "Seeding Redmine data..."

SEED_SCRIPT="/tmp/seed_docs.rb"
cat > "$SEED_SCRIPT" << 'RUBY'
# Helper to safely create categories
def ensure_category(name)
  cat = DocumentCategory.find_by(name: name)
  unless cat
    cat = DocumentCategory.create!(name: name, active: true)
    puts "Created category: #{name}"
  end
  cat
end

# 1. Ensure default/starting categories exist
user_cat = ensure_category('User documentation')
tech_cat = ensure_category('Technical documentation')

# 2. Setup Project
project = Project.find_by(identifier: 'iso-prep')
if project.nil?
  project = Project.new(
    name: 'ISO 13485 Prep',
    identifier: 'iso-prep',
    description: 'Project for ISO audit preparation',
    is_public: false
  )
  # Enable documents module
  project.enabled_module_names = ['documents', 'issue_tracking']
  project.save!
  project.set_parent!(nil)
  puts "Created project: ISO 13485 Prep"
end

# 3. Create/Update Document
# It must be in "Technical documentation" initially
doc = Document.find_by(title: 'Legacy System Spec', project: project)
if doc.nil?
  doc = Document.new(
    title: 'Legacy System Spec',
    description: 'Original system specification v1.0',
    category: tech_cat,
    project: project
  )
  doc.save!
  puts "Created document: Legacy System Spec"
else
  # Reset category if it exists (in case of retry)
  doc.category = tech_cat
  doc.save!
  puts "Reset document category to Technical documentation"
end

# 4. Add admin as member so they can see it easily (optional but good for visibility)
admin = User.find_by(login: 'admin')
role = Role.find_by(name: 'Manager')
if admin && role && !project.users.include?(admin)
  Member.create!(user: admin, project: project, roles: [role])
end
RUBY

# Copy and run seed script
docker cp "$SEED_SCRIPT" redmine:/tmp/seed_docs.rb
docker exec -e RAILS_ENV=production redmine bundle exec rails runner /tmp/seed_docs.rb

# 4. Log in and navigate to Enumerations page
TARGET_URL="$REDMINE_BASE_URL/enumerations"
log "Logging in and navigating to: $TARGET_URL"

ensure_redmine_logged_in "$TARGET_URL"

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="