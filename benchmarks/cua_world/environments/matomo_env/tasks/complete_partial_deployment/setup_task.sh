#!/bin/bash
# Setup script for Complete Partial Deployment task
# Seeds a partially-configured Matomo environment:
#   - GlobalRetail Corp site with WRONG currency/timezone/ecommerce settings
#   - 2 goals: Product Page View (correct), Add to Cart (wrong pattern)
#   - 1 custom dimension: Customer Tier (correct)
#   - NO segments, NO Tag Manager, NO users, NO dashboard
# The agent must audit, fix, and complete the deployment per the spec document.

echo "=== Setting up Complete Partial Deployment Task ==="
source /workspace/scripts/task_utils.sh

TARGET_SITE="GlobalRetail Corp"

# ── Wait for Matomo to be ready ──────────────────────────────────────────
echo "Waiting for Matomo..."
wait_for_matomo 60 || echo "WARNING: Matomo health check timed out, continuing..."

# ── Ensure critical database tables exist ────────────────────────────────
# The Matomo Docker image sometimes starts with an incomplete schema.
# We create the critical log tables + plugin tables if missing, then run
# core:update to bring everything else up to date.
echo "Checking database schema health..."
LOG_VISIT_EXISTS=$(matomo_query "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='matomo' AND TABLE_NAME='matomo_log_visit'" 2>/dev/null || echo "0")
if [ "$LOG_VISIT_EXISTS" = "0" ] || [ -z "$LOG_VISIT_EXISTS" ]; then
    echo "Critical tables missing — repairing database schema..."

    # Create the minimal set of log tables needed for core:update to succeed
    cat > /tmp/repair_matomo_schema.sql << 'REPAIRSQL'
