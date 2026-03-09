#!/bin/bash
set -e

echo "=== Setting up Snipe-IT ==="

# Wait for desktop to be ready
sleep 5

# ---------------------------------------------------------------
# 1. Prepare Snipe-IT directory and configuration
# ---------------------------------------------------------------
echo "--- Preparing Snipe-IT configuration ---"
mkdir -p /home/ga/snipeit
cp /workspace/config/docker-compose.yml /home/ga/snipeit/
cp /workspace/config/snipeit.env /home/ga/snipeit/.env
chown -R ga:ga /home/ga/snipeit

# ---------------------------------------------------------------
# 2. Start Docker containers
# ---------------------------------------------------------------
echo "--- Starting Docker containers ---"
cd /home/ga/snipeit
docker compose pull
docker compose up -d

# Wait for MariaDB to be ready
echo "--- Waiting for MariaDB ---"
wait_for_mysql() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec snipeit-db mysqladmin ping -h localhost -u root -proot_pass 2>/dev/null | grep -q "alive"; then
            echo "MariaDB is ready (${elapsed}s)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "MariaDB timeout after ${timeout}s"
    return 1
}
wait_for_mysql

# ---------------------------------------------------------------
# 3. Generate APP_KEY and configure
# ---------------------------------------------------------------
echo "--- Generating APP_KEY ---"
APP_KEY=$(docker compose run --rm snipeit-app php artisan key:generate --show 2>/dev/null | tr -d '[:space:]')
echo "Generated APP_KEY: $APP_KEY"

# Update .env with APP_KEY
sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" /home/ga/snipeit/.env

# Restart app container to pick up the new key
docker compose down
docker compose up -d

# Wait for MariaDB again after restart
wait_for_mysql

# ---------------------------------------------------------------
# 4. Wait for Snipe-IT to be ready
# ---------------------------------------------------------------
echo "--- Waiting for Snipe-IT application ---"
wait_for_snipeit() {
    local timeout=180
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "Snipe-IT is ready (HTTP $HTTP_CODE) (${elapsed}s)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... (${elapsed}s, HTTP $HTTP_CODE)"
    done
    echo "Snipe-IT timeout after ${timeout}s"
    return 1
}
wait_for_snipeit

# ---------------------------------------------------------------
# 5. Run database migrations
# ---------------------------------------------------------------
echo "--- Running database migrations ---"
docker exec snipeit-app php artisan migrate --force 2>&1 || true
sleep 3

# ---------------------------------------------------------------
# 6. Insert settings row to bypass setup wizard
# ---------------------------------------------------------------
echo "--- Bypassing setup wizard ---"
docker exec snipeit-db mysql -u root -proot_pass snipeit -e "
INSERT INTO settings (id, created_at, updated_at, site_name, auto_increment_assets, auto_increment_prefix, per_page)
VALUES (1, NOW(), NOW(), 'Snipe-IT Asset Management', 1, 'ASSET-', 20)
ON DUPLICATE KEY UPDATE site_name='Snipe-IT Asset Management';
" 2>/dev/null || true

# ---------------------------------------------------------------
# 7. Create admin user via artisan
# ---------------------------------------------------------------
echo "--- Creating admin user ---"
docker exec snipeit-app php artisan snipeit:create-admin \
    --first_name="Admin" \
    --last_name="User" \
    --email="admin@example.com" \
    --username="admin" \
    --password="password" 2>&1 || echo "Admin user may already exist"

sleep 3

# ---------------------------------------------------------------
# 8. Install Passport and generate OAuth keys
# ---------------------------------------------------------------
echo "--- Setting up Laravel Passport ---"
docker exec snipeit-app php artisan passport:install --force 2>&1 || true
docker exec snipeit-app php artisan passport:keys --force 2>&1 || true

# Generate OAuth keys with openssl directly (passport:keys may not
# write to the correct symlink target in the snipe-it container).
# NOTE: In the snipe-it container, Apache runs as user "docker" (not www-data).
# The storage/oauth-*.key files are symlinks to /var/lib/snipeit/keys/.
# Keys must be readable by the "docker" user (chmod 660 or 644).
echo "  Generating OAuth keys with openssl..."
docker exec snipeit-app bash -c '
    # Write keys to the symlink target directory
    openssl genrsa -out /var/lib/snipeit/keys/oauth-private.key 4096 2>/dev/null
    openssl rsa -in /var/lib/snipeit/keys/oauth-private.key -pubout -out /var/lib/snipeit/keys/oauth-public.key 2>/dev/null
    # Apache runs as "docker" user (uid=10000, gid=50/staff) in snipe-it container
    chmod 644 /var/lib/snipeit/keys/oauth-private.key /var/lib/snipeit/keys/oauth-public.key
    chown 10000:50 /var/lib/snipeit/keys/oauth-private.key /var/lib/snipeit/keys/oauth-public.key
'
echo "  OAuth keys generated."

# ---------------------------------------------------------------
# 9. Generate API token via PHP script
# ---------------------------------------------------------------
echo "--- Generating API token ---"

# Write PHP script to generate a personal access token
cat > /tmp/gen_token.php << 'PHPEOF'
<?php
require '/var/www/html/vendor/autoload.php';
$app = require_once '/var/www/html/bootstrap/app.php';
$app->make('Illuminate\Contracts\Console\Kernel')->bootstrap();

$user = App\Models\User::where('username', 'admin')->first();
if (!$user) {
    fwrite(STDERR, "Admin user not found\n");
    exit(1);
}
$token = $user->createToken('seed-token');
echo $token->accessToken;
PHPEOF

docker cp /tmp/gen_token.php snipeit-app:/tmp/gen_token.php
API_TOKEN=$(docker exec -w /var/www/html snipeit-app php /tmp/gen_token.php 2>/dev/null)

if [ -z "$API_TOKEN" ]; then
    echo "  WARNING: Failed to generate API token via PHP script"
    echo "  Trying artisan tinker fallback..."
    docker exec snipeit-app php artisan tinker --execute="
        \$user = App\Models\User::where('username', 'admin')->first();
        if (\$user) { \$t = \$user->createToken('seed-token'); echo \$t->accessToken; }
    " 2>/dev/null > /tmp/api_token_tinker.txt || true
    API_TOKEN=$(cat /tmp/api_token_tinker.txt 2>/dev/null | tail -1)
fi

if [ -z "$API_TOKEN" ]; then
    echo "  CRITICAL: Could not generate API token. Data seeding will fail."
else
    echo "  API token generated: ${API_TOKEN:0:20}..."
fi

# Save token for later use
echo "$API_TOKEN" > /home/ga/snipeit/api_token.txt
chown ga:ga /home/ga/snipeit/api_token.txt

# Verify the API is working
echo "--- Verifying API access ---"
API_TEST=$(curl -s -X GET "http://localhost:8000/api/v1/statuslabels" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${API_TOKEN}" 2>/dev/null)
echo "  API test response: ${API_TEST:0:100}"

if echo "$API_TEST" | grep -q '"total"'; then
    echo "  API is working!"
else
    echo "  WARNING: API may not be working correctly. Proceeding anyway..."
fi

# ---------------------------------------------------------------
# 10. Seed realistic data via API
# ---------------------------------------------------------------
echo "--- Seeding realistic data ---"
SNIPEIT_URL="http://localhost:8000"

# Helper function for API calls
snipeit_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    curl -s -X "$method" \
        "${SNIPEIT_URL}/api/v1/${endpoint}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -d "$data" 2>/dev/null
}

# Helper to extract ID from API response
get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

# --- Status Labels ---
echo "  Creating status labels..."
SL_DEPLOYED=$(get_id "$(snipeit_api POST "statuslabels" '{"name":"Deployed","type":"deployable","color":"#2196F3","show_in_nav":true}')")
SL_REPAIR=$(get_id "$(snipeit_api POST "statuslabels" '{"name":"Out for Repair","type":"undeployable","color":"#FF9800","show_in_nav":true}')")
SL_RETIRED=$(get_id "$(snipeit_api POST "statuslabels" '{"name":"Retired","type":"archived","color":"#9E9E9E","show_in_nav":true}')")
SL_LOST=$(get_id "$(snipeit_api POST "statuslabels" '{"name":"Lost/Stolen","type":"archived","color":"#F44336","show_in_nav":true}')")
# Also look up built-in status labels
SL_READY=$(snipeit_api GET "statuslabels" "" | jq -r '.rows[] | select(.name=="Ready to Deploy") | .id')
SL_PENDING=$(snipeit_api GET "statuslabels" "" | jq -r '.rows[] | select(.name=="Pending") | .id')
echo "  Status IDs: deployed=$SL_DEPLOYED ready=$SL_READY repair=$SL_REPAIR retired=$SL_RETIRED pending=$SL_PENDING"

# --- Categories ---
echo "  Creating categories..."
CAT_LAPTOPS=$(get_id "$(snipeit_api POST "categories" '{"name":"Laptops","category_type":"asset","eol":48}')")
CAT_DESKTOPS=$(get_id "$(snipeit_api POST "categories" '{"name":"Desktops","category_type":"asset","eol":60}')")
CAT_MONITORS=$(get_id "$(snipeit_api POST "categories" '{"name":"Monitors","category_type":"asset","eol":72}')")
CAT_PRINTERS=$(get_id "$(snipeit_api POST "categories" '{"name":"Printers","category_type":"asset","eol":60}')")
CAT_PHONES=$(get_id "$(snipeit_api POST "categories" '{"name":"Phones","category_type":"asset","eol":36}')")
CAT_NETWORK=$(get_id "$(snipeit_api POST "categories" '{"name":"Networking","category_type":"asset","eol":60}')")
CAT_SERVERS=$(get_id "$(snipeit_api POST "categories" '{"name":"Servers","category_type":"asset","eol":60}')")
CAT_TABLETS=$(get_id "$(snipeit_api POST "categories" '{"name":"Tablets","category_type":"asset","eol":36}')")
CAT_OS=$(get_id "$(snipeit_api POST "categories" '{"name":"Operating Systems","category_type":"license"}')")
CAT_PRODSW=$(get_id "$(snipeit_api POST "categories" '{"name":"Productivity Software","category_type":"license"}')")
CAT_INPUT=$(get_id "$(snipeit_api POST "categories" '{"name":"Input Devices","category_type":"accessory"}')")
CAT_CABLES=$(get_id "$(snipeit_api POST "categories" '{"name":"Cables and Adapters","category_type":"accessory"}')")
CAT_PRINTSUP=$(get_id "$(snipeit_api POST "categories" '{"name":"Printer Supplies","category_type":"consumable"}')")
CAT_MEMORY=$(get_id "$(snipeit_api POST "categories" '{"name":"Memory","category_type":"component"}')")
CAT_STORAGE=$(get_id "$(snipeit_api POST "categories" '{"name":"Storage","category_type":"component"}')")
echo "  Category IDs: laptops=$CAT_LAPTOPS desktops=$CAT_DESKTOPS monitors=$CAT_MONITORS network=$CAT_NETWORK servers=$CAT_SERVERS"

# --- Manufacturers ---
echo "  Creating manufacturers..."
MFR_DELL=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Dell","url":"https://www.dell.com","support_url":"https://www.dell.com/support","support_phone":"1-800-624-9896","support_email":"support@dell.com"}')")
MFR_HP=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"HP","url":"https://www.hp.com","support_url":"https://support.hp.com","support_phone":"1-800-474-6836","support_email":"support@hp.com"}')")
MFR_LENOVO=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Lenovo","url":"https://www.lenovo.com","support_url":"https://support.lenovo.com","support_phone":"1-855-253-6686","support_email":"support@lenovo.com"}')")
MFR_APPLE=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Apple","url":"https://www.apple.com","support_url":"https://support.apple.com","support_phone":"1-800-275-2273","support_email":"support@apple.com"}')")
MFR_CISCO=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Cisco","url":"https://www.cisco.com","support_url":"https://www.cisco.com/c/en/us/support","support_phone":"1-800-553-2447","support_email":"tac@cisco.com"}')")
MFR_SAMSUNG=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Samsung","url":"https://www.samsung.com","support_url":"https://www.samsung.com/us/support/","support_phone":"1-800-726-7864","support_email":"support@samsung.com"}')")
MFR_MSFT=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Microsoft","url":"https://www.microsoft.com","support_url":"https://support.microsoft.com","support_phone":"1-800-642-7676","support_email":"support@microsoft.com"}')")
MFR_LOGI=$(get_id "$(snipeit_api POST "manufacturers" '{"name":"Logitech","url":"https://www.logitech.com","support_url":"https://support.logitech.com","support_phone":"1-646-454-3200","support_email":"support@logitech.com"}')")
echo "  Manufacturer IDs: dell=$MFR_DELL hp=$MFR_HP lenovo=$MFR_LENOVO apple=$MFR_APPLE cisco=$MFR_CISCO"

# --- Locations ---
echo "  Creating locations..."
LOC_HQA=$(get_id "$(snipeit_api POST "locations" '{"name":"Headquarters - Building A","address":"100 Technology Drive","address2":"Suite 500","city":"San Francisco","state":"CA","zip":"94105","country":"US"}')")
LOC_HQB=$(get_id "$(snipeit_api POST "locations" '{"name":"Headquarters - Building B","address":"110 Technology Drive","city":"San Francisco","state":"CA","zip":"94105","country":"US"}')")
LOC_NYC=$(get_id "$(snipeit_api POST "locations" '{"name":"New York Office","address":"350 Fifth Avenue","address2":"Floor 34","city":"New York","state":"NY","zip":"10118","country":"US"}')")
LOC_AUSTIN=$(get_id "$(snipeit_api POST "locations" '{"name":"Austin Data Center","address":"2001 Robert Dedman Drive","city":"Austin","state":"TX","zip":"78712","country":"US"}')")
LOC_LONDON=$(get_id "$(snipeit_api POST "locations" '{"name":"London Office","address":"30 St Mary Axe","city":"London","zip":"EC3A 8BF","country":"GB"}')")
LOC_REMOTE=$(get_id "$(snipeit_api POST "locations" '{"name":"Remote Workers","address":"Various","city":"Various","country":"US"}')")

# --- Departments ---
echo "  Creating departments..."
snipeit_api POST "departments" "{\"name\":\"Information Technology\",\"company_id\":null,\"location_id\":$LOC_HQA}"
snipeit_api POST "departments" "{\"name\":\"Engineering\",\"company_id\":null,\"location_id\":$LOC_HQA}"
snipeit_api POST "departments" "{\"name\":\"Human Resources\",\"company_id\":null,\"location_id\":$LOC_HQA}"
snipeit_api POST "departments" "{\"name\":\"Finance\",\"company_id\":null,\"location_id\":$LOC_HQB}"
snipeit_api POST "departments" "{\"name\":\"Marketing\",\"company_id\":null,\"location_id\":$LOC_NYC}"
snipeit_api POST "departments" "{\"name\":\"Sales\",\"company_id\":null,\"location_id\":$LOC_NYC}"
snipeit_api POST "departments" "{\"name\":\"Operations\",\"company_id\":null,\"location_id\":$LOC_AUSTIN}"

# --- Suppliers ---
echo "  Creating suppliers..."
SUP_CDW=$(get_id "$(snipeit_api POST "suppliers" '{"name":"CDW Corporation","address":"200 N. Milwaukee Ave","city":"Vernon Hills","state":"IL","zip":"60061","country":"US","phone":"1-800-800-4239","email":"orders@cdw.com","url":"https://www.cdw.com","notes":"Primary hardware supplier"}')")
SUP_INSIGHT=$(get_id "$(snipeit_api POST "suppliers" '{"name":"Insight Direct","address":"6820 S. Harl Ave","city":"Tempe","state":"AZ","zip":"85283","country":"US","phone":"1-800-467-4448","email":"sales@insight.com","url":"https://www.insight.com","notes":"Enterprise licensing partner"}')")
SUP_SHI=$(get_id "$(snipeit_api POST "suppliers" '{"name":"SHI International","address":"290 Davidson Avenue","city":"Somerset","state":"NJ","zip":"08873","country":"US","phone":"1-888-764-8888","email":"sales@shi.com","url":"https://www.shi.com","notes":"Software licensing"}')")

# --- Asset Models ---
echo "  Creating asset models..."
# Laptops
MDL_LAT5540=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Dell Latitude 5540\",\"category_id\":$CAT_LAPTOPS,\"manufacturer_id\":$MFR_DELL,\"model_number\":\"LAT-5540\",\"eol\":48,\"notes\":\"Standard business laptop\"}")")
MDL_LAT7440=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Dell Latitude 7440\",\"category_id\":$CAT_LAPTOPS,\"manufacturer_id\":$MFR_DELL,\"model_number\":\"LAT-7440\",\"eol\":48,\"notes\":\"Premium business ultrabook\"}")")
MDL_EB840=$(get_id "$(snipeit_api POST "models" "{\"name\":\"HP EliteBook 840 G10\",\"category_id\":$CAT_LAPTOPS,\"manufacturer_id\":$MFR_HP,\"model_number\":\"EB-840-G10\",\"eol\":48,\"notes\":\"Enterprise laptop\"}")")
MDL_T14S=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Lenovo ThinkPad T14s Gen 4\",\"category_id\":$CAT_LAPTOPS,\"manufacturer_id\":$MFR_LENOVO,\"model_number\":\"TP-T14S-G4\",\"eol\":48,\"notes\":\"Thin and light business laptop\"}")")
MDL_MBP16=$(get_id "$(snipeit_api POST "models" "{\"name\":\"MacBook Pro 16-inch M3 Pro\",\"category_id\":$CAT_LAPTOPS,\"manufacturer_id\":$MFR_APPLE,\"model_number\":\"MBP-16-M3P\",\"eol\":48,\"notes\":\"Creative and development workstation\"}")")
# Desktops
MDL_OPT7010=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Dell OptiPlex 7010\",\"category_id\":$CAT_DESKTOPS,\"manufacturer_id\":$MFR_DELL,\"model_number\":\"OPT-7010\",\"eol\":60,\"notes\":\"Standard desktop\"}")")
MDL_ED800=$(get_id "$(snipeit_api POST "models" "{\"name\":\"HP EliteDesk 800 G9\",\"category_id\":$CAT_DESKTOPS,\"manufacturer_id\":$MFR_HP,\"model_number\":\"ED-800-G9\",\"eol\":60,\"notes\":\"Enterprise desktop\"}")")
# Monitors
MDL_U2723=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Dell U2723QE 27in 4K\",\"category_id\":$CAT_MONITORS,\"manufacturer_id\":$MFR_DELL,\"model_number\":\"U2723QE\",\"eol\":72,\"notes\":\"27-inch 4K USB-C monitor\"}")")
MDL_OG5=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Samsung Odyssey G5 34in\",\"category_id\":$CAT_MONITORS,\"manufacturer_id\":$MFR_SAMSUNG,\"model_number\":\"S34C50\",\"eol\":72,\"notes\":\"34-inch ultrawide monitor\"}")")
# Networking
MDL_C9200=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Cisco Catalyst 9200L\",\"category_id\":$CAT_NETWORK,\"manufacturer_id\":$MFR_CISCO,\"model_number\":\"C9200L-24P\",\"eol\":84,\"notes\":\"24-port PoE+ switch\"}")")
# Servers
MDL_R750=$(get_id "$(snipeit_api POST "models" "{\"name\":\"Dell PowerEdge R750\",\"category_id\":$CAT_SERVERS,\"manufacturer_id\":$MFR_DELL,\"model_number\":\"PE-R750\",\"eol\":60,\"notes\":\"2U rack server\"}")")
echo "  Model IDs: lat5540=$MDL_LAT5540 lat7440=$MDL_LAT7440 eb840=$MDL_EB840 t14s=$MDL_T14S mbp16=$MDL_MBP16"

# --- Users (employees) ---
echo "  Creating users..."
USR_SCHEN=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"Sarah\",\"last_name\":\"Chen\",\"username\":\"schen\",\"email\":\"sarah.chen@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":1,\"location_id\":$LOC_HQA,\"jobtitle\":\"IT Director\",\"phone\":\"415-555-0101\",\"notes\":\"Head of IT department\"}")")
USR_JROD=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"James\",\"last_name\":\"Rodriguez\",\"username\":\"jrodriguez\",\"email\":\"james.rodriguez@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":2,\"location_id\":$LOC_HQA,\"jobtitle\":\"Senior Software Engineer\",\"phone\":\"415-555-0102\",\"notes\":\"Backend team lead\"}")")
USR_EWAT=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"Emily\",\"last_name\":\"Watson\",\"username\":\"ewatson\",\"email\":\"emily.watson@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":3,\"location_id\":$LOC_HQA,\"jobtitle\":\"HR Manager\",\"phone\":\"415-555-0103\",\"notes\":\"Handles employee onboarding\"}")")
USR_MTHO=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"Michael\",\"last_name\":\"Thompson\",\"username\":\"mthompson\",\"email\":\"michael.thompson@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":4,\"location_id\":$LOC_HQB,\"jobtitle\":\"Financial Analyst\",\"phone\":\"415-555-0104\",\"notes\":\"Budget and procurement\"}")")
USR_PPAT=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"Priya\",\"last_name\":\"Patel\",\"username\":\"ppatel\",\"email\":\"priya.patel@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":5,\"location_id\":$LOC_NYC,\"jobtitle\":\"Marketing Director\",\"phone\":\"212-555-0201\",\"notes\":\"NYC marketing team lead\"}")")
USR_DKIM=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"David\",\"last_name\":\"Kim\",\"username\":\"dkim\",\"email\":\"david.kim@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":2,\"location_id\":$LOC_HQA,\"jobtitle\":\"DevOps Engineer\",\"phone\":\"415-555-0106\",\"notes\":\"Infrastructure and CI/CD\"}")")
USR_LNGU=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"Lisa\",\"last_name\":\"Nguyen\",\"username\":\"lnguyen\",\"email\":\"lisa.nguyen@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":6,\"location_id\":$LOC_NYC,\"jobtitle\":\"Sales Representative\",\"phone\":\"212-555-0202\",\"notes\":\"Enterprise accounts\"}")")
USR_RMAR=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"Robert\",\"last_name\":\"Martinez\",\"username\":\"rmartinez\",\"email\":\"robert.martinez@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":7,\"location_id\":$LOC_AUSTIN,\"jobtitle\":\"Data Center Manager\",\"phone\":\"512-555-0301\",\"notes\":\"Austin DC operations\"}")")
USR_AKOW=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"Anna\",\"last_name\":\"Kowalski\",\"username\":\"akowalski\",\"email\":\"anna.kowalski@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":2,\"location_id\":$LOC_LONDON,\"jobtitle\":\"Frontend Developer\",\"phone\":\"44-20-7946-0958\",\"notes\":\"London office, React specialist\"}")")
USR_MJOH=$(get_id "$(snipeit_api POST "users" "{\"first_name\":\"Marcus\",\"last_name\":\"Johnson\",\"username\":\"mjohnson\",\"email\":\"marcus.johnson@example.com\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\",\"activated\":true,\"department_id\":1,\"location_id\":$LOC_REMOTE,\"jobtitle\":\"IT Support Specialist\",\"phone\":\"415-555-0110\",\"notes\":\"Remote support, VPN expert\"}")")
echo "  User IDs: schen=$USR_SCHEN mthompson=$USR_MTHO dkim=$USR_DKIM akowalski=$USR_AKOW"

# --- Hardware Assets ---
echo "  Creating hardware assets..."
# Laptops - Dell Latitude 5540
HW_L001=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L001\",\"name\":\"Dell Latitude 5540 - Sarah Chen\",\"model_id\":$MDL_LAT5540,\"status_id\":$SL_DEPLOYED,\"serial\":\"DL5540-SN-7829\",\"purchase_date\":\"2024-01-15\",\"purchase_cost\":1299.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Assigned to IT Director\"}")")
HW_L002=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L002\",\"name\":\"Dell Latitude 5540 - Finance Pool\",\"model_id\":$MDL_LAT5540,\"status_id\":$SL_READY,\"serial\":\"DL5540-SN-7830\",\"purchase_date\":\"2024-01-15\",\"purchase_cost\":1299.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQB,\"notes\":\"Available for assignment\"}")")
HW_L003=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L003\",\"name\":\"Dell Latitude 5540 - Repair\",\"model_id\":$MDL_LAT5540,\"status_id\":$SL_REPAIR,\"serial\":\"DL5540-SN-7831\",\"purchase_date\":\"2023-06-20\",\"purchase_cost\":1249.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Screen replacement pending\"}")")

# Laptops - Dell Latitude 7440
HW_L004=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L004\",\"name\":\"Dell Latitude 7440 - James Rodriguez\",\"model_id\":$MDL_LAT7440,\"status_id\":$SL_DEPLOYED,\"serial\":\"DL7440-SN-4521\",\"purchase_date\":\"2024-03-01\",\"purchase_cost\":1649.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Senior engineering laptop\"}")")

# HP EliteBook
HW_L005=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L005\",\"name\":\"HP EliteBook 840 - Emily Watson\",\"model_id\":$MDL_EB840,\"status_id\":$SL_DEPLOYED,\"serial\":\"HP840G10-SN-1122\",\"purchase_date\":\"2024-02-10\",\"purchase_cost\":1399.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"HR department\"}")")
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L006\",\"name\":\"HP EliteBook 840 - Spare\",\"model_id\":$MDL_EB840,\"status_id\":$SL_READY,\"serial\":\"HP840G10-SN-1123\",\"purchase_date\":\"2024-02-10\",\"purchase_cost\":1399.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Spare unit for emergencies\"}"

# Lenovo ThinkPad
HW_L007=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L007\",\"name\":\"Lenovo ThinkPad T14s - David Kim\",\"model_id\":$MDL_T14S,\"status_id\":$SL_DEPLOYED,\"serial\":\"LEN-T14S-G4-8834\",\"purchase_date\":\"2024-04-15\",\"purchase_cost\":1549.99,\"warranty_months\":36,\"supplier_id\":$SUP_INSIGHT,\"rtd_location_id\":$LOC_HQA,\"notes\":\"DevOps workstation\"}")")

# MacBook Pro
HW_L008=$(get_id "$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L008\",\"name\":\"MacBook Pro 16 M3 - Anna Kowalski\",\"model_id\":$MDL_MBP16,\"status_id\":$SL_DEPLOYED,\"serial\":\"MBP16-M3P-FVFXL\",\"purchase_date\":\"2024-05-01\",\"purchase_cost\":2499.99,\"warranty_months\":12,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_LONDON,\"notes\":\"London office, frontend development\"}")")
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L009\",\"name\":\"MacBook Pro 16 M3 - New Hire Pool\",\"model_id\":$MDL_MBP16,\"status_id\":$SL_READY,\"serial\":\"MBP16-M3P-FVFXM\",\"purchase_date\":\"2024-07-10\",\"purchase_cost\":2499.99,\"warranty_months\":12,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Reserved for new developer hires\"}"

# Desktops
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-D001\",\"name\":\"Dell OptiPlex 7010 - Reception\",\"model_id\":$MDL_OPT7010,\"status_id\":$SL_DEPLOYED,\"serial\":\"DOPT7010-SN-3301\",\"purchase_date\":\"2023-09-01\",\"purchase_cost\":899.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Front desk workstation\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-D002\",\"name\":\"Dell OptiPlex 7010 - Conference Room A\",\"model_id\":$MDL_OPT7010,\"status_id\":$SL_DEPLOYED,\"serial\":\"DOPT7010-SN-3302\",\"purchase_date\":\"2023-09-01\",\"purchase_cost\":899.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Conference room shared station\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-D003\",\"name\":\"HP EliteDesk 800 - Lab Workstation\",\"model_id\":$MDL_ED800,\"status_id\":$SL_DEPLOYED,\"serial\":\"HPED800-SN-5501\",\"purchase_date\":\"2024-01-20\",\"purchase_cost\":1099.99,\"warranty_months\":36,\"supplier_id\":$SUP_INSIGHT,\"rtd_location_id\":$LOC_AUSTIN,\"notes\":\"Austin data center lab\"}"

# Monitors
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-M001\",\"name\":\"Dell U2723QE Monitor - IT Office\",\"model_id\":$MDL_U2723,\"status_id\":$SL_DEPLOYED,\"serial\":\"DMON-U27-7701\",\"purchase_date\":\"2024-01-15\",\"purchase_cost\":549.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"USB-C monitor\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-M002\",\"name\":\"Dell U2723QE Monitor - Spare\",\"model_id\":$MDL_U2723,\"status_id\":$SL_READY,\"serial\":\"DMON-U27-7702\",\"purchase_date\":\"2024-06-01\",\"purchase_cost\":549.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQB,\"notes\":\"Available for assignment\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-M003\",\"name\":\"Samsung Odyssey G5 - Engineering\",\"model_id\":$MDL_OG5,\"status_id\":$SL_DEPLOYED,\"serial\":\"SAM-OG5-9901\",\"purchase_date\":\"2024-03-01\",\"purchase_cost\":449.99,\"warranty_months\":24,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"Ultrawide for development\"}"

# Networking
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-N001\",\"name\":\"Cisco Catalyst 9200L - Floor 3\",\"model_id\":$MDL_C9200,\"status_id\":$SL_DEPLOYED,\"serial\":\"CISCO-C9200-AA01\",\"purchase_date\":\"2023-11-15\",\"purchase_cost\":3299.99,\"warranty_months\":60,\"supplier_id\":$SUP_INSIGHT,\"rtd_location_id\":$LOC_HQA,\"notes\":\"3rd floor main switch\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-N002\",\"name\":\"Cisco Catalyst 9200L - DC Core\",\"model_id\":$MDL_C9200,\"status_id\":$SL_DEPLOYED,\"serial\":\"CISCO-C9200-AA02\",\"purchase_date\":\"2023-11-15\",\"purchase_cost\":3299.99,\"warranty_months\":60,\"supplier_id\":$SUP_INSIGHT,\"rtd_location_id\":$LOC_AUSTIN,\"notes\":\"Austin data center core switch\"}"

# Servers
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-S001\",\"name\":\"Dell PowerEdge R750 - Production\",\"model_id\":$MDL_R750,\"status_id\":$SL_DEPLOYED,\"serial\":\"PE-R750-SN-1001\",\"purchase_date\":\"2023-08-01\",\"purchase_cost\":8499.99,\"warranty_months\":60,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_AUSTIN,\"notes\":\"Production application server\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-S002\",\"name\":\"Dell PowerEdge R750 - Staging\",\"model_id\":$MDL_R750,\"status_id\":$SL_DEPLOYED,\"serial\":\"PE-R750-SN-1002\",\"purchase_date\":\"2023-08-01\",\"purchase_cost\":8499.99,\"warranty_months\":60,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_AUSTIN,\"notes\":\"Staging environment server\"}"

# Retired asset
snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-L010\",\"name\":\"Dell Latitude 5530 - Retired\",\"model_id\":$MDL_LAT5540,\"status_id\":$SL_RETIRED,\"serial\":\"DL5530-SN-OLD1\",\"purchase_date\":\"2020-03-15\",\"purchase_cost\":1099.99,\"warranty_months\":36,\"supplier_id\":$SUP_CDW,\"rtd_location_id\":$LOC_HQA,\"notes\":\"End of life, replaced by 5540 series\"}"

# --- Checkout some assets to users ---
echo "  Checking out assets to users..."
snipeit_api POST "hardware/$HW_L001/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USR_SCHEN,\"note\":\"Standard IT Director laptop assignment\"}"
snipeit_api POST "hardware/$HW_L004/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USR_JROD,\"note\":\"Engineering laptop assignment\"}"
snipeit_api POST "hardware/$HW_L005/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USR_EWAT,\"note\":\"HR department laptop\"}"
snipeit_api POST "hardware/$HW_L007/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USR_DKIM,\"note\":\"DevOps workstation\"}"
snipeit_api POST "hardware/$HW_L008/checkout" "{\"checkout_to_type\":\"user\",\"assigned_user\":$USR_AKOW,\"note\":\"London frontend developer\"}"

# --- Licenses ---
echo "  Creating licenses..."
snipeit_api POST "licenses" "{\"name\":\"Microsoft 365 Business Premium\",\"serial\":\"MS365-BP-2024-001\",\"seats\":50,\"category_id\":$CAT_PRODSW,\"manufacturer_id\":$MFR_MSFT,\"purchase_date\":\"2024-01-01\",\"purchase_cost\":2640.00,\"expiration_date\":\"2025-01-01\",\"order_number\":\"PO-2024-0101\",\"supplier_id\":$SUP_SHI,\"notes\":\"Annual subscription for all employees\"}"
snipeit_api POST "licenses" "{\"name\":\"Adobe Creative Cloud - All Apps\",\"serial\":\"ACC-TEAM-2024-001\",\"seats\":10,\"category_id\":$CAT_PRODSW,\"manufacturer_id\":$MFR_MSFT,\"purchase_date\":\"2024-03-01\",\"purchase_cost\":6599.90,\"expiration_date\":\"2025-03-01\",\"order_number\":\"PO-2024-0215\",\"supplier_id\":$SUP_SHI,\"notes\":\"Team license for design and marketing\"}"
snipeit_api POST "licenses" "{\"name\":\"Windows 11 Enterprise\",\"serial\":\"WIN11-ENT-VOL-001\",\"seats\":100,\"category_id\":$CAT_OS,\"manufacturer_id\":$MFR_MSFT,\"purchase_date\":\"2023-06-01\",\"purchase_cost\":8400.00,\"expiration_date\":\"2026-06-01\",\"order_number\":\"PO-2023-0550\",\"supplier_id\":$SUP_SHI,\"notes\":\"Volume licensing agreement\"}"

# --- Accessories ---
echo "  Creating accessories..."
snipeit_api POST "accessories" "{\"name\":\"Logitech MX Master 3S Mouse\",\"category_id\":$CAT_INPUT,\"manufacturer_id\":$MFR_LOGI,\"model_number\":\"910-006556\",\"qty\":25,\"purchase_date\":\"2024-02-15\",\"purchase_cost\":99.99,\"supplier_id\":$SUP_CDW,\"location_id\":$LOC_HQA,\"notes\":\"Ergonomic wireless mouse\"}"
snipeit_api POST "accessories" "{\"name\":\"Dell USB-C to HDMI Adapter\",\"category_id\":$CAT_CABLES,\"manufacturer_id\":$MFR_DELL,\"model_number\":\"DA310\",\"qty\":30,\"purchase_date\":\"2024-01-10\",\"purchase_cost\":69.99,\"supplier_id\":$SUP_CDW,\"location_id\":$LOC_HQA,\"notes\":\"Universal multiport adapter\"}"
snipeit_api POST "accessories" "{\"name\":\"Jabra Evolve2 75 Headset\",\"category_id\":$CAT_INPUT,\"manufacturer_id\":$MFR_LOGI,\"model_number\":\"27599-989-999\",\"qty\":15,\"purchase_date\":\"2024-03-20\",\"purchase_cost\":299.99,\"supplier_id\":$SUP_CDW,\"location_id\":$LOC_HQA,\"notes\":\"Wireless ANC headset for remote meetings\"}"

# --- Consumables ---
echo "  Creating consumables..."
snipeit_api POST "consumables" "{\"name\":\"HP 58A Black Toner\",\"category_id\":$CAT_PRINTSUP,\"manufacturer_id\":$MFR_HP,\"model_number\":\"CF258A\",\"qty\":20,\"purchase_date\":\"2024-04-01\",\"purchase_cost\":119.99,\"location_id\":$LOC_HQA,\"notes\":\"Compatible with HP LaserJet Pro M404/M428\"}"

# --- Components ---
echo "  Creating components..."
snipeit_api POST "components" "{\"name\":\"16GB DDR4-3200 SODIMM\",\"category_id\":$CAT_MEMORY,\"qty\":10,\"purchase_date\":\"2024-02-01\",\"purchase_cost\":49.99,\"location_id\":$LOC_HQA,\"notes\":\"Laptop memory upgrade kit\"}"
snipeit_api POST "components" "{\"name\":\"512GB NVMe M.2 SSD\",\"category_id\":$CAT_STORAGE,\"qty\":8,\"purchase_date\":\"2024-02-01\",\"purchase_cost\":59.99,\"location_id\":$LOC_HQA,\"notes\":\"Samsung 980 PRO replacement drives\"}"

echo "--- Data seeding complete ---"

# ---------------------------------------------------------------
# 11. Verify data was loaded
# ---------------------------------------------------------------
echo "--- Verifying seeded data ---"
ASSET_COUNT=$(snipeit_api GET "hardware" "" | jq -r '.total // 0' 2>/dev/null || echo "0")
USER_COUNT=$(snipeit_api GET "users" "" | jq -r '.total // 0' 2>/dev/null || echo "0")
CAT_COUNT=$(snipeit_api GET "categories" "" | jq -r '.total // 0' 2>/dev/null || echo "0")
echo "  Assets: $ASSET_COUNT"
echo "  Users: $USER_COUNT"
echo "  Categories: $CAT_COUNT"

# ---------------------------------------------------------------
# 12. Create database query helper
# ---------------------------------------------------------------
echo "--- Creating database query helper ---"
cat > /usr/local/bin/snipeit-db-query << 'DBEOF'
#!/bin/bash
# Execute SQL query against Snipe-IT database
docker exec snipeit-db mysql -u snipeit -psnipeit_pass snipeit -N -e "$1" 2>/dev/null
DBEOF
chmod +x /usr/local/bin/snipeit-db-query

# ---------------------------------------------------------------
# 13. Setup Firefox for Snipe-IT
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"

# NOTE: On Ubuntu 22.04, Firefox is a snap package. Snap Firefox:
#   - Cannot access -profile paths outside its sandbox
#   - Stores its profile under ~/snap/firefox/common/.mozilla/firefox/
#   - Needs a warm-up launch to create its default profile directory
# Strategy: Launch Firefox once to create the default profile, then
# inject user.js preferences into that profile.

# Step 1: Do a brief warm-up launch to create the default profile
su - ga -c "DISPLAY=:1 firefox --headless &"
sleep 8
# Kill the warm-up instance
pkill -f firefox || true
sleep 2

# Step 2: Find the default profile directory created by snap Firefox
SNAP_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE_DIR" ]; then
    # Fallback: try non-snap location
    SNAP_PROFILE_DIR=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$SNAP_PROFILE_DIR" ]; then
    echo "  Found Firefox profile at: $SNAP_PROFILE_DIR"
    # Step 3: Write user.js preferences into the default profile
    cat > "$SNAP_PROFILE_DIR/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage", "http://localhost:8000");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.feeds.showFirstRunUI", false);
user_pref("browser.uitour.enabled", false);
FFEOF
    chown ga:ga "$SNAP_PROFILE_DIR/user.js"
else
    echo "  WARNING: Could not find Firefox default profile directory"
fi

# Create desktop shortcut (no -profile flag for snap compatibility)
cat > /home/ga/Desktop/SnipeIT.desktop << 'DSKEOF'
[Desktop Entry]
Name=Snipe-IT
Comment=IT Asset Management
Exec=firefox http://localhost:8000
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
DSKEOF
chmod +x /home/ga/Desktop/SnipeIT.desktop
chown ga:ga /home/ga/Desktop/SnipeIT.desktop

# ---------------------------------------------------------------
# 14. Launch Firefox with Snipe-IT
# ---------------------------------------------------------------
echo "--- Launching Firefox ---"
su - ga -c "DISPLAY=:1 firefox http://localhost:8000/login &"

# Wait for Firefox window to appear
echo "--- Waiting for Firefox window ---"
FIREFOX_TIMEOUT=60
FIREFOX_ELAPSED=0
while [ $FIREFOX_ELAPSED -lt $FIREFOX_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|snipe\|mozilla"; then
        echo "Firefox window detected (${FIREFOX_ELAPSED}s)"
        break
    fi
    sleep 3
    FIREFOX_ELAPSED=$((FIREFOX_ELAPSED + 3))
done

# Maximize Firefox window
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Snipe-IT setup complete ==="
echo "  URL: http://localhost:8000"
echo "  Admin: admin / password"
echo "  API Token saved to: /home/ga/snipeit/api_token.txt"
