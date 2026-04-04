#!/usr/bin/env ruby
# Redmine seed script — run via: bundle exec rails runner seed_redmine.rb -e production
# Seeds realistic project management data for gym_anything tasks.

require 'json'

puts "=== Seeding Redmine with realistic data ==="

# ============================================================
# 1. Configure admin account
# ============================================================
admin = User.find_by(login: 'admin')
if admin
  admin.password = 'Admin1234!'
  admin.password_confirmation = 'Admin1234!'
  admin.must_change_passwd = false
  admin.firstname = 'Redmine'
  admin.lastname = 'Administrator'
  admin.save!
  puts "Admin configured: admin / Admin1234!"
else
  puts "WARNING: admin user not found"
end

# ============================================================
# 2. Enable REST API
# ============================================================
setting = Setting.find_by(name: 'rest_api_enabled')
if setting
  setting.value = '1'
  setting.save!
else
  Setting.create!(name: 'rest_api_enabled', value: '1')
end
puts "REST API enabled"

# Disable login required for API (allow API key auth)
Setting['login_required'] = '0' rescue nil

# ============================================================
# 3. Lookup default trackers, statuses, priorities, roles
# ============================================================
tracker_bug     = Tracker.find_by(name: 'Bug')
tracker_feature = Tracker.find_by(name: 'Feature')
tracker_support = Tracker.find_by(name: 'Support')

status_new        = IssueStatus.find_by(name: 'New')
status_in_progress = IssueStatus.find_by(name: 'In Progress')
status_resolved   = IssueStatus.find_by(name: 'Resolved')
status_closed     = IssueStatus.find_by(name: 'Closed')
status_feedback   = IssueStatus.find_by(name: 'Feedback')

priority_low      = IssuePriority.find_by(name: 'Low')
priority_normal   = IssuePriority.find_by(name: 'Normal')
priority_high     = IssuePriority.find_by(name: 'High')
priority_urgent   = IssuePriority.find_by(name: 'Urgent')
priority_immediate = IssuePriority.find_by(name: 'Immediate')

role_manager  = Role.find_by(name: 'Manager')
role_developer = Role.find_by(name: 'Developer')
role_reporter = Role.find_by(name: 'Reporter')

puts "Trackers: #{[tracker_bug, tracker_feature, tracker_support].map(&:name).join(', ')}"
puts "Statuses: #{[status_new, status_in_progress, status_resolved, status_closed].map(&:name).join(', ')}"
puts "Priorities: #{[priority_low, priority_normal, priority_high, priority_urgent].map(&:name).join(', ')}"

# Default time entry activity
activity_dev  = TimeEntryActivity.find_by(name: 'Development')
activity_design = TimeEntryActivity.find_by(name: 'Design')
activity_test = TimeEntryActivity.find_by(name: 'Testing') || TimeEntryActivity.find_by(name: 'QA')

# ============================================================
# 4. Create users
# ============================================================
users_data = [
  { login: 'alice.chen',    firstname: 'Alice',   lastname: 'Chen',      mail: 'alice.chen@devlabs.io',    role: role_manager },
  { login: 'bob.walker',    firstname: 'Bob',     lastname: 'Walker',    mail: 'bob.walker@devlabs.io',    role: role_developer },
  { login: 'carol.santos',  firstname: 'Carol',   lastname: 'Santos',    mail: 'carol.santos@devlabs.io',  role: role_developer },
  { login: 'david.kim',     firstname: 'David',   lastname: 'Kim',       mail: 'david.kim@devlabs.io',     role: role_developer },
  { login: 'eve.martinez',  firstname: 'Eve',     lastname: 'Martinez',  mail: 'eve.martinez@devlabs.io',  role: role_reporter },
  { login: 'frank.nguyen',  firstname: 'Frank',   lastname: 'Nguyen',    mail: 'frank.nguyen@devlabs.io',  role: role_reporter },
  { login: 'grace.lee',     firstname: 'Grace',   lastname: 'Lee',       mail: 'grace.lee@devlabs.io',     role: role_developer },
]