CREATE TABLE IF NOT EXISTS matomo_log_action (
  idaction int(10) unsigned NOT NULL AUTO_INCREMENT,
  name varchar(4096) DEFAULT NULL, hash int(10) unsigned NOT NULL,
  type tinyint(3) unsigned DEFAULT NULL, url_prefix tinyint(2) DEFAULT NULL,
  PRIMARY KEY (idaction), KEY index_type_hash (type,hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_log_visit (
  idvisit bigint(10) unsigned NOT NULL AUTO_INCREMENT,
  idsite int(10) unsigned NOT NULL, idvisitor binary(8) NOT NULL,
  visit_last_action_time datetime NOT NULL, config_id binary(8) NOT NULL,
  location_ip varbinary(16) DEFAULT NULL, user_id varchar(200) DEFAULT NULL,
  visit_first_action_time datetime NOT NULL, visit_total_time int(11) unsigned NOT NULL DEFAULT 0,
  visitor_count_visits int(11) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (idvisit),
  KEY index_idsite_datetime (idsite,visit_last_action_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_log_link_visit_action (
  idlink_va bigint(10) unsigned NOT NULL AUTO_INCREMENT,
  idsite int(10) unsigned NOT NULL, idvisitor binary(8) NOT NULL,
  idvisit bigint(10) unsigned NOT NULL, server_time datetime NOT NULL,
  PRIMARY KEY (idlink_va), KEY index_idvisit (idvisit)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_log_conversion (
  idvisit bigint(10) unsigned NOT NULL, idsite int(10) unsigned NOT NULL,
  idvisitor binary(8) NOT NULL, server_time datetime NOT NULL,
  idgoal int(10) NOT NULL, buster int(10) unsigned NOT NULL,
  url varchar(4096) NOT NULL, visitor_count_visits int(11) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (idvisit,idgoal,buster)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_log_conversion_item (
  idsite int(10) unsigned NOT NULL, idvisitor binary(8) NOT NULL,
  server_time datetime NOT NULL, idvisit bigint(10) unsigned NOT NULL,
  idorder varchar(100) NOT NULL, idaction_sku int(10) unsigned NOT NULL,
  idaction_name int(10) unsigned NOT NULL, idaction_category int(10) unsigned NOT NULL,
  idaction_category2 int(10) unsigned NOT NULL, idaction_category3 int(10) unsigned NOT NULL,
  idaction_category4 int(10) unsigned NOT NULL, idaction_category5 int(10) unsigned NOT NULL,
  deleted tinyint(1) unsigned NOT NULL,
  PRIMARY KEY (idvisit,idorder,idaction_sku)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_log_profiling (
  query text NOT NULL, count int(10) unsigned DEFAULT NULL,
  sum_time_ms float DEFAULT NULL,
  idprofiling bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (idprofiling), UNIQUE KEY query (query(100))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_sequence (
  name varchar(120) NOT NULL, value bigint(20) unsigned NOT NULL,
  PRIMARY KEY (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_site_url (
  idurl int(10) unsigned NOT NULL AUTO_INCREMENT,
  idsite int(10) unsigned NOT NULL, url varchar(190) DEFAULT NULL,
  PRIMARY KEY (idurl), UNIQUE KEY unique_idsite_url (idsite, url)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_user_token_auth (
  idusertokenauth bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  login varchar(100) NOT NULL, description varchar(100) NOT NULL,
  password varchar(191) NOT NULL, hash_algo varchar(30) NOT NULL,
  system_token tinyint(1) NOT NULL DEFAULT 0,
  last_used datetime DEFAULT NULL, date_created datetime NOT NULL,
  date_expired datetime DEFAULT NULL, secure_only tinyint(2) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (idusertokenauth), UNIQUE KEY uniq_password (password)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_tagmanager_container (
  idcontainer varchar(8) NOT NULL, idsite int(10) unsigned NOT NULL,
  context varchar(10) NOT NULL, name varchar(50) NOT NULL,
  description varchar(1000) DEFAULT '', status varchar(10) NOT NULL DEFAULT 'active',
  created_date datetime NOT NULL, updated_date datetime NOT NULL,
  deleted_date datetime DEFAULT NULL,
  PRIMARY KEY (idcontainer, idsite)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_tagmanager_container_version (
  idcontainerversion bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  idcontainer varchar(8) NOT NULL, idsite int(10) unsigned NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'active', revision int(10) unsigned NOT NULL DEFAULT 0,
  name varchar(50) NOT NULL DEFAULT '', description varchar(1000) DEFAULT '',
  created_date datetime NOT NULL, updated_date datetime NOT NULL,
  deleted_date datetime DEFAULT NULL, release_date datetime DEFAULT NULL,
  release_login varchar(100) DEFAULT NULL, environments text DEFAULT NULL,
  PRIMARY KEY (idcontainerversion, idcontainer, idsite)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_tagmanager_tag (
  idtag bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  idcontainerversion bigint(20) unsigned NOT NULL,
  idsite int(10) unsigned NOT NULL, type varchar(50) NOT NULL,
  name varchar(50) NOT NULL, status varchar(10) NOT NULL DEFAULT 'active',
  parameters text DEFAULT NULL, fire_trigger_ids text DEFAULT NULL,
  block_trigger_ids text DEFAULT NULL, fire_limit varchar(20) NOT NULL DEFAULT 'unlimited',
  fire_delay int(10) unsigned NOT NULL DEFAULT 0, priority smallint(5) unsigned NOT NULL DEFAULT 999,
  created_date datetime NOT NULL, updated_date datetime NOT NULL,
  deleted_date datetime DEFAULT NULL,
  PRIMARY KEY (idtag, idcontainerversion, idsite)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_tagmanager_trigger (
  idtrigger bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  idcontainerversion bigint(20) unsigned NOT NULL,
  idsite int(10) unsigned NOT NULL, type varchar(50) NOT NULL,
  name varchar(50) NOT NULL, status varchar(10) NOT NULL DEFAULT 'active',
  parameters text DEFAULT NULL, conditions text DEFAULT NULL,
  created_date datetime NOT NULL, updated_date datetime NOT NULL,
  deleted_date datetime DEFAULT NULL,
  PRIMARY KEY (idtrigger, idcontainerversion, idsite)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_tagmanager_variable (
  idvariable bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  idcontainerversion bigint(20) unsigned NOT NULL,
  idsite int(10) unsigned NOT NULL, type varchar(50) NOT NULL,
  name varchar(50) NOT NULL, status varchar(10) NOT NULL DEFAULT 'active',
  default_value text DEFAULT NULL, parameters text DEFAULT NULL,
  created_date datetime NOT NULL, updated_date datetime NOT NULL,
  deleted_date datetime DEFAULT NULL,
  PRIMARY KEY (idvariable, idcontainerversion, idsite)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_archive_invalidations (
  idinvalidation bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  name varchar(255) NOT NULL, idsite int(10) unsigned NOT NULL,
  date1 date NOT NULL, date2 date NOT NULL,
  period tinyint(3) unsigned NOT NULL, status tinyint(1) unsigned DEFAULT 0,
  ts_invalidated datetime DEFAULT NULL,
  PRIMARY KEY (idinvalidation)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_annotations (
  idnote bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  idsite int(11) NOT NULL, date date DEFAULT NULL,
  title varchar(255) NOT NULL, starred tinyint(1) NOT NULL DEFAULT 0,
  user varchar(100) DEFAULT NULL,
  PRIMARY KEY (idnote)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS matomo_brute_force_log (
  id_brute_force_log bigint(11) NOT NULL AUTO_INCREMENT,
  ip_address varchar(60) DEFAULT NULL, attempted_at datetime NOT NULL,
  login varchar(100) DEFAULT NULL,
  PRIMARY KEY (id_brute_force_log)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
REPAIRSQL

    docker cp /tmp/repair_matomo_schema.sql matomo-db:/tmp/repair_matomo_schema.sql
    docker exec matomo-db bash -c 'mysql -u matomo -pmatomo123 matomo < /tmp/repair_matomo_schema.sql' 2>/dev/null

    # Run core:update to create any remaining tables and bring schema up to date
    docker exec matomo-app php /var/www/html/console core:update --yes 2>/dev/null || true

    # Clear caches after schema changes
    docker exec matomo-app php /var/www/html/console cache:clear 2>/dev/null || true

    TABLE_COUNT=$(matomo_query "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='matomo'" 2>/dev/null || echo "0")
    echo "Database repaired. Total tables: $TABLE_COUNT"
else
    echo "Database schema OK (matomo_log_visit exists)."
fi

# Always run core:update to ensure schema migrations are applied even when
# log_visit exists but other columns/tables are outdated from an earlier version.
NEEDS_UPDATE=$(curl -s "http://localhost/" 2>/dev/null | grep -c "CoreUpdater\|Update" || echo "0")
if [ "$NEEDS_UPDATE" -gt "0" ]; then
    echo "Matomo needs a database update — running core:update..."
    docker exec matomo-app php /var/www/html/console core:update --yes 2>/dev/null || true
    docker exec matomo-app php /var/www/html/console cache:clear 2>/dev/null || true
    echo "Update complete."
fi

# ── Ensure admin password is set correctly ────────────────────────────────
# Matomo stores passwords as bcrypt(md5(plaintext)).  The web installer
# sometimes produces a hash that doesn't match; reset it deterministically.
echo "Ensuring admin password is correct..."
docker exec matomo-app php -r "\$h=password_hash(md5('Admin12345'),PASSWORD_BCRYPT);\$p=new PDO('mysql:host=db;dbname=matomo','matomo','matomo123');\$p->exec(\"UPDATE matomo_user SET password='\$h' WHERE login='admin'\");" 2>/dev/null || true

# ── Ensure target site exists (with deliberately WRONG settings) ─────────
SITE_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_site WHERE LOWER(name)=LOWER('$TARGET_SITE')" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ] || [ -z "$SITE_COUNT" ]; then
    echo "Creating site '$TARGET_SITE' with wrong settings..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login)
                  VALUES ('$TARGET_SITE', 'https://globalretail.example.com', NOW(), 0, 0, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
    echo "Site created with USD/UTC/ecommerce=0 (all wrong)."
else
    echo "Site '$TARGET_SITE' already exists. Resetting to wrong settings..."
    matomo_query "UPDATE matomo_site SET currency='USD', timezone='UTC', ecommerce=0, excluded_parameters='' WHERE LOWER(name)=LOWER('$TARGET_SITE')" 2>/dev/null
fi

SITE_ID=$(matomo_query "SELECT idsite FROM matomo_site WHERE LOWER(name)=LOWER('$TARGET_SITE') LIMIT 1" 2>/dev/null)
echo "$SITE_ID" > /tmp/cpd_site_id
echo "GlobalRetail Corp site ID: $SITE_ID"

# ── Record Initial Site baseline (for anti-gaming check) ─────────────────
INITIAL_SITE_CURRENCY=$(matomo_query "SELECT currency FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "")
INITIAL_SITE_TIMEZONE=$(matomo_query "SELECT timezone FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "")
INITIAL_SITE_ECOMMERCE=$(matomo_query "SELECT ecommerce FROM matomo_site WHERE idsite=1" 2>/dev/null || echo "")
echo "${INITIAL_SITE_CURRENCY}|${INITIAL_SITE_TIMEZONE}|${INITIAL_SITE_ECOMMERCE}" > /tmp/cpd_initial_site1_state.txt

# ── Clean pre-existing task artifacts for this site ──────────────────────
echo "Cleaning pre-existing artifacts for site $SITE_ID..."

# Clean goals for this site
for GOAL_NAME in "Product Page View" "Add to Cart" "Checkout Started" "Purchase Complete"; do
    matomo_query "DELETE FROM matomo_goal WHERE LOWER(name)=LOWER('$GOAL_NAME') AND idsite=$SITE_ID" 2>/dev/null || true
done

# Clean segments that belong to this task
for SEG_NAME in "High-Value Customers" "Mobile Shoppers"; do
    matomo_query "DELETE FROM matomo_segment WHERE LOWER(name)=LOWER('$SEG_NAME') AND (enable_only_idsite=$SITE_ID OR enable_only_idsite=0)" 2>/dev/null || true
done

# Clean custom dimensions for this site
matomo_query "DELETE FROM matomo_custom_dimensions WHERE idsite=$SITE_ID" 2>/dev/null || true

# Clean Tag Manager data for this site
matomo_query "DELETE FROM matomo_tagmanager_tag WHERE idsite=$SITE_ID" 2>/dev/null || true
matomo_query "DELETE FROM matomo_tagmanager_trigger WHERE idsite=$SITE_ID" 2>/dev/null || true
matomo_query "DELETE FROM matomo_tagmanager_container_version WHERE idsite=$SITE_ID" 2>/dev/null || true
matomo_query "DELETE FROM matomo_tagmanager_container WHERE idsite=$SITE_ID" 2>/dev/null || true

# Clean users created for this task
for USER_LOGIN in "marketing_lead" "data_analyst"; do
    matomo_query "DELETE FROM matomo_access WHERE login='$USER_LOGIN'" 2>/dev/null || true
    matomo_query "DELETE FROM matomo_user_token_auth WHERE login='$USER_LOGIN'" 2>/dev/null || true
    matomo_query "DELETE FROM matomo_user WHERE login='$USER_LOGIN'" 2>/dev/null || true
done

# Clean dashboards created for this task
matomo_query "DELETE FROM matomo_user_dashboard WHERE LOWER(name)=LOWER('Client Overview')" 2>/dev/null || true
matomo_query "DELETE FROM matomo_user_dashboard WHERE LOWER(name)=LOWER('Analytics Dashboard')" 2>/dev/null || true

echo "Artifacts cleaned."

# ── Seed 2 conversion goals (1 correct, 1 with wrong pattern) ───────────
echo "Seeding conversion goals..."

# Goal 1: Product Page View (CORRECT — agent should leave as-is)
matomo_query "INSERT INTO matomo_goal (idsite, idgoal, name, match_attribute, pattern, pattern_type, case_sensitive, allow_multiple, revenue, deleted)
              VALUES ($SITE_ID, 1, 'Product Page View', 'url', '/products/', 'contains', 0, 0, 0, 0)" 2>/dev/null

# Goal 2: Add to Cart (WRONG pattern: /cart instead of /cart/add)
matomo_query "INSERT INTO matomo_goal (idsite, idgoal, name, match_attribute, pattern, pattern_type, case_sensitive, allow_multiple, revenue, deleted)
              VALUES ($SITE_ID, 2, 'Add to Cart', 'url', '/cart', 'contains', 0, 0, 0, 0)" 2>/dev/null

echo "Goals seeded: Product Page View (correct), Add to Cart (wrong pattern /cart)."

# ── Seed 1 correct custom dimension ─────────────────────────────────────
echo "Seeding custom dimension..."

matomo_query "INSERT INTO matomo_custom_dimensions (idcustomdimension, idsite, name, \`index\`, scope, active, case_sensitive)
              VALUES (1, $SITE_ID, 'Customer Tier', 1, 'visit', 1, 1)" 2>/dev/null

echo "Custom dimension 'Customer Tier' (visit scope, active) seeded."

# ── Copy deployment spec to agent-accessible location ────────────────────
echo "Placing deployment specification..."
mkdir -p /home/ga/Documents
cp /workspace/tasks/complete_partial_deployment/deployment_spec.txt /home/ga/Documents/deployment_spec.txt
chown ga:ga /home/ga/Documents/deployment_spec.txt
chmod 644 /home/ga/Documents/deployment_spec.txt
echo "Spec placed at /home/ga/Documents/deployment_spec.txt"

# ── Delete stale outputs ─────────────────────────────────────────────────
rm -f /tmp/complete_partial_deployment_result.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# ── Record baseline state ────────────────────────────────────────────────
echo "Recording baseline state..."

# Baseline: goal IDs and count
matomo_query "SELECT idgoal FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0 ORDER BY idgoal" 2>/dev/null | tr '\n' ',' | sed 's/,$//' > /tmp/cpd_initial_goal_ids.txt
INITIAL_GOAL_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_goal WHERE idsite=$SITE_ID AND deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_GOAL_COUNT" > /tmp/cpd_initial_goal_count.txt
echo "Initial goal IDs: $(cat /tmp/cpd_initial_goal_ids.txt), count: $INITIAL_GOAL_COUNT"

# Baseline: segment count
INITIAL_SEG_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_segment WHERE deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_SEG_COUNT" > /tmp/cpd_initial_segment_count.txt
echo "Initial segment count: $INITIAL_SEG_COUNT"

# Baseline: custom dimension count
INITIAL_DIM_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_custom_dimensions WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
echo "$INITIAL_DIM_COUNT" > /tmp/cpd_initial_dim_count.txt
echo "Initial dimension count: $INITIAL_DIM_COUNT"

# Baseline: user count (excluding admin and anonymous)
INITIAL_USER_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_user WHERE login NOT IN ('admin','anonymous')" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/cpd_initial_user_count.txt
echo "Initial non-system user count: $INITIAL_USER_COUNT"

# Baseline: TM container count for this site
INITIAL_TM_COUNT=$(matomo_query "SELECT COUNT(*) FROM matomo_tagmanager_container WHERE idsite=$SITE_ID AND deleted_date IS NULL" 2>/dev/null || echo "0")
echo "$INITIAL_TM_COUNT" > /tmp/cpd_initial_tm_count.txt
echo "Initial TM container count: $INITIAL_TM_COUNT"

# ── Task start timestamp ─────────────────────────────────────────────────
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# ── Launch Firefox ───────────────────────────────────────────────────────
pkill -f firefox 2>/dev/null || true
sleep 2

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox 'http://localhost/index.php?module=CoreHome&action=index&idSite=$SITE_ID&period=day&date=today' > /tmp/firefox_task.log 2>&1 &"
sleep 5

if ! wait_for_window "firefox\|mozilla\|Matomo" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Complete Partial Deployment Task Setup Complete ==="
echo ""
echo "TASK: Read /home/ga/Documents/deployment_spec.txt and complete the analytics setup."
echo "  - Fix site settings (currency, timezone, ecommerce, URL params)"
echo "  - Fix 'Add to Cart' goal pattern and create 2 missing goals"
echo "  - Create missing custom dimension 'Page Category'"
echo "  - Create 2 audience segments"
echo "  - Set up Tag Manager container with tags and triggers, publish"
echo "  - Create 2 user accounts with appropriate access"
echo "  - Create 'Client Overview' dashboard with 4 widgets"
echo ""
echo "Login credentials: admin / Admin12345"
echo "Target site: GlobalRetail Corp (ID: $SITE_ID)"
echo ""
