#!/bin/bash
echo "=== Setting up configure_project_permissions task ==="

# Clean up any artifacts from previous runs
rm -f /tmp/permissions_task_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure SciNote and Docker are healthy
ensure_docker_healthy
wait_for_scinote_ready 90

echo "=== Preparing database state for permissions task ==="

# We use Rails runner to safely create users with properly hashed passwords and team associations
cat > /tmp/setup_permissions.rb << 'EOF'
begin
  admin = User.find_by(email: 'admin@scinote.net')
  team = Team.first || Team.create!(name: "Genetics Lab")
  
  # Ensure roles exist
  role_owner = UserRole.find_by(name: 'Owner') || UserRole.first
  role_user = UserRole.find_by(name: 'User') || UserRole.second
  
  # Helper to ensure a user exists
  def ensure_user(email, first, last)
    u = User.find_or_initialize_by(email: email)
    if u.new_record?
      u.full_name = "#{first} #{last}"
      u.password = 'password123'
      u.password_confirmation = 'password123'
      u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
      u.save!
    end
    u
  end

  jane = ensure_user('jane.doe@example.com', 'Jane', 'Doe')
  john = ensure_user('john.smith@example.com', 'John', 'Smith')
  sarah = ensure_user('sarah.connor@example.com', 'Sarah', 'Connor')

  # Ensure they are on the Team
  [jane, john, sarah].each do |u|
    UserAssignment.find_or_create_by!(assignable: team, user: u) do |ua|
      ua.user_role = role_user
    end
  end

  # Create Project
  proj = Project.find_or_initialize_by(name: 'Zebrafish Gene Editing', team: team)
  proj.created_by_id = admin.id
  proj.save!

  # Reset project assignments to starting state
  UserAssignment.where(assignable: proj).destroy_all
  
  # Assign Admin (Owner), Jane (User), and John (User)
  UserAssignment.create!(assignable: proj, user: admin, user_role: role_owner)
  UserAssignment.create!(assignable: proj, user: jane, user_role: role_user)
  UserAssignment.create!(assignable: proj, user: john, user_role: role_user)
  # Note: Sarah is purposely NOT assigned to the project yet

  puts "Setup complete: Project created and users initialized."
rescue => e
  puts "Error during setup: #{e.message}"
  exit 1
end
EOF

# Copy and execute the setup script inside the SciNote web container
docker cp /tmp/setup_permissions.rb scinote_web:/tmp/setup_permissions.rb
docker exec scinote_web bash -c "bundle exec rails runner /tmp/setup_permissions.rb"

# Record the exact start time to prevent gaming (agent must act AFTER this timestamp)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Start Firefox and navigate to the projects page
ensure_firefox_running "${SCINOTE_URL}/projects"

# Wait a moment for rendering, then take the initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="