#!/bin/bash
# OpenProject Setup Script (post_start hook)
# Starts OpenProject via Docker Compose, seeds realistic project management data,
# and launches Firefox pointed at the login page.

set -e

echo "=== Setting up OpenProject via Docker ==="

XAUTH="/run/user/1000/gdm/Xauthority"
OP_DIR="/home/ga/openproject"
OP_URL="http://localhost:8080"
OP_LOGIN_URL="${OP_URL}/login"
CONTAINER_NAME="openproject"
SEED_RESULT="/tmp/openproject_seed_result.json"

# -----------------------------------------------------------------------
# 1. Wait for Docker daemon
# -----------------------------------------------------------------------
wait_for_docker() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker info >/dev/null 2>&1; then
            echo "Docker daemon is ready"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: Docker daemon not ready after ${timeout}s"
    return 1
}
wait_for_docker

# -----------------------------------------------------------------------
# 2. Authenticate with Docker Hub to avoid rate limits
# -----------------------------------------------------------------------
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin \
        && echo "Docker Hub auth successful" \
        || echo "Docker Hub auth failed (continuing anyway)"
else
    echo "No .dockerhub_credentials found — proceeding without authentication"
fi

# -----------------------------------------------------------------------
# 3. Copy docker-compose.yml to writable home directory
# -----------------------------------------------------------------------
echo "Setting up Docker Compose configuration..."
mkdir -p "$OP_DIR"
cp /workspace/config/docker-compose.yml "$OP_DIR/"
chown -R ga:ga "$OP_DIR"

# -----------------------------------------------------------------------
# 4. Pull image and start container
# -----------------------------------------------------------------------
echo "Pulling OpenProject image..."
cd "$OP_DIR"
docker compose pull

echo "Starting OpenProject container..."
docker compose up -d

echo "Container status:"
docker compose ps

# -----------------------------------------------------------------------
# 5. Wait for HTTP readiness
# -----------------------------------------------------------------------
wait_for_http() {
    local url="$1"
    local timeout_sec="${2:-600}"
    local elapsed=0
    echo "Waiting for HTTP readiness: $url"
    while [ "$elapsed" -lt "$timeout_sec" ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
        [ -z "$code" ] && code="000"
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "303" ]; then
            echo "HTTP ready after ${elapsed}s (HTTP $code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  waiting... ${elapsed}s (HTTP $code)"
    done
    echo "WARNING: Timeout waiting for OpenProject at $url"
    docker compose logs --tail 50 2>&1 || true
    return 1
}
wait_for_http "$OP_LOGIN_URL" 600

# Give it extra time after responding (Rails boot)
sleep 10

# -----------------------------------------------------------------------
# 6. Seed OpenProject with realistic project management data via Rails runner
# -----------------------------------------------------------------------
echo "=== Seeding OpenProject with realistic data ==="

cat > /tmp/openproject_seed.rb << 'RUBY_SEED_EOF'
require 'json'

result = {projects: [], users: [], work_packages: []}