created_users = {}
users_data.each do |ud|
  u = User.find_by(login: ud[:login])
  unless u
    u = User.new(
      login: ud[:login],
      firstname: ud[:firstname],
      lastname: ud[:lastname],
      mail: ud[:mail],
      password: 'DevLabs2024!',
      password_confirmation: 'DevLabs2024!'
    )
    u.must_change_passwd = false
    u.save!
  end
  created_users[ud[:login]] = { user: u, default_role: ud[:role] }
  puts "  User: #{ud[:login]} (#{u.id})"
end

# ============================================================
# 5. Create projects
# ============================================================
projects_data = [
  {
    name: 'Phoenix E-Commerce Platform',
    identifier: 'phoenix-ecommerce',
    description: 'Full rebuild of the customer-facing online store with React frontend, Node.js backend, and PostgreSQL. Target: 10x performance improvement and modern UX.',
    members: ['alice.chen', 'bob.walker', 'carol.santos', 'eve.martinez'],
    trackers: [tracker_bug, tracker_feature, tracker_support],
    categories: ['Frontend', 'Backend', 'API', 'Database', 'Security', 'Performance'],
    versions: [
      { name: 'v1.0 Launch',    description: 'Initial public release — MVP feature set', due: Date.today + 45, status: 'open' },
      { name: 'v1.1 Patch',     description: 'Bug fixes and performance improvements post-launch', due: Date.today + 75, status: 'open' },
      # Create as open first so we can assign issues; close it at the end of seed
      { name: 'v0.9 Beta',      description: 'Closed beta testing phase', due: Date.today - 15, status: 'open' },
    ]
  },
  {
    name: 'Mobile Application v2',
    identifier: 'mobile-app-v2',
    description: 'Cross-platform mobile app (iOS and Android) using React Native. Complete rewrite from v1 with offline support, push notifications, and biometric authentication.',
    members: ['alice.chen', 'david.kim', 'grace.lee', 'frank.nguyen'],
    trackers: [tracker_bug, tracker_feature, tracker_support],
    categories: ['iOS', 'Android', 'Authentication', 'Notifications', 'Offline', 'UI/UX'],
    versions: [
      { name: 'v2.0 Release',  description: 'First major release of the v2 rewrite', due: Date.today + 60, status: 'open' },
      { name: 'v2.1 Hotfix',   description: 'Emergency fixes for critical v2.0 bugs', due: Date.today + 90, status: 'open' },
      # Create as open first so we can assign issues; close it at the end of seed
      { name: 'v1.9 Legacy',   description: 'Final update to legacy v1 before sunset', due: Date.today - 30, status: 'open' },
    ]
  },
  {
    name: 'Infrastructure & DevOps',
    identifier: 'infra-devops',
    description: 'Internal operations: CI/CD pipeline improvements, Kubernetes migration, monitoring & alerting, and security hardening. Supports all engineering teams.',
    members: ['alice.chen', 'carol.santos', 'david.kim'],
    trackers: [tracker_bug, tracker_feature, tracker_support],
    categories: ['CI/CD', 'Kubernetes', 'Monitoring', 'Security', 'Database', 'Networking'],
    versions: [
      { name: 'Q1 2025 Goals',  description: 'Q1 infrastructure improvements', due: Date.today + 30, status: 'open' },
      { name: 'Q2 2025 Goals',  description: 'Q2 infrastructure improvements', due: Date.today + 120, status: 'open' },
    ]
  },
]

created_projects = {}
projects_data.each do |pd|
  project = Project.find_by(identifier: pd[:identifier])
  unless project
    project = Project.new(
      name: pd[:name],
      identifier: pd[:identifier],
      description: pd[:description],
      is_public: false
    )
    project.enabled_module_names = ['issue_tracking', 'time_tracking', 'wiki', 'files', 'repository']
    project.trackers = pd[:trackers].compact
    project.save!
  end

  # Add members
  pd[:members].each do |login|
    next unless created_users[login]
    u = created_users[login][:user]
    role = created_users[login][:default_role]
    unless Member.find_by(project: project, user: u)
      Member.create!(project: project, user: u, roles: [role])
    end
    # Add admin as member too
    unless Member.find_by(project: project, user: admin)
      Member.create!(project: project, user: admin, roles: [role_manager])
    end
  end

  # Create categories
  pd[:categories].each do |cat_name|
    unless IssueCategory.find_by(project: project, name: cat_name)
      IssueCategory.create!(project: project, name: cat_name)
    end
  end

  # Create versions
  pd[:versions].each do |vd|
    unless Version.find_by(project: project, name: vd[:name])
      Version.create!(
        project: project,
        name: vd[:name],
        description: vd[:description],
        due_date: vd[:due],
        status: vd[:status]
      )
    end
  end

  created_projects[pd[:identifier]] = project
  puts "  Project: #{pd[:name]} (#{project.id})"
end

# ============================================================
# 6. Create issues
# ============================================================
issues_seed = [
  # === Phoenix E-Commerce Platform ===
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_bug,
    subject: 'Login button unresponsive on mobile Safari iOS 17',
    description: "Users on iOS 17.x Safari report that the login button does not respond to taps. The issue appears to be related to the new pointer events handling in WebKit. Reproducible on iPhone 14 and 15 series.\n\nSteps to reproduce:\n1. Open app URL in Safari on iOS 17\n2. Enter credentials\n3. Tap the Login button\n4. Nothing happens — no spinner, no error, no navigation\n\nExpected: user is authenticated and redirected to dashboard\nActual: no response whatsoever",
    status: status_new, priority: priority_high, author: 'alice.chen', assignee: 'bob.walker',
    category: 'Frontend', version: 'v1.0 Launch', due: Date.today + 7,
    estimated_hours: 8
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_bug,
    subject: 'Payment gateway timeout during peak traffic (>500 concurrent users)',
    description: "The payment processing endpoint /api/v1/checkout/payment times out under load. Stripe API calls exceed the 30s request timeout when concurrent users exceed 500.\n\nLoad test results:\n- 100 users: avg 1.2s response ✓\n- 250 users: avg 4.8s response ✓\n- 500 users: avg 34s → timeout ✗\n\nRoot cause hypothesis: N+1 queries in CartService.process_payment() are starving the connection pool.",
    status: status_in_progress, priority: priority_urgent, author: 'eve.martinez', assignee: 'carol.santos',
    category: 'Performance', version: 'v1.0 Launch', due: Date.today + 3,
    estimated_hours: 16
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_bug,
    subject: 'Product images not loading after CDN migration',
    description: "Since migrating static assets to CloudFront CDN, approximately 15% of product images return 403 Forbidden errors. The issue appears intermittent and correlates with cache invalidation events.\n\nAffected image format: .webp (original .jpg files serve correctly).\nError in browser: GET https://cdn.devlabs.io/products/[id].webp 403",
    status: status_new, priority: priority_high, author: 'frank.nguyen', assignee: 'bob.walker',
    category: 'Frontend', version: 'v1.1 Patch', due: Date.today + 10,
    estimated_hours: 5
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_bug,
    subject: 'Search autocomplete returns stale results after product deletion',
    description: "When a product is deleted from the catalog, the Elasticsearch search index is not updated synchronously. The autocomplete dropdown continues to show deleted products for up to 15 minutes.\n\nThis causes a confusing UX where users click a suggested product and land on a 404 page.",
    status: status_feedback, priority: priority_normal, author: 'alice.chen', assignee: 'carol.santos',
    category: 'Backend', version: 'v1.1 Patch', due: Date.today + 14,
    estimated_hours: 6
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_feature,
    subject: 'Implement wishlist feature with social sharing',
    description: "Users should be able to add products to a personal wishlist and share it via a unique URL. The wishlist should persist across sessions and devices.\n\nAcceptance criteria:\n- Add/remove items via heart icon on product cards\n- Wishlist page at /my/wishlist\n- Share button generates shareable link\n- Shared wishlists are read-only for recipients\n- Email notification when wishlist items go on sale",
    status: status_new, priority: priority_normal, author: 'alice.chen', assignee: 'bob.walker',
    category: 'Frontend', version: 'v1.1 Patch', due: Date.today + 30,
    estimated_hours: 24
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_feature,
    subject: 'Add product comparison table (up to 4 products)',
    description: "Allow users to compare up to 4 products side-by-side in a sticky comparison bar and full comparison table. Feature should work on mobile with horizontal scroll.\n\nKey specs:\n- Floating comparison bar at bottom of screen when 2+ products selected\n- Full comparison page at /compare?ids=1,2,3\n- Attributes to compare: price, rating, key specs, availability\n- Shareable comparison URLs",
    status: status_in_progress, priority: priority_normal, author: 'eve.martinez', assignee: 'carol.santos',
    category: 'Frontend', version: 'v1.1 Patch', due: Date.today + 25,
    estimated_hours: 20
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_support,
    subject: 'Customer reports duplicate charge after network error during checkout',
    description: "Customer order #ORD-2025-88234 was charged twice. Customer completed checkout, received network error, retried, and was charged again. Our idempotency key implementation in the payment service appears to have a race condition.\n\nCustomer: Jane Doe (customer_id: 48291)\nAmount: $147.99 × 2\nDate: 2025-11-14 14:23 UTC",
    status: status_in_progress, priority: priority_urgent, author: 'frank.nguyen', assignee: 'carol.santos',
    category: 'Backend', version: nil, due: Date.today + 1,
    estimated_hours: 4
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_bug,
    subject: 'Filter sidebar resets when navigating back from product page',
    description: "When a user applies filters (category, price range, rating), clicks into a product detail page, and presses the browser back button, all applied filters are lost.\n\nExpected: filters should persist via URL parameters or browser history state.\nActual: filter state is reset to defaults.",
    status: status_resolved, priority: priority_normal, author: 'frank.nguyen', assignee: 'bob.walker',
    category: 'Frontend', version: 'v0.9 Beta', due: nil,
    estimated_hours: 6
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_bug,
    subject: 'Admin dashboard charts broken in Firefox 120+',
    description: "All Chart.js charts on the admin dashboard (/admin/analytics) render as empty white boxes in Firefox 120 and above. The issue does not affect Chrome or Safari.\n\nConsole error: TypeError: Cannot read properties of undefined (reading 'getContext')\n\nSuspected cause: timing issue with DOM ready and Chart.js initialization.",
    status: status_closed, priority: priority_normal, author: 'alice.chen', assignee: 'bob.walker',
    category: 'Frontend', version: 'v0.9 Beta', due: nil,
    estimated_hours: 3
  },
  {
    project: 'phoenix-ecommerce',
    tracker: tracker_feature,
    subject: 'Add dark mode support with system preference detection',
    description: "Implement dark mode using CSS custom properties. Should auto-detect OS preference (prefers-color-scheme media query) and allow manual toggle in user settings.\n\nDesign mockups are attached in the wiki. Token names follow the design system conventions.",
    status: status_new, priority: priority_low, author: 'alice.chen', assignee: nil,
    category: 'Frontend', version: 'v1.1 Patch', due: Date.today + 45,
    estimated_hours: 16
  },

  # === Mobile Application v2 ===
  {
    project: 'mobile-app-v2',
    tracker: tracker_bug,
    subject: 'Biometric authentication fails after app backgrounding on Android 14',
    description: "On Android 14 devices, biometric auth (fingerprint/face ID) fails with error code BIOMETRIC_ERROR_HW_UNAVAILABLE when the app is brought back from background.\n\nReproduction:\n1. Open app, enable biometric login\n2. Background the app (home button)\n3. Return to app\n4. Attempt biometric auth\n5. Error appears — user must enter PIN instead\n\nNot reproducible on Android 12 or 13.",
    status: status_new, priority: priority_high, author: 'alice.chen', assignee: 'david.kim',
    category: 'Android', version: 'v2.0 Release', due: Date.today + 5,
    estimated_hours: 12
  },
  {
    project: 'mobile-app-v2',
    tracker: tracker_bug,
    subject: 'Push notifications not delivered when app is force-closed on iOS',
    description: "Push notifications via APNs are not delivered when the app is force-closed on iOS (swiped away in app switcher). Background delivery works correctly.\n\nAffected: iOS 16.x and 17.x\nNot affected: Android (FCM)\n\nFCM/APNs token is correctly registered. Server-side delivery logs show successful APNs response (HTTP 200). Issue appears to be in how we handle the notification payload — content-available flag may not be set correctly.",
    status: status_in_progress, priority: priority_high, author: 'frank.nguyen', assignee: 'grace.lee',
    category: 'iOS', version: 'v2.0 Release', due: Date.today + 7,
    estimated_hours: 10
  },
  {
    project: 'mobile-app-v2',
    tracker: tracker_bug,
    subject: 'Offline mode: local changes lost on sync conflict',
    description: "When user makes changes offline and syncs when connectivity is restored, if a server-side conflict exists, local changes are silently discarded without notifying the user.\n\nExpected: show conflict resolution UI or at minimum notify user of overwritten changes.\nActual: server version wins silently.",
    status: status_new, priority: priority_urgent, author: 'alice.chen', assignee: 'david.kim',
    category: 'Offline', version: 'v2.0 Release', due: Date.today + 10,
    estimated_hours: 20
  },
  {
    project: 'mobile-app-v2',
    tracker: tracker_feature,
    subject: 'Implement in-app review prompt (Apple/Google review flow)',
    description: "Integrate native in-app review flow for both iOS (SKStoreReviewController) and Android (Google Play In-App Review API).\n\nTrigger conditions:\n- User has completed ≥3 sessions\n- User has been using app for ≥7 days\n- Not shown more than once per 90 days\n- Never shown after a negative feedback event",
    status: status_new, priority: priority_low, author: 'alice.chen', assignee: 'grace.lee',
    category: 'UI/UX', version: 'v2.1 Hotfix', due: Date.today + 60,
    estimated_hours: 8
  },
  {
    project: 'mobile-app-v2',
    tracker: tracker_feature,
    subject: 'Add widget support for iOS 16+ Lock Screen',
    description: "Implement iOS Lock Screen widgets (WidgetKit) showing key app metrics. Three widget sizes: small (single metric), medium (3 metrics), large (trend chart + metrics).\n\nMetrics to expose: daily progress, streak count, pending actions count.",
    status: status_in_progress, priority: priority_normal, author: 'david.kim', assignee: 'grace.lee',
    category: 'iOS', version: 'v2.1 Hotfix', due: Date.today + 40,
    estimated_hours: 24
  },
  {
    project: 'mobile-app-v2',
    tracker: tracker_support,
    subject: 'User unable to log in after password reset on Android',
    description: "Multiple reports from Android users that after completing the password reset flow, attempting to log in with the new password fails with 'Invalid credentials' error.\n\nThis does not affect iOS. The API reset endpoint works correctly (tested via curl). Suspected issue: Android Keychain stores old credentials and auto-fills them, bypassing the user's input.",
    status: status_feedback, priority: priority_high, author: 'frank.nguyen', assignee: 'david.kim',
    category: 'Authentication', version: nil, due: Date.today + 2,
    estimated_hours: 5
  },
  {
    project: 'mobile-app-v2',
    tracker: tracker_bug,
    subject: 'Dark mode: tab bar icons inverted on Android 12 (Material You)',
    description: "On Android 12+ with Material You dynamic theming enabled, the bottom tab bar icons appear inverted (dark on dark background) when dark mode is active.\n\nRoot cause: we are not respecting the Material You color token system — hardcoded icon tints conflict with the dynamic color palette.",
    status: status_resolved, priority: priority_normal, author: 'grace.lee', assignee: 'david.kim',
    category: 'Android', version: 'v1.9 Legacy', due: nil,
    estimated_hours: 4
  },

  # === Infrastructure & DevOps ===
  {
    project: 'infra-devops',
    tracker: tracker_feature,
    subject: 'Migrate CI/CD from Jenkins to GitHub Actions',
    description: "Replace Jenkins self-hosted CI with GitHub Actions. Goals:\n- Eliminate Jenkins maintenance overhead\n- Use ephemeral runners for security\n- Reduce avg build time from 18 min to <8 min via better parallelization\n- Implement required status checks on main branch\n\nPhase 1: Migrate unit test jobs\nPhase 2: Migrate build & package jobs\nPhase 3: Migrate deployment jobs\nPhase 4: Decommission Jenkins",
    status: status_in_progress, priority: priority_high, author: 'alice.chen', assignee: 'carol.santos',
    category: 'CI/CD', version: 'Q1 2025 Goals', due: Date.today + 20,
    estimated_hours: 40
  },
  {
    project: 'infra-devops',
    tracker: tracker_feature,
    subject: 'Set up Kubernetes cluster for production workloads',
    description: "Deploy production-grade Kubernetes cluster on AWS EKS. Requirements:\n- Multi-AZ deployment (3 zones)\n- Auto-scaling node groups (min 3, max 20)\n- Cluster Autoscaler + Vertical Pod Autoscaler\n- RBAC with separate namespaces per service\n- Ingress controller (nginx)\n- cert-manager for TLS\n- Secrets management via AWS Secrets Manager",
    status: status_new, priority: priority_high, author: 'alice.chen', assignee: 'david.kim',
    category: 'Kubernetes', version: 'Q1 2025 Goals', due: Date.today + 35,
    estimated_hours: 80
  },
  {
    project: 'infra-devops',
    tracker: tracker_bug,
    subject: 'Staging database running out of disk space weekly',
    description: "The staging PostgreSQL instance (staging-db-01) consistently runs out of disk space every 7-10 days. Root cause: WAL archiving is enabled but retention cleanup is not running.\n\nImmediate fix: manual cleanup of pg_wal directory.\nLong-term fix: configure pg_wal retention policy and automate disk usage alerts.",
    status: status_in_progress, priority: priority_urgent, author: 'carol.santos', assignee: 'david.kim',
    category: 'Database', version: 'Q1 2025 Goals', due: Date.today + 2,
    estimated_hours: 8
  },
  {
    project: 'infra-devops',
    tracker: tracker_feature,
    subject: 'Implement centralized log aggregation with OpenSearch',
    description: "Deploy OpenSearch cluster (managed via AWS) for centralized log aggregation. Replace current approach of SSH-ing into servers to tail logs.\n\nComponents:\n- OpenSearch cluster (3 nodes)\n- Fluent Bit as log shipper on all EC2/K8s nodes\n- OpenSearch Dashboards for visualization\n- Index retention: 30 days hot, 90 days warm\n- Alerting via OpenSearch Alerting plugin",
    status: status_new, priority: priority_normal, author: 'david.kim', assignee: 'carol.santos',
    category: 'Monitoring', version: 'Q2 2025 Goals', due: Date.today + 90,
    estimated_hours: 60
  },
  {
    project: 'infra-devops',
    tracker: tracker_bug,
    subject: 'SSL certificate for api.devlabs.io expires in 14 days',
    description: "The TLS certificate for api.devlabs.io (SAN: api.devlabs.io, staging-api.devlabs.io) will expire on 2025-12-08. Auto-renewal via certbot is configured but has been failing silently for the past month.\n\nError in certbot logs: Permission denied when writing to /var/lib/letsencrypt/.\n\nNeed to:\n1. Fix certbot permissions\n2. Manually renew now\n3. Verify auto-renewal cron is working",
    status: status_resolved, priority: priority_urgent, author: 'carol.santos', assignee: 'david.kim',
    category: 'Security', version: 'Q1 2025 Goals', due: nil,
    estimated_hours: 3
  },
  {
    project: 'infra-devops',
    tracker: tracker_support,
    subject: 'Deployment to production stuck in pending state',
    description: "GitHub Actions deployment workflow for service `notification-worker` has been in 'pending' state for 45 minutes. No error logs visible. The runner appears healthy.\n\nSuspected cause: runner concurrency limit reached — we have 3 concurrent job limit on the self-hosted runner but 4 jobs queued.",
    status: status_closed, priority: priority_high, author: 'frank.nguyen', assignee: 'carol.santos',
    category: 'CI/CD', version: nil, due: nil,
    estimated_hours: 1
  },
]

created_issues = []
issues_seed.each do |idata|
  project = created_projects[idata[:project]]
  next unless project

  author_user = idata[:author] ? (User.find_by(login: idata[:author]) || admin) : admin
  assignee_user = idata[:assignee] ? User.find_by(login: idata[:assignee]) : nil
  category = idata[:category] ? IssueCategory.find_by(project: project, name: idata[:category]) : nil
  version = idata[:version] ? Version.find_by(project: project, name: idata[:version]) : nil

  existing = Issue.find_by(project: project, subject: idata[:subject])
  unless existing
    issue = Issue.new(
      project:          project,
      tracker:          idata[:tracker],
      subject:          idata[:subject],
      description:      idata[:description],
      status:           idata[:status],
      priority:         idata[:priority],
      author:           author_user,
      assigned_to:      assignee_user,
      category:         category,
      fixed_version:    version,
      due_date:         idata[:due],
      estimated_hours:  idata[:estimated_hours]
    )
    issue.save!
    existing = issue
  end

  created_issues << { id: existing.id, project: idata[:project], subject: idata[:subject] }
  puts "  Issue ##{existing.id}: #{idata[:subject][0..60]}..."
end

# ============================================================
# 7. Add journals (comments) to some issues
# ============================================================
journal_data = [
  { issue_subject: 'Login button unresponsive on mobile Safari iOS 17',
    author: 'bob.walker',
    notes: 'Confirmed reproducible. Traced to a Safari-specific behavior where pointer events on transformed elements are dropped. Testing fix with css `touch-action: manipulation` on the button.' },
  { issue_subject: 'Payment gateway timeout during peak traffic (>500 concurrent users)',
    author: 'carol.santos',
    notes: 'Root cause confirmed: CartService.process_payment() runs 47 queries per checkout due to ActiveRecord lazy loading. Implementing eager loading with `.includes(:line_items, :product)`. Expect 80% reduction in DB round-trips.' },
  { issue_subject: 'Payment gateway timeout during peak traffic (>500 concurrent users)',
    author: 'alice.chen',
    notes: 'Good progress Carol. Also check the connection pool config — we may be too conservative at pool_size=5 for the payments worker.' },
  { issue_subject: 'Migrate CI/CD from Jenkins to GitHub Actions',
    author: 'carol.santos',
    notes: 'Phase 1 complete — all unit test jobs migrated. Build times down from 18 min to 12 min already just from ephemeral runner overhead removal. Starting Phase 2 (build & package) next week.' },
  { issue_subject: 'Biometric authentication fails after app backgrounding on Android 14',
    author: 'david.kim',
    notes: 'Investigating. Android 14 changed the BiometricPrompt lifecycle — it no longer survives activity recreation. We need to re-create the BiometricPrompt instance in onResume().' },
  { issue_subject: 'Push notifications not delivered when app is force-closed on iOS',
    author: 'grace.lee',
    notes: 'Found the issue: our notification payload is missing content-available: 1 for background delivery. APNs requires this flag for silent/background push. Adding it now.' },
]

journal_data.each do |jd|
  issue = Issue.find_by('subject LIKE ?', "%#{jd[:issue_subject][0..40]}%")
  next unless issue
  author = User.find_by(login: jd[:author]) || admin
  journal = Journal.new(journalized: issue, user: author, notes: jd[:notes])
  journal.save!
  puts "  Journal added to ##{issue.id}"
end

# ============================================================
# 8. Add time entries
# ============================================================
time_entries_data = [
  { project: 'phoenix-ecommerce', issue_subject: 'Login button unresponsive on mobile Safari iOS 17',
    user: 'bob.walker', hours: 3.5, comments: 'Investigated and identified root cause. Testing fix.', activity: activity_dev },
  { project: 'phoenix-ecommerce', issue_subject: 'Payment gateway timeout during peak traffic (>500 concurrent users)',
    user: 'carol.santos', hours: 8.0, comments: 'Profiled and optimized N+1 queries in CartService.', activity: activity_dev },
  { project: 'phoenix-ecommerce', issue_subject: 'Payment gateway timeout during peak traffic (>500 concurrent users)',
    user: 'carol.santos', hours: 4.0, comments: 'Load testing with optimized queries. Results look promising.', activity: activity_test },
  { project: 'mobile-app-v2', issue_subject: 'Add widget support for iOS 16+ Lock Screen',
    user: 'grace.lee', hours: 6.0, comments: 'Implemented small and medium widget sizes.', activity: activity_dev },
  { project: 'mobile-app-v2', issue_subject: 'Push notifications not delivered when app is force-closed on iOS',
    user: 'grace.lee', hours: 2.5, comments: 'Diagnosed APNs payload issue, implemented fix.', activity: activity_dev },
  { project: 'infra-devops', issue_subject: 'Migrate CI/CD from Jenkins to GitHub Actions',
    user: 'carol.santos', hours: 12.0, comments: 'Phase 1 migration — unit test jobs.', activity: activity_dev },
  { project: 'infra-devops', issue_subject: 'Staging database running out of disk space weekly',
    user: 'david.kim', hours: 2.0, comments: 'Emergency cleanup and investigation.', activity: activity_dev },
]