begin
  # ---- Create regular users ----
  users_data = [
    {login: 'alice.johnson', firstname: 'Alice', lastname: 'Johnson',
     mail: 'alice.johnson@techcorp.example', password: 'User1234!@'},
    {login: 'bob.smith', firstname: 'Bob', lastname: 'Smith',
     mail: 'bob.smith@techcorp.example', password: 'User1234!@'},
    {login: 'carol.williams', firstname: 'Carol', lastname: 'Williams',
     mail: 'carol.williams@techcorp.example', password: 'User1234!@'},
  ]

  created_users = {}
  users_data.each do |data|
    u = User.find_by(login: data[:login])
    if u.nil?
      u = User.new
      u.login = data[:login]
      u.firstname = data[:firstname]
      u.lastname = data[:lastname]
      u.mail = data[:mail]
      u.password = data[:password]
      u.password_confirmation = data[:password]
      u.force_password_change = false
      u.status = User.statuses[:active]
      u.save!
      puts "Created user: #{data[:login]}"
    else
      puts "User exists: #{data[:login]}"
    end
    created_users[data[:login]] = u
    result[:users] << {login: data[:login], id: u.id,
                       name: "#{data[:firstname]} #{data[:lastname]}"}
  end

  admin_user = User.find_by(login: 'admin')

  # ---- Create projects ----
  projects_data = [
    {name: 'E-Commerce Platform', identifier: 'ecommerce-platform',
     description: 'Build and maintain the company e-commerce website and backend services.'},
    {name: 'Mobile Banking App', identifier: 'mobile-banking-app',
     description: 'Develop a secure mobile banking application for iOS and Android platforms.'},
    {name: 'DevOps Automation', identifier: 'devops-automation',
     description: 'Infrastructure automation, CI/CD pipelines, and deployment management.'},
  ]

  developer_role = Role.find_by(name: 'Developer') || Role.find_by(name: 'Member') || Role.where(builtin: 0).first
  manager_role   = Role.find_by(name: 'Project admin') || Role.find_by(name: 'Manager') || developer_role
  puts "Using role: #{developer_role.name} (id: #{developer_role.id})"

  def add_member_with_role(project, user, role)
    m = Member.find_by(project: project, principal: user)
    if m.nil?
      m = Member.new(project: project, principal: user)
      m.member_roles.build(role: role)
      m.save!
      puts "  Added #{user.login} to #{project.name}"
    end
    m
  end

  created_projects = {}
  projects_data.each do |data|
    p = Project.find_by(identifier: data[:identifier])
    if p.nil?
      p = Project.new
      p.name = data[:name]
      p.identifier = data[:identifier]
      p.description = data[:description]
      p.save!
      puts "Created project: #{data[:name]}"
    else
      puts "Project exists: #{data[:name]}"
    end
    created_projects[data[:identifier]] = p
    result[:projects] << {name: data[:name], id: p.id, identifier: data[:identifier]}

    # Enable modules
    [:work_package_tracking, :wiki, :timelines, :time_tracking, :news].each do |mod|
      EnabledModule.find_or_create_by(project: p, name: mod.to_s) rescue nil
    end

    # Add members with roles in one step (roles must be present before save!)
    created_users.values.each do |user|
      add_member_with_role(p, user, developer_role) rescue puts("  WARN: member #{user.login}: #{$!.message}")
    end

    if admin_user
      add_member_with_role(p, admin_user, manager_role) rescue puts("  WARN: admin member: #{$!.message}")
    end
  end

  # ---- Create versions (sprints) ----
  versions_per_project = {
    'ecommerce-platform' => [
      'Sprint 1 - Launch MVP', 'Sprint 2 - Search & Filters', 'Sprint 3 - Checkout Flow'],
    'mobile-banking-app'  => [
      'Sprint 1 - Auth & Onboarding', 'Sprint 2 - Transactions', 'Sprint 3 - Notifications'],
    'devops-automation'   => [
      'Sprint 1 - CI Pipeline', 'Sprint 2 - Deploy Automation', 'Sprint 3 - Monitoring'],
  }
  created_versions = {}
  versions_per_project.each do |proj_id, names|
    project = created_projects[proj_id]
    created_versions[proj_id] = []
    names.each_with_index do |vname, idx|
      v = Version.find_by(project: project, name: vname)
      if v.nil?
        v = Version.new
        v.project = project
        v.name = vname
        v.status = 'open'
        v.start_date = Date.today - (60 - idx * 20)
        v.effective_date = Date.today + (30 + idx * 14)
        v.save!
        puts "  Created version: #{vname}"
      end
      created_versions[proj_id] << v
    end
  end

  # ---- Work package types/statuses ----
  task_type    = Type.find_by(name: 'Task')    || Type.order(:id).first
  bug_type     = Type.find_by(name: 'Bug')     || task_type
  feature_type = Type.find_by(name: 'Feature') || task_type

  new_status         = Status.find_by(name: 'New')         || Status.order(:id).first
  in_progress_status = Status.find_by(name: 'In progress') || new_status
  resolved_status    = Status.find_by(name: 'Closed')      || new_status
  default_priority   = IssuePriority.find_by(is_default: true) ||
                        IssuePriority.find_by(name: 'Normal') ||
                        IssuePriority.order(:id).first

  alice = created_users['alice.johnson']
  bob   = created_users['bob.smith']
  carol = created_users['carol.williams']

  # ---- Work packages per project ----
  all_work_packages = {
    'ecommerce-platform' => [
      {subject: 'Implement product search with Elasticsearch', type: feature_type,
       status: in_progress_status, assigned_to: alice,
       version: created_versions['ecommerce-platform'][0],
       description: 'Integrate Elasticsearch for full-text product search with faceted filtering.'},
      {subject: 'Fix broken checkout on mobile Safari', type: bug_type,
       status: new_status, assigned_to: bob,
       version: created_versions['ecommerce-platform'][0],
       description: 'Payment form fails to submit on iOS Safari 16 and earlier.'},
      {subject: 'Implement product recommendation engine', type: feature_type,
       status: new_status, assigned_to: carol,
       version: created_versions['ecommerce-platform'][1],
       description: 'Add collaborative filtering-based recommendation widget on product pages.'},
      {subject: 'Optimize database queries for category listing', type: task_type,
       status: resolved_status, assigned_to: alice,
       version: created_versions['ecommerce-platform'][0],
       description: 'Reduce N+1 query issues in category controller actions.'},
      {subject: 'Add wishlist feature', type: feature_type,
       status: new_status, assigned_to: bob,
       version: created_versions['ecommerce-platform'][1],
       description: 'Allow users to save products to a persistent wishlist across sessions.'},
    ],
    'mobile-banking-app' => [
      {subject: 'Implement biometric login (Face ID / Fingerprint)', type: feature_type,
       status: in_progress_status, assigned_to: carol,
       version: created_versions['mobile-banking-app'][0],
       description: 'Add Face ID and fingerprint authentication for iOS and Android.'},
      {subject: 'Fix transaction history pagination bug', type: bug_type,
       status: new_status, assigned_to: alice,
       version: created_versions['mobile-banking-app'][1],
       description: 'Transactions older than 90 days not appearing in paginated results.'},
      {subject: 'Add push notification for large transactions', type: feature_type,
       status: new_status, assigned_to: bob,
       version: created_versions['mobile-banking-app'][2],
       description: 'Send real-time push notification when transaction exceeds $500.'},
      {subject: 'Security audit - JWT token expiration', type: task_type,
       status: in_progress_status, assigned_to: carol,
       version: created_versions['mobile-banking-app'][0],
       description: 'Verify JWT tokens expire correctly and refresh tokens are invalidated on logout.'},
      {subject: 'Implement recurring payment scheduler', type: feature_type,
       status: new_status, assigned_to: alice,
       version: created_versions['mobile-banking-app'][1],
       description: 'Allow users to schedule recurring payments (weekly, monthly).'},
    ],
    'devops-automation' => [
      {subject: 'Set up GitHub Actions CI pipeline for all microservices', type: task_type,
       status: resolved_status, assigned_to: bob,
       version: created_versions['devops-automation'][0],
       description: 'Configure automated testing and linting for each microservice repository.'},
      {subject: 'Kubernetes cluster autoscaling misconfigured', type: bug_type,
       status: in_progress_status, assigned_to: carol,
       version: created_versions['devops-automation'][1],
       description: 'HPA not scaling down correctly under low load conditions.'},
      {subject: 'Implement blue-green deployment strategy', type: feature_type,
       status: new_status, assigned_to: alice,
       version: created_versions['devops-automation'][1],
       description: 'Zero-downtime deployments using blue-green switching in production.'},
      {subject: 'Set up Prometheus and Grafana monitoring stack', type: task_type,
       status: in_progress_status, assigned_to: bob,
       version: created_versions['devops-automation'][2],
       description: 'Deploy monitoring with alerting for CPU, memory, and API latency metrics.'},
      {subject: 'Automate SSL certificate renewal with Certbot', type: task_type,
       status: new_status, assigned_to: carol,
       version: created_versions['devops-automation'][2],
       description: 'Set up automated certificate renewal via Lets Encrypt for all domains.'},
    ],
  }

  all_work_packages.each do |proj_identifier, wps|
    project = created_projects[proj_identifier]
    wps.each do |wp_data|
      wp = WorkPackage.find_by(project: project, subject: wp_data[:subject])
      if wp.nil?
        wp = WorkPackage.new
        wp.project = project
        wp.subject = wp_data[:subject]
        wp.author = admin_user
        wp.type = wp_data[:type]
        wp.status = wp_data[:status]
        wp.priority = default_priority
        wp.assigned_to = wp_data[:assigned_to]
        wp.version = wp_data[:version]
        begin
          wp.description = wp_data[:description]
        rescue; nil; end
        wp.save!
        puts "  Created WP (#{proj_identifier}): #{wp.subject[0..60]}"
      else
        puts "  WP exists (#{proj_identifier}): #{wp.subject[0..60]}"
      end
      result[:work_packages] << {
        id: wp.id,
        subject: wp.subject,
        project_identifier: proj_identifier,
        status: (wp.status&.name rescue 'unknown'),
        assigned_to_login: (wp.assigned_to&.login rescue nil)
      }
    end
  end

  puts "\nSEED_RESULT_JSON_START"
  puts result.to_json
  puts "SEED_RESULT_JSON_END"

rescue => e
  puts "ERROR in seed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  puts "\nSEED_RESULT_JSON_START"
  puts result.to_json
  puts "SEED_RESULT_JSON_END"
end
RUBY_SEED_EOF

echo "Seeding OpenProject project/work packages (real data snapshot)..."
docker cp /tmp/openproject_seed.rb "$CONTAINER_NAME":/tmp/openproject_seed.rb

SEED_RAW=$(docker exec "$CONTAINER_NAME" bash -c "
    cd /app && bundle exec rails runner /tmp/openproject_seed.rb 2>&1
" 2>&1 || echo "SEED_FAILED")

echo "$SEED_RAW" | tail -80

JSON_CONTENT=$(echo "$SEED_RAW" | awk '/SEED_RESULT_JSON_START/{p=1; next} /SEED_RESULT_JSON_END/{p=0} p')

if [ -n "$JSON_CONTENT" ]; then
    echo "$JSON_CONTENT" > "$SEED_RESULT"
    chmod 644 "$SEED_RESULT"
    cp "$SEED_RESULT" /home/ga/openproject_seed_result.json
    chown ga:ga /home/ga/openproject_seed_result.json
    echo "Seed result written: $SEED_RESULT"
    echo "Projects: $(echo "$JSON_CONTENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('projects',[])))" 2>/dev/null || echo '?')"
    echo "Users: $(echo "$JSON_CONTENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('users',[])))" 2>/dev/null || echo '?')"
    echo "Work Packages: $(echo "$JSON_CONTENT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('work_packages',[])))" 2>/dev/null || echo '?')"
else
    echo "WARNING: Could not extract seed JSON, writing empty result"
    echo '{"projects":[],"users":[],"work_packages":[]}' > "$SEED_RESULT"
    cp "$SEED_RESULT" /home/ga/openproject_seed_result.json
    chown ga:ga /home/ga/openproject_seed_result.json
fi

# Also write legacy path for any existing task scripts that use it
cp "$SEED_RESULT" /home/ga/openproject_seed_ids.json 2>/dev/null || true
chown ga:ga /home/ga/openproject_seed_ids.json 2>/dev/null || true

# -----------------------------------------------------------------------
# 7. Create admin API token for verifier / task_utils.sh API calls
#    (OpenProject v15 uses apikey:<token> basic auth, not user:pass)
# -----------------------------------------------------------------------
echo "Creating admin API token..."
cat > /tmp/openproject_create_token.rb << 'RUBY_TOKEN_EOF'
u = User.find_by(login: 'admin')
Token::API.where(user_id: u.id).destroy_all
token = Token::API.new(user: u)
token.save!
puts token.plain_value
RUBY_TOKEN_EOF

docker cp /tmp/openproject_create_token.rb "$CONTAINER_NAME":/tmp/openproject_create_token.rb
API_TOKEN=$(docker exec "$CONTAINER_NAME" bash -c \
    "cd /app && bundle exec rails runner /tmp/openproject_create_token.rb 2>/dev/null" \
    | grep -v 'INFO\|WARNING\|ActiveJob\|Enqueued' | tail -1)

if [ -n "$API_TOKEN" ]; then
    echo "$API_TOKEN" > /home/ga/openproject_api_token.txt
    chmod 600 /home/ga/openproject_api_token.txt
    chown ga:ga /home/ga/openproject_api_token.txt
    echo "API token written to /home/ga/openproject_api_token.txt"
else
    echo "WARNING: Could not create API token"
fi

# -----------------------------------------------------------------------
# 8. Set up Firefox snap profile (suppress first-run dialogs)
# -----------------------------------------------------------------------
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
mkdir -p "${FIREFOX_PROFILE_BASE}/openproject.profile"

cat > "${FIREFOX_PROFILE_BASE}/profiles.ini" << 'PROFILES_EOF'
[Profile0]
Name=openproject
IsRelative=1
Path=openproject.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFILES_EOF

cat > "${FIREFOX_PROFILE_BASE}/openproject.profile/user.js" << 'USER_JS_EOF'
user_pref("browser.startup.homepage", "http://localhost:8080/login");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("extensions.autoDisableScopes", 15);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("privacy.notices.shown", true);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("signon.management.page.breach-alerts.enabled", false);
user_pref("signon.autofillForms", false);
user_pref("signon.rememberSignons", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("browser.uitour.enabled", false);
USER_JS_EOF

chown -R ga:ga /home/ga/snap/ 2>/dev/null || true
echo "Firefox profile ready: ${FIREFOX_PROFILE_BASE}/openproject.profile"

# -----------------------------------------------------------------------
# 8. Re-verify OpenProject and launch Firefox
# -----------------------------------------------------------------------
echo "Re-verifying OpenProject is responsive before launching Firefox..."
for i in $(seq 1 60); do
    if curl -s -o /dev/null -w "%{http_code}" "${OP_LOGIN_URL}" 2>/dev/null | grep -qE "200|302|303"; then
        echo "OpenProject web service ready"
        break
    fi
    sleep 2
done

pkill -9 -f firefox 2>/dev/null || true
for i in $(seq 1 10); do
    pgrep -f firefox >/dev/null 2>&1 || break
    sleep 1
done
sleep 2

rm -f "${FIREFOX_PROFILE_BASE}/openproject.profile/.parentlock" \
      "${FIREFOX_PROFILE_BASE}/openproject.profile/lock" 2>/dev/null || true

PROFILE_PATH="${FIREFOX_PROFILE_BASE}/openproject.profile"
su - ga -c "
    rm -f '${PROFILE_PATH}/.parentlock' '${PROFILE_PATH}/lock' 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=${XAUTH} \
    setsid firefox --new-instance \
        -profile '${PROFILE_PATH}' \
        'http://localhost:8080/login' &
"

echo "Waiting for Firefox window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -qi "firefox"; then
        echo "Firefox window appeared after ${i}s"
        break
    fi
    sleep 2
done
sleep 3

DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: \
    -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# -----------------------------------------------------------------------
# 9. Log in as admin so the Firefox session is established for task scripts
# -----------------------------------------------------------------------
echo "Logging in as admin via Firefox..."
# Click on username field (coords: visual_grounding 717,257 × 1.5 for 1920x1080 = 1076,386)
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool mousemove 1076 386" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool click 1" 2>/dev/null || true
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key ctrl+a" 2>/dev/null || true
sleep 0.2
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'admin'" 2>/dev/null
sleep 0.5
# Click on password field (visual_grounding 717,289 × 1.5 = 1076,434)
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool mousemove 1076 434" 2>/dev/null || true
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool click 1" 2>/dev/null || true
sleep 0.3
# Type password avoiding ! which can cause xdotool issues; use 'exclam' keysym instead
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'Admin1234'" 2>/dev/null
sleep 0.2
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key exclam" 2>/dev/null
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return" 2>/dev/null
echo "Login submitted, waiting for dashboard..."
sleep 10

DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: \
    -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

echo ""
echo "=== OpenProject setup complete ==="
echo "OpenProject URL: ${OP_LOGIN_URL}"
echo "Admin credentials: admin / Admin1234!"
echo "Users: alice.johnson, bob.smith, carol.williams (password: User1234!@)"
echo "Projects: ecommerce-platform, mobile-banking-app, devops-automation"
echo "Seed mapping: ${SEED_RESULT}"