time_entries_data.each do |te|
  project = created_projects[te[:project]]
  next unless project && te[:activity]
  user = User.find_by(login: te[:user]) || admin
  issue = Issue.find_by('project_id = ? AND subject LIKE ?', project.id, "%#{te[:issue_subject][0..40]}%")
  next unless issue
  TimeEntry.create!(
    project: project,
    issue: issue,
    user: user,
    hours: te[:hours],
    comments: te[:comments],
    activity: te[:activity],
    spent_on: Date.today - rand(1..14)
  )
  puts "  TimeEntry: #{te[:hours]}h on ##{issue.id}"
end

# ============================================================
# 9. Close versions that should appear as historical/completed
# ============================================================
[
  { project: 'phoenix-ecommerce', version_name: 'v0.9 Beta' },
  { project: 'mobile-app-v2',     version_name: 'v1.9 Legacy' },
].each do |vd|
  project = created_projects[vd[:project]]
  next unless project
  v = Version.find_by(project: project, name: vd[:version_name])
  if v
    v.update!(status: 'closed')
    puts "  Closed version: #{vd[:version_name]} in #{vd[:project]}"
  end
end

# ============================================================
# 10. Output seed result JSON for task scripts
# ============================================================
result = {
  projects: created_projects.map { |identifier, p| { identifier: identifier, id: p.id, name: p.name } },
  users: created_users.map { |login, u| { login: login, id: u[:user].id } },
  issues: created_issues,
  admin_api_key: admin.api_key
}

output_json = JSON.pretty_generate(result)
File.write('/tmp/redmine_seed_result.json', output_json)
puts ""
puts "=== Seed complete ==="
puts "Projects: #{created_projects.size}"
puts "Users: #{created_users.size}"
puts "Issues: #{created_issues.size}"
puts output_json
