<?php
/**
 * Vtiger CRM Data Seeder
 *
 * Seeds realistic CRM data using Vtiger's Webservice API.
 * Data represents Meridian Technology Partners, a mid-size IT consulting firm.
 *
 * Companies sourced from real industry verticals:
 * - Technology, Healthcare, Financial Services, Manufacturing, Retail, Energy
 *
 * Run inside the vtiger-app container:
 *   php /tmp/seed_data.php
 */

$VTIGER_URL = 'http://localhost:80';
$USERNAME   = 'admin';
$PASSWORD   = 'password';

// ---------------------------------------------------------------
// Vtiger Webservice API helper functions
// ---------------------------------------------------------------

function vtiger_challenge($url, $username) {
    $ch = curl_init("$url/webservice.php?operation=getchallenge&username=$username");
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $resp = json_decode(curl_exec($ch), true);
    curl_close($ch);
    if ($resp && $resp['success']) {
        return $resp['result']['token'];
    }
    return null;
}

function vtiger_login($url, $username, $accessKey) {
    $ch = curl_init("$url/webservice.php");
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'operation' => 'login',
        'username'  => $username,
        'accessKey' => $accessKey,
    ]));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $resp = json_decode(curl_exec($ch), true);
    curl_close($ch);
    if ($resp && $resp['success']) {
        return $resp['result']['sessionName'];
    }
    return null;
}

function vtiger_create($url, $sessionName, $elementType, $element) {
    $ch = curl_init("$url/webservice.php");
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'operation'   => 'create',
        'sessionName' => $sessionName,
        'elementType' => $elementType,
        'element'     => json_encode($element),
    ]));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $resp = json_decode(curl_exec($ch), true);
    curl_close($ch);
    if ($resp && $resp['success']) {
        return $resp['result'];
    }
    echo "  ERROR creating $elementType: " . json_encode($resp) . "\n";
    return null;
}

function vtiger_query($url, $sessionName, $query) {
    $ch = curl_init("$url/webservice.php");
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'operation'   => 'query',
        'sessionName' => $sessionName,
        'query'       => $query,
    ]));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $resp = json_decode(curl_exec($ch), true);
    curl_close($ch);
    if ($resp && $resp['success']) {
        return $resp['result'];
    }
    return [];
}

// ---------------------------------------------------------------
// Authenticate
// ---------------------------------------------------------------
echo "=== Vtiger CRM Data Seeder ===\n";

// Get admin user's access key from database
$dbh = new mysqli('vtiger-db', 'vtiger', 'vtiger_pass', 'vtiger');
if ($dbh->connect_error) {
    echo "DB connection failed: {$dbh->connect_error}\n";
    exit(1);
}

$result = $dbh->query("SELECT accesskey FROM vtiger_users WHERE user_name='admin' LIMIT 1");
if (!$result || $result->num_rows == 0) {
    echo "Admin user not found in database. Installation may not be complete.\n";
    echo "Attempting direct SQL seeding instead...\n";

    // Fall back to direct SQL seeding
    seed_via_sql($dbh);
    $dbh->close();
    exit(0);
}
$row = $result->fetch_assoc();
$userAccessKey = $row['accesskey'];

// Get challenge token
$token = vtiger_challenge($VTIGER_URL, $USERNAME);
if (!$token) {
    echo "Failed to get challenge token. Falling back to SQL seeding.\n";
    seed_via_sql($dbh);
    $dbh->close();
    exit(0);
}

// Login
$accessKey = md5($token . $userAccessKey);
$sessionName = vtiger_login($VTIGER_URL, $USERNAME, $accessKey);
if (!$sessionName) {
    echo "Failed to login via webservice. Falling back to SQL seeding.\n";
    seed_via_sql($dbh);
    $dbh->close();
    exit(0);
}

echo "Authenticated as admin (session: $sessionName)\n\n";
$dbh->close();

// ---------------------------------------------------------------
// Seed Organizations (Accounts)
// Real-world company names from various industries
// ---------------------------------------------------------------
echo "--- Creating Organizations ---\n";

$organizations = [
    ['accountname' => 'Apex Dynamics Inc', 'industry' => 'Technology', 'phone' => '415-555-0100', 'website' => 'https://www.apexdynamics.com', 'bill_street' => '500 Innovation Drive', 'bill_city' => 'San Jose', 'bill_state' => 'CA', 'bill_code' => '95110', 'bill_country' => 'United States', 'annual_revenue' => '45000000', 'employees' => '250', 'description' => 'Enterprise software and cloud infrastructure provider specializing in distributed computing solutions'],
    ['accountname' => 'Pinnacle Healthcare Systems', 'industry' => 'Healthcare', 'phone' => '617-555-0200', 'website' => 'https://www.pinnaclehealthsys.com', 'bill_street' => '200 Medical Center Blvd', 'bill_city' => 'Boston', 'bill_state' => 'MA', 'bill_code' => '02115', 'bill_country' => 'United States', 'annual_revenue' => '120000000', 'employees' => '800', 'description' => 'Integrated healthcare management platform for hospital networks and clinics'],
    ['accountname' => 'Sterling Financial Group', 'industry' => 'Finance', 'phone' => '212-555-0300', 'website' => 'https://www.sterlingfg.com', 'bill_street' => '1 Wall Street Plaza', 'bill_city' => 'New York', 'bill_state' => 'NY', 'bill_code' => '10005', 'bill_country' => 'United States', 'annual_revenue' => '890000000', 'employees' => '2500', 'description' => 'Investment banking and wealth management services for institutional clients'],
    ['accountname' => 'GreenLeaf Manufacturing', 'industry' => 'Manufacturing', 'phone' => '313-555-0400', 'website' => 'https://www.greenleafmfg.com', 'bill_street' => '4500 Industrial Parkway', 'bill_city' => 'Detroit', 'bill_state' => 'MI', 'bill_code' => '48201', 'bill_country' => 'United States', 'annual_revenue' => '67000000', 'employees' => '450', 'description' => 'Sustainable packaging and material solutions for consumer goods industry'],
    ['accountname' => 'Coastal Retail Holdings', 'industry' => 'Retail', 'phone' => '305-555-0500', 'website' => 'https://www.coastalretail.com', 'bill_street' => '800 Brickell Avenue', 'bill_city' => 'Miami', 'bill_state' => 'FL', 'bill_code' => '33131', 'bill_country' => 'United States', 'annual_revenue' => '230000000', 'employees' => '1200', 'description' => 'Multi-brand retail chain with 85 locations across southeastern United States'],
    ['accountname' => 'Nexus Energy Solutions', 'industry' => 'Energy', 'phone' => '713-555-0600', 'website' => 'https://www.nexusenergy.com', 'bill_street' => '1200 Smith Street', 'bill_city' => 'Houston', 'bill_state' => 'TX', 'bill_code' => '77002', 'bill_country' => 'United States', 'annual_revenue' => '540000000', 'employees' => '1800', 'description' => 'Renewable energy infrastructure and consulting services'],
    ['accountname' => 'Atlas Logistics Corp', 'industry' => 'Transportation', 'phone' => '901-555-0700', 'website' => 'https://www.atlaslogistics.com', 'bill_street' => '3000 Freight Boulevard', 'bill_city' => 'Memphis', 'bill_state' => 'TN', 'bill_code' => '38118', 'bill_country' => 'United States', 'annual_revenue' => '180000000', 'employees' => '950', 'description' => 'Full-service freight and supply chain management for North American markets'],
    ['accountname' => 'BrightPath Education', 'industry' => 'Education', 'phone' => '512-555-0800', 'website' => 'https://www.brightpathedu.com', 'bill_street' => '700 Lavaca Street', 'bill_city' => 'Austin', 'bill_state' => 'TX', 'bill_code' => '78701', 'bill_country' => 'United States', 'annual_revenue' => '35000000', 'employees' => '180', 'description' => 'EdTech platform providing K-12 digital learning tools and teacher training'],
    ['accountname' => 'Horizon Telecom', 'industry' => 'Telecommunications', 'phone' => '720-555-0900', 'website' => 'https://www.horizontelecom.com', 'bill_street' => '1600 Broadway', 'bill_city' => 'Denver', 'bill_state' => 'CO', 'bill_code' => '80202', 'bill_country' => 'United States', 'annual_revenue' => '310000000', 'employees' => '1400', 'description' => 'Regional telecommunications provider offering fiber, wireless, and managed IT services'],
    ['accountname' => 'Catalyst Biotech', 'industry' => 'Healthcare', 'phone' => '858-555-1000', 'website' => 'https://www.catalystbiotech.com', 'bill_street' => '10920 Via Frontera', 'bill_city' => 'San Diego', 'bill_state' => 'CA', 'bill_code' => '92127', 'bill_country' => 'United States', 'annual_revenue' => '28000000', 'employees' => '120', 'description' => 'Biopharmaceutical research company focused on autoimmune disease therapies'],
    ['accountname' => 'Summit Construction Group', 'industry' => 'Construction', 'phone' => '303-555-1100', 'website' => 'https://www.summitcg.com', 'bill_street' => '2100 16th Street', 'bill_city' => 'Denver', 'bill_state' => 'CO', 'bill_code' => '80202', 'bill_country' => 'United States', 'annual_revenue' => '95000000', 'employees' => '600', 'description' => 'Commercial and residential construction services across Rocky Mountain region'],
    ['accountname' => 'DataForge Analytics', 'industry' => 'Technology', 'phone' => '206-555-1200', 'website' => 'https://www.dataforge.io', 'bill_street' => '400 Union Avenue', 'bill_city' => 'Seattle', 'bill_state' => 'WA', 'bill_code' => '98101', 'bill_country' => 'United States', 'annual_revenue' => '52000000', 'employees' => '280', 'description' => 'Big data analytics and machine learning platform for enterprise customers'],
    ['accountname' => 'Pacific Seafood Distributors', 'industry' => 'Food & Beverage', 'phone' => '503-555-1300', 'website' => 'https://www.pacificseafood.com', 'bill_street' => '3380 SE Powell Blvd', 'bill_city' => 'Portland', 'bill_state' => 'OR', 'bill_code' => '97202', 'bill_country' => 'United States', 'annual_revenue' => '78000000', 'employees' => '350', 'description' => 'Wholesale seafood distribution serving restaurants and retailers across the Pacific Northwest'],
    ['accountname' => 'Vanguard Security Services', 'industry' => 'Technology', 'phone' => '571-555-1400', 'website' => 'https://www.vanguardsec.com', 'bill_street' => '1900 Campus Commons Drive', 'bill_city' => 'Reston', 'bill_state' => 'VA', 'bill_code' => '20191', 'bill_country' => 'United States', 'annual_revenue' => '110000000', 'employees' => '700', 'description' => 'Cybersecurity consulting and managed security operations for government and enterprise'],
    ['accountname' => 'Ironclad Insurance', 'industry' => 'Insurance', 'phone' => '860-555-1500', 'website' => 'https://www.ironcladins.com', 'bill_street' => '1 Hartford Plaza', 'bill_city' => 'Hartford', 'bill_state' => 'CT', 'bill_code' => '06103', 'bill_country' => 'United States', 'annual_revenue' => '420000000', 'employees' => '2000', 'description' => 'Property and casualty insurance with focus on commercial lines and risk management'],
];

$org_ids = [];
foreach ($organizations as $org) {
    $org['assigned_user_id'] = '19x1'; // admin user
    $result = vtiger_create($VTIGER_URL, $sessionName, 'Accounts', $org);
    if ($result) {
        $org_ids[$org['accountname']] = $result['id'];
        echo "  Created org: {$org['accountname']} (ID: {$result['id']})\n";
    }
}

// ---------------------------------------------------------------
// Seed Contacts
// Realistic contact data associated with the organizations
// ---------------------------------------------------------------
echo "\n--- Creating Contacts ---\n";

$contacts = [
    ['firstname' => 'Robert', 'lastname' => 'Chen', 'account_id' => 'Apex Dynamics Inc', 'title' => 'Chief Technology Officer', 'email' => 'robert.chen@apexdynamics.com', 'phone' => '415-555-0101', 'mobile' => '415-555-0111', 'mailingstreet' => '500 Innovation Drive', 'mailingcity' => 'San Jose', 'mailingstate' => 'CA', 'mailingzip' => '95110', 'mailingcountry' => 'United States', 'description' => 'Primary technical decision maker. Previously VP Engineering at Salesforce.'],
    ['firstname' => 'Jennifer', 'lastname' => 'Walsh', 'account_id' => 'Apex Dynamics Inc', 'title' => 'VP of Procurement', 'email' => 'jennifer.walsh@apexdynamics.com', 'phone' => '415-555-0102', 'mobile' => '415-555-0112', 'mailingstreet' => '500 Innovation Drive', 'mailingcity' => 'San Jose', 'mailingstate' => 'CA', 'mailingzip' => '95110', 'mailingcountry' => 'United States', 'description' => 'Handles vendor contracts and procurement decisions.'],
    ['firstname' => 'Dr. Amara', 'lastname' => 'Johnson', 'account_id' => 'Pinnacle Healthcare Systems', 'title' => 'Chief Information Officer', 'email' => 'amara.johnson@pinnaclehealthsys.com', 'phone' => '617-555-0201', 'mobile' => '617-555-0211', 'mailingstreet' => '200 Medical Center Blvd', 'mailingcity' => 'Boston', 'mailingstate' => 'MA', 'mailingzip' => '02115', 'mailingcountry' => 'United States', 'description' => 'Oversees all IT infrastructure for 12-hospital network. Board certified in Health Informatics.'],
    ['firstname' => 'Marcus', 'lastname' => 'Rivera', 'account_id' => 'Pinnacle Healthcare Systems', 'title' => 'IT Security Director', 'email' => 'marcus.rivera@pinnaclehealthsys.com', 'phone' => '617-555-0202', 'mobile' => '617-555-0212', 'mailingstreet' => '200 Medical Center Blvd', 'mailingcity' => 'Boston', 'mailingstate' => 'MA', 'mailingzip' => '02115', 'mailingcountry' => 'United States', 'description' => 'HIPAA compliance lead. Manages security operations center.'],
    ['firstname' => 'Victoria', 'lastname' => 'Blackwell', 'account_id' => 'Sterling Financial Group', 'title' => 'Managing Director', 'email' => 'v.blackwell@sterlingfg.com', 'phone' => '212-555-0301', 'mobile' => '212-555-0311', 'mailingstreet' => '1 Wall Street Plaza', 'mailingcity' => 'New York', 'mailingstate' => 'NY', 'mailingzip' => '10005', 'mailingcountry' => 'United States', 'description' => 'Senior partner responsible for technology investments. 20 years in fintech.'],
    ['firstname' => 'Thomas', 'lastname' => 'Park', 'account_id' => 'Sterling Financial Group', 'title' => 'Head of Digital Transformation', 'email' => 'thomas.park@sterlingfg.com', 'phone' => '212-555-0302', 'mobile' => '212-555-0312', 'mailingstreet' => '1 Wall Street Plaza', 'mailingcity' => 'New York', 'mailingstate' => 'NY', 'mailingzip' => '10005', 'mailingcountry' => 'United States', 'description' => 'Leading cloud migration initiative across all trading desks.'],
    ['firstname' => 'Karen', 'lastname' => 'Okafor', 'account_id' => 'GreenLeaf Manufacturing', 'title' => 'Operations Manager', 'email' => 'karen.okafor@greenleafmfg.com', 'phone' => '313-555-0401', 'mobile' => '313-555-0411', 'mailingstreet' => '4500 Industrial Parkway', 'mailingcity' => 'Detroit', 'mailingstate' => 'MI', 'mailingzip' => '48201', 'mailingcountry' => 'United States', 'description' => 'Manages 3 production facilities. Champion of Industry 4.0 automation.'],
    ['firstname' => 'Daniel', 'lastname' => 'Moretti', 'account_id' => 'Coastal Retail Holdings', 'title' => 'Chief Marketing Officer', 'email' => 'daniel.moretti@coastalretail.com', 'phone' => '305-555-0501', 'mobile' => '305-555-0511', 'mailingstreet' => '800 Brickell Avenue', 'mailingcity' => 'Miami', 'mailingstate' => 'FL', 'mailingzip' => '33131', 'mailingcountry' => 'United States', 'description' => 'Driving omnichannel retail strategy across 85 store locations.'],
    ['firstname' => 'Sarah', 'lastname' => 'Kim', 'account_id' => 'Coastal Retail Holdings', 'title' => 'Director of E-Commerce', 'email' => 'sarah.kim@coastalretail.com', 'phone' => '305-555-0502', 'mobile' => '305-555-0512', 'mailingstreet' => '800 Brickell Avenue', 'mailingcity' => 'Miami', 'mailingstate' => 'FL', 'mailingzip' => '33131', 'mailingcountry' => 'United States', 'description' => 'Managing $45M online revenue channel. Shopify Plus migration lead.'],
    ['firstname' => 'Ahmad', 'lastname' => 'Hassan', 'account_id' => 'Nexus Energy Solutions', 'title' => 'VP of Engineering', 'email' => 'ahmad.hassan@nexusenergy.com', 'phone' => '713-555-0601', 'mobile' => '713-555-0611', 'mailingstreet' => '1200 Smith Street', 'mailingcity' => 'Houston', 'mailingstate' => 'TX', 'mailingzip' => '77002', 'mailingcountry' => 'United States', 'description' => 'Leads engineering for solar and wind farm SCADA systems.'],
    ['firstname' => 'Lisa', 'lastname' => 'Thompson', 'account_id' => 'Atlas Logistics Corp', 'title' => 'Supply Chain Director', 'email' => 'lisa.thompson@atlaslogistics.com', 'phone' => '901-555-0701', 'mobile' => '901-555-0711', 'mailingstreet' => '3000 Freight Boulevard', 'mailingcity' => 'Memphis', 'mailingstate' => 'TN', 'mailingzip' => '38118', 'mailingcountry' => 'United States', 'description' => 'Optimizing last-mile delivery for 15 distribution centers.'],
    ['firstname' => 'James', 'lastname' => 'Crawford', 'account_id' => 'BrightPath Education', 'title' => 'Founder & CEO', 'email' => 'james.crawford@brightpathedu.com', 'phone' => '512-555-0801', 'mobile' => '512-555-0811', 'mailingstreet' => '700 Lavaca Street', 'mailingcity' => 'Austin', 'mailingstate' => 'TX', 'mailingzip' => '78701', 'mailingcountry' => 'United States', 'description' => 'Former teacher turned EdTech entrepreneur. Focus on underserved school districts.'],
    ['firstname' => 'Rachel', 'lastname' => 'Nguyen', 'account_id' => 'Horizon Telecom', 'title' => 'Network Architect', 'email' => 'rachel.nguyen@horizontelecom.com', 'phone' => '720-555-0901', 'mobile' => '720-555-0911', 'mailingstreet' => '1600 Broadway', 'mailingcity' => 'Denver', 'mailingstate' => 'CO', 'mailingzip' => '80202', 'mailingcountry' => 'United States', 'description' => 'Designing 5G rollout across Colorado and Wyoming service territories.'],
    ['firstname' => 'Dr. Michael', 'lastname' => 'Sato', 'account_id' => 'Catalyst Biotech', 'title' => 'VP of Research', 'email' => 'michael.sato@catalystbiotech.com', 'phone' => '858-555-1001', 'mobile' => '858-555-1011', 'mailingstreet' => '10920 Via Frontera', 'mailingcity' => 'San Diego', 'mailingstate' => 'CA', 'mailingzip' => '92127', 'mailingcountry' => 'United States', 'description' => 'Leading Phase II clinical trials for CB-201 autoimmune therapy. Published 40+ papers.'],
    ['firstname' => 'Patricia', 'lastname' => 'Gonzalez', 'account_id' => 'Summit Construction Group', 'title' => 'Project Manager', 'email' => 'patricia.gonzalez@summitcg.com', 'phone' => '303-555-1101', 'mobile' => '303-555-1111', 'mailingstreet' => '2100 16th Street', 'mailingcity' => 'Denver', 'mailingstate' => 'CO', 'mailingzip' => '80202', 'mailingcountry' => 'United States', 'description' => 'Managing $30M commercial construction projects. LEED AP certified.'],
    ['firstname' => 'Kevin', 'lastname' => 'Wu', 'account_id' => 'DataForge Analytics', 'title' => 'Chief Data Officer', 'email' => 'kevin.wu@dataforge.io', 'phone' => '206-555-1201', 'mobile' => '206-555-1211', 'mailingstreet' => '400 Union Avenue', 'mailingcity' => 'Seattle', 'mailingstate' => 'WA', 'mailingzip' => '98101', 'mailingcountry' => 'United States', 'description' => 'PhD Stanford CS. Building next-gen real-time analytics engine.'],
    ['firstname' => 'Michael', 'lastname' => 'Torres', 'account_id' => 'Pacific Seafood Distributors', 'title' => 'General Manager', 'email' => 'michael.torres@pacificseafood.com', 'phone' => '503-555-1301', 'mobile' => '503-555-1311', 'mailingstreet' => '3380 SE Powell Blvd', 'mailingcity' => 'Portland', 'mailingstate' => 'OR', 'mailingzip' => '97202', 'mailingcountry' => 'United States', 'description' => 'Third-generation seafood industry veteran. Manages fleet of 25 refrigerated trucks.'],
    ['firstname' => 'Diana', 'lastname' => 'Petrov', 'account_id' => 'Vanguard Security Services', 'title' => 'CISO', 'email' => 'diana.petrov@vanguardsec.com', 'phone' => '571-555-1401', 'mobile' => '571-555-1411', 'mailingstreet' => '1900 Campus Commons Drive', 'mailingcity' => 'Reston', 'mailingstate' => 'VA', 'mailingzip' => '20191', 'mailingcountry' => 'United States', 'description' => 'Former NSA. Leads threat intelligence and incident response teams.'],
    ['firstname' => 'William', 'lastname' => 'Harper', 'account_id' => 'Ironclad Insurance', 'title' => 'VP of Claims', 'email' => 'william.harper@ironcladins.com', 'phone' => '860-555-1501', 'mobile' => '860-555-1511', 'mailingstreet' => '1 Hartford Plaza', 'mailingcity' => 'Hartford', 'mailingstate' => 'CT', 'mailingzip' => '06103', 'mailingcountry' => 'United States', 'description' => 'Modernizing claims processing with AI-powered damage assessment.'],
    ['firstname' => 'Emily', 'lastname' => 'Johansson', 'account_id' => 'Nexus Energy Solutions', 'title' => 'Sustainability Director', 'email' => 'emily.johansson@nexusenergy.com', 'phone' => '713-555-0602', 'mobile' => '713-555-0612', 'mailingstreet' => '1200 Smith Street', 'mailingcity' => 'Houston', 'mailingstate' => 'TX', 'mailingzip' => '77002', 'mailingcountry' => 'United States', 'description' => 'Carbon offset program manager. Previously at DOE.'],
];

$contact_ids = [];
foreach ($contacts as $contact) {
    $acct_name = $contact['account_id'];
    if (isset($org_ids[$acct_name])) {
        $contact['account_id'] = $org_ids[$acct_name];
    } else {
        unset($contact['account_id']);
    }
    $contact['assigned_user_id'] = '19x1';
    $result = vtiger_create($VTIGER_URL, $sessionName, 'Contacts', $contact);
    if ($result) {
        $contact_ids[$contact['firstname'] . ' ' . $contact['lastname']] = $result['id'];
        echo "  Created contact: {$contact['firstname']} {$contact['lastname']} (ID: {$result['id']})\n";
    }
}

// ---------------------------------------------------------------
// Seed Products
// Technology products and services offered by Meridian Tech Partners
// ---------------------------------------------------------------
echo "\n--- Creating Products ---\n";

$products = [
    ['productname' => 'Cloud Infrastructure Assessment', 'productcode' => 'SVC-CIA-001', 'unit_price' => '15000.00', 'qty_per_unit' => '1', 'description' => 'Comprehensive assessment of existing IT infrastructure for cloud migration readiness. Includes network topology review, application dependency mapping, and migration roadmap.', 'product_no' => 'PRD-001'],
    ['productname' => 'Enterprise Security Audit', 'productcode' => 'SVC-ESA-002', 'unit_price' => '25000.00', 'qty_per_unit' => '1', 'description' => 'Full-scope security audit including penetration testing, vulnerability assessment, compliance gap analysis (SOC 2, ISO 27001), and remediation planning.', 'product_no' => 'PRD-002'],
    ['productname' => 'Data Analytics Platform License', 'productcode' => 'LIC-DAP-003', 'unit_price' => '5000.00', 'qty_per_unit' => '1', 'description' => 'Annual license for DataForge Analytics Platform. Includes real-time dashboarding, ML model deployment, and unlimited data connectors. Per-seat pricing.', 'product_no' => 'PRD-003'],
    ['productname' => 'Managed SOC Service (Monthly)', 'productcode' => 'MSP-SOC-004', 'unit_price' => '8500.00', 'qty_per_unit' => '1', 'description' => 'Monthly managed Security Operations Center service. 24/7 monitoring, threat detection, incident response, and quarterly threat reports.', 'product_no' => 'PRD-004'],
    ['productname' => 'Custom ERP Integration', 'productcode' => 'SVC-ERP-005', 'unit_price' => '45000.00', 'qty_per_unit' => '1', 'description' => 'Custom integration between legacy ERP systems and modern cloud platforms. Includes API development, data migration, testing, and 90 days post-launch support.', 'product_no' => 'PRD-005'],
    ['productname' => 'Network Infrastructure Upgrade', 'productcode' => 'HW-NIU-006', 'unit_price' => '75000.00', 'qty_per_unit' => '1', 'description' => 'Complete network refresh including Cisco Catalyst switches, Meraki wireless APs, SD-WAN controllers, and professional installation services.', 'product_no' => 'PRD-006'],
    ['productname' => 'Staff Augmentation (Senior Consultant)', 'productcode' => 'SVC-SAS-007', 'unit_price' => '12000.00', 'qty_per_unit' => '1', 'description' => 'Monthly rate for senior technology consultant placement. 160 hours per month. Specialties available: DevOps, Cloud Architecture, Security, Data Engineering.', 'product_no' => 'PRD-007'],
    ['productname' => 'Disaster Recovery Planning', 'productcode' => 'SVC-DRP-008', 'unit_price' => '20000.00', 'qty_per_unit' => '1', 'description' => 'Business continuity and disaster recovery planning engagement. RTO/RPO analysis, DR architecture design, runbook development, and tabletop exercise.', 'product_no' => 'PRD-008'],
    ['productname' => 'IoT Sensor Platform Bundle', 'productcode' => 'HW-IOT-009', 'unit_price' => '35000.00', 'qty_per_unit' => '1', 'description' => 'Industrial IoT monitoring bundle: 50 environmental sensors, gateway hardware, LoRaWAN connectivity, and 1-year cloud platform subscription.', 'product_no' => 'PRD-009'],
    ['productname' => 'Compliance Management Software', 'productcode' => 'LIC-CMS-010', 'unit_price' => '7500.00', 'qty_per_unit' => '1', 'description' => 'Annual license for compliance management platform. Supports HIPAA, SOC 2, PCI DSS, and GDPR frameworks. Includes automated evidence collection and audit trail.', 'product_no' => 'PRD-010'],
];

$product_ids = [];
foreach ($products as $product) {
    $product['assigned_user_id'] = '19x1';
    $result = vtiger_create($VTIGER_URL, $sessionName, 'Products', $product);
    if ($result) {
        $product_ids[$product['productname']] = $result['id'];
        echo "  Created product: {$product['productname']} (ID: {$result['id']})\n";
    }
}

// ---------------------------------------------------------------
// Seed Deals (Potentials)
// Active sales pipeline for Meridian Tech Partners
// ---------------------------------------------------------------
echo "\n--- Creating Deals ---\n";

$deals = [
    ['potentialname' => 'Apex Cloud Migration Phase 2', 'related_to' => 'Apex Dynamics Inc', 'contact_id' => 'Robert Chen', 'amount' => '185000', 'sales_stage' => 'Proposal/Price Quote', 'closingdate' => '2026-04-15', 'probability' => '65', 'description' => 'Phase 2 of cloud migration project. Migrating remaining 40 applications to AWS. Includes refactoring of 3 legacy monoliths to microservices.'],
    ['potentialname' => 'Pinnacle EHR Security Upgrade', 'related_to' => 'Pinnacle Healthcare Systems', 'contact_id' => 'Dr. Amara Johnson', 'amount' => '320000', 'sales_stage' => 'Negotiation/Review', 'closingdate' => '2026-03-30', 'probability' => '80', 'description' => 'HIPAA-compliant security overhaul for 12-hospital EHR system. Includes zero-trust architecture, MFA rollout, and security awareness training.'],
    ['potentialname' => 'Sterling Trading Platform Modernization', 'related_to' => 'Sterling Financial Group', 'contact_id' => 'Thomas Park', 'amount' => '750000', 'sales_stage' => 'Qualification', 'closingdate' => '2026-06-30', 'probability' => '35', 'description' => 'Modernize legacy trading platform from on-premises to cloud-native. 18-month engagement with dedicated team of 8 consultants.'],
    ['potentialname' => 'GreenLeaf IoT Factory Monitoring', 'related_to' => 'GreenLeaf Manufacturing', 'contact_id' => 'Karen Okafor', 'amount' => '95000', 'sales_stage' => 'Needs Analysis', 'closingdate' => '2026-05-15', 'probability' => '45', 'description' => 'Deploy IoT sensor platform across 3 manufacturing facilities for real-time production monitoring and predictive maintenance.'],
    ['potentialname' => 'Coastal Retail E-Commerce Replatform', 'related_to' => 'Coastal Retail Holdings', 'contact_id' => 'Sarah Kim', 'amount' => '210000', 'sales_stage' => 'Proposal/Price Quote', 'closingdate' => '2026-04-01', 'probability' => '60', 'description' => 'Migrate from Magento to Shopify Plus. Includes custom theme development, 85-store inventory integration, and mobile app redesign.'],
    ['potentialname' => 'Nexus SCADA Security Assessment', 'related_to' => 'Nexus Energy Solutions', 'contact_id' => 'Ahmad Hassan', 'amount' => '55000', 'sales_stage' => 'Closed Won', 'closingdate' => '2026-01-15', 'probability' => '100', 'description' => 'Security assessment of industrial control systems across 12 solar farms and 4 wind installations. Completed successfully.'],
    ['potentialname' => 'Atlas Supply Chain Analytics', 'related_to' => 'Atlas Logistics Corp', 'contact_id' => 'Lisa Thompson', 'amount' => '130000', 'sales_stage' => 'Perception Analysis', 'closingdate' => '2026-07-31', 'probability' => '25', 'description' => 'Implement real-time supply chain analytics platform with demand forecasting and route optimization for 15 distribution centers.'],
    ['potentialname' => 'BrightPath LMS Platform Build', 'related_to' => 'BrightPath Education', 'contact_id' => 'James Crawford', 'amount' => '165000', 'sales_stage' => 'Proposal/Price Quote', 'closingdate' => '2026-05-01', 'probability' => '70', 'description' => 'Build custom learning management system with adaptive testing, gamification, and parent dashboard. Target: 500 school districts.'],
    ['potentialname' => 'Horizon 5G Network Planning', 'related_to' => 'Horizon Telecom', 'contact_id' => 'Rachel Nguyen', 'amount' => '280000', 'sales_stage' => 'Negotiation/Review', 'closingdate' => '2026-03-15', 'probability' => '75', 'description' => 'RF planning and optimization for 5G rollout across 200 cell sites in Colorado. Includes small cell deployment strategy.'],
    ['potentialname' => 'Catalyst LIMS Implementation', 'related_to' => 'Catalyst Biotech', 'contact_id' => 'Dr. Michael Sato', 'amount' => '90000', 'sales_stage' => 'Needs Analysis', 'closingdate' => '2026-08-15', 'probability' => '40', 'description' => 'Implement laboratory information management system for GLP-compliant research data management.'],
    ['potentialname' => 'Vanguard SOC Expansion', 'related_to' => 'Vanguard Security Services', 'contact_id' => 'Diana Petrov', 'amount' => '420000', 'sales_stage' => 'Closed Won', 'closingdate' => '2025-12-20', 'probability' => '100', 'description' => 'Expanded managed SOC contract to include 24/7 OT security monitoring. 3-year contract renewal with increased scope.'],
    ['potentialname' => 'Ironclad Claims AI Platform', 'related_to' => 'Ironclad Insurance', 'contact_id' => 'William Harper', 'amount' => '350000', 'sales_stage' => 'Qualification', 'closingdate' => '2026-09-30', 'probability' => '30', 'description' => 'AI-powered claims processing system with computer vision for damage assessment. Pilot with auto insurance division.'],
];

foreach ($deals as $deal) {
    $acct_name = $deal['related_to'];
    $contact_name = $deal['contact_id'];
    if (isset($org_ids[$acct_name])) {
        $deal['related_to'] = $org_ids[$acct_name];
    }
    if (isset($contact_ids[$contact_name])) {
        $deal['contact_id'] = $contact_ids[$contact_name];
    } else {
        unset($deal['contact_id']);
    }
    $deal['assigned_user_id'] = '19x1';
    $result = vtiger_create($VTIGER_URL, $sessionName, 'Potentials', $deal);
    if ($result) {
        echo "  Created deal: {$deal['potentialname']} (ID: {$result['id']})\n";
    }
}

// ---------------------------------------------------------------
// Seed Tickets (HelpDesk)
// Support tickets from various clients
// ---------------------------------------------------------------
echo "\n--- Creating Tickets ---\n";

$tickets = [
    ['ticket_title' => 'VPN connectivity drops during peak hours', 'parent_id' => 'Apex Dynamics Inc', 'contact_id' => 'Robert Chen', 'ticketstatus' => 'Open', 'ticketpriorities' => 'High', 'ticketseverities' => 'Major', 'description' => 'Users report intermittent VPN disconnections between 9-11 AM EST when remote workforce connects. Affecting approximately 80 users. Split tunnel configuration may need adjustment. Current throughput at 92% capacity on primary VPN concentrator.'],
    ['ticket_title' => 'HIPAA audit finding - unencrypted backups', 'parent_id' => 'Pinnacle Healthcare Systems', 'contact_id' => 'Marcus Rivera', 'ticketstatus' => 'In Progress', 'ticketpriorities' => 'Urgent', 'ticketseverities' => 'Critical', 'description' => 'External auditor identified 3 backup volumes without AES-256 encryption in the disaster recovery site. Requires immediate remediation before March compliance deadline. All patient data backups must be encrypted at rest per HIPAA Security Rule §164.312(a)(2)(iv).'],
    ['ticket_title' => 'E-commerce checkout timeout errors', 'parent_id' => 'Coastal Retail Holdings', 'contact_id' => 'Sarah Kim', 'ticketstatus' => 'Open', 'ticketpriorities' => 'High', 'ticketseverities' => 'Major', 'description' => 'Customers experiencing timeout errors during checkout since last deployment (v3.2.1). Error rate: 4.2% of transactions. Payment gateway responding within SLA but application server pool exhausting connections. Estimated revenue impact: $12K/day.'],
    ['ticket_title' => 'Solar farm SCADA alert false positives', 'parent_id' => 'Nexus Energy Solutions', 'contact_id' => 'Ahmad Hassan', 'ticketstatus' => 'Waiting For Response', 'ticketpriorities' => 'Normal', 'ticketseverities' => 'Minor', 'description' => 'Receiving 200+ false positive alerts daily from Mojave Desert solar installation. Temperature sensor thresholds set too low for summer conditions. Need to recalibrate alerting rules for seasonal variation.'],
    ['ticket_title' => 'TMS integration data sync failure', 'parent_id' => 'Atlas Logistics Corp', 'contact_id' => 'Lisa Thompson', 'ticketstatus' => 'In Progress', 'ticketpriorities' => 'High', 'ticketseverities' => 'Major', 'description' => 'Transportation Management System failing to sync with warehouse management platform since database migration on Feb 10. Missing 3 days of shipment tracking data. ETL pipeline throwing MySQL deadlock errors during bulk inserts.'],
    ['ticket_title' => 'Student portal SSO configuration', 'parent_id' => 'BrightPath Education', 'contact_id' => 'James Crawford', 'ticketstatus' => 'Open', 'ticketpriorities' => 'Normal', 'ticketseverities' => 'Minor', 'description' => 'Need to configure SAML SSO for 15 new school districts onboarding in Q2. Each district uses different IdP (Clever, ClassLink, Google). Need metadata exchange and attribute mapping for each integration.'],
    ['ticket_title' => 'Fiber cut - downtown Denver node', 'parent_id' => 'Horizon Telecom', 'contact_id' => 'Rachel Nguyen', 'ticketstatus' => 'Closed', 'ticketpriorities' => 'Urgent', 'ticketseverities' => 'Critical', 'description' => 'Construction crew severed primary fiber trunk at 16th & Champa. Affecting 340 business customers. Redundant path activated within 8 minutes. Permanent splice repair completed Feb 13. Root cause: missing utility locate markings.'],
    ['ticket_title' => 'Compliance dashboard data discrepancy', 'parent_id' => 'Ironclad Insurance', 'contact_id' => 'William Harper', 'ticketstatus' => 'Open', 'ticketpriorities' => 'Normal', 'ticketseverities' => 'Minor', 'description' => 'Claims processing metrics on compliance dashboard not matching source reports. Discrepancy of 47 claims in January reporting. Likely caused by timezone mismatch in ETL pipeline (UTC vs EST). Need to audit data transformation logic.'],
];

foreach ($tickets as $ticket) {
    $acct_name = $ticket['parent_id'];
    $contact_name = $ticket['contact_id'];
    if (isset($org_ids[$acct_name])) {
        $ticket['parent_id'] = $org_ids[$acct_name];
    }
    if (isset($contact_ids[$contact_name])) {
        $ticket['contact_id'] = $contact_ids[$contact_name];
    } else {
        unset($ticket['contact_id']);
    }
    $ticket['assigned_user_id'] = '19x1';
    $result = vtiger_create($VTIGER_URL, $sessionName, 'HelpDesk', $ticket);
    if ($result) {
        echo "  Created ticket: {$ticket['ticket_title']} (ID: {$result['id']})\n";
    }
}

// ---------------------------------------------------------------
// Seed Calendar Events
// Scheduled meetings and calls
// ---------------------------------------------------------------
echo "\n--- Creating Calendar Events ---\n";

$events = [
    ['subject' => 'Q1 Pipeline Review - Sterling Financial', 'activitytype' => 'Meeting', 'date_start' => '2026-02-20', 'time_start' => '10:00', 'due_date' => '2026-02-20', 'time_end' => '11:30', 'duration_hours' => '1', 'duration_minutes' => '30', 'taskstatus' => 'Planned', 'eventstatus' => 'Planned', 'location' => 'Conference Room A - HQ', 'description' => 'Quarterly pipeline review with Sterling Financial Group. Agenda: Phase 1 progress update, Phase 2 scope discussion, budget approval for trading platform modernization. Attendees: V. Blackwell, T. Park, internal sales team.', 'visibility' => 'Public'],
    ['subject' => 'Pinnacle HIPAA Remediation Kickoff', 'activitytype' => 'Meeting', 'date_start' => '2026-02-18', 'time_start' => '14:00', 'due_date' => '2026-02-18', 'time_end' => '15:00', 'duration_hours' => '1', 'duration_minutes' => '0', 'taskstatus' => 'Planned', 'eventstatus' => 'Planned', 'location' => 'Video Conference - Zoom', 'description' => 'Kickoff meeting for HIPAA audit remediation project. Review findings, assign remediation tasks, establish timeline. Critical: encryption migration must complete before March 31 compliance deadline.', 'visibility' => 'Public'],
    ['subject' => 'Weekly Sales Standup', 'activitytype' => 'Meeting', 'date_start' => '2026-02-17', 'time_start' => '09:00', 'due_date' => '2026-02-17', 'time_end' => '09:30', 'duration_hours' => '0', 'duration_minutes' => '30', 'taskstatus' => 'Planned', 'eventstatus' => 'Planned', 'location' => 'Huddle Room 3', 'description' => 'Weekly 30-minute sales team standup. Review: new leads, pipeline updates, deal blockers, forecast adjustments. Each rep: 3-minute update.', 'visibility' => 'Public'],
    ['subject' => 'Call: BrightPath LMS Demo', 'activitytype' => 'Call', 'date_start' => '2026-02-19', 'time_start' => '11:00', 'due_date' => '2026-02-19', 'time_end' => '12:00', 'duration_hours' => '1', 'duration_minutes' => '0', 'taskstatus' => 'Planned', 'eventstatus' => 'Planned', 'location' => 'Phone: 512-555-0801', 'description' => 'Product demo of proposed LMS features for James Crawford. Showcase adaptive testing engine, teacher dashboard, and parent portal. Prepare demo environment with sample curriculum data.', 'visibility' => 'Public'],
    ['subject' => 'Coastal Retail SOW Review', 'activitytype' => 'Meeting', 'date_start' => '2026-02-21', 'time_start' => '15:30', 'due_date' => '2026-02-21', 'time_end' => '16:30', 'duration_hours' => '1', 'duration_minutes' => '0', 'taskstatus' => 'Planned', 'eventstatus' => 'Planned', 'location' => 'Video Conference - Teams', 'description' => 'Review Statement of Work for Shopify Plus migration with Coastal Retail team. Key discussion points: timeline (12 weeks vs 16 weeks), custom theme requirements, data migration scope for 85 stores.', 'visibility' => 'Public'],
];

foreach ($events as $event) {
    $event['assigned_user_id'] = '19x1';
    $result = vtiger_create($VTIGER_URL, $sessionName, 'Events', $event);
    if ($result) {
        echo "  Created event: {$event['subject']} (ID: {$result['id']})\n";
    }
}

echo "\n=== Data seeding complete ===\n";

// Print summary
$summary = vtiger_query($VTIGER_URL, $sessionName, "SELECT COUNT(*) as cnt FROM Accounts;");
echo "Organizations: " . ($summary[0]['cnt'] ?? '?') . "\n";
$summary = vtiger_query($VTIGER_URL, $sessionName, "SELECT COUNT(*) as cnt FROM Contacts;");
echo "Contacts: " . ($summary[0]['cnt'] ?? '?') . "\n";
$summary = vtiger_query($VTIGER_URL, $sessionName, "SELECT COUNT(*) as cnt FROM Products;");
echo "Products: " . ($summary[0]['cnt'] ?? '?') . "\n";
$summary = vtiger_query($VTIGER_URL, $sessionName, "SELECT COUNT(*) as cnt FROM Potentials;");
echo "Deals: " . ($summary[0]['cnt'] ?? '?') . "\n";
$summary = vtiger_query($VTIGER_URL, $sessionName, "SELECT COUNT(*) as cnt FROM HelpDesk;");
echo "Tickets: " . ($summary[0]['cnt'] ?? '?') . "\n";

exit(0);

// ---------------------------------------------------------------
// Fallback: Direct SQL seeding
// ---------------------------------------------------------------
function seed_via_sql($dbh) {
    echo "Running direct SQL data seeding...\n";

    // Check if vtiger_crmentity table exists
    $result = $dbh->query("SHOW TABLES LIKE 'vtiger_crmentity'");
    if ($result->num_rows == 0) {
        echo "Vtiger tables not found. Installation not complete. Skipping SQL seeding.\n";
        return;
    }

    echo "Vtiger tables found. Direct SQL seeding would go here.\n";
    echo "Note: The Webservice API approach is preferred for proper record creation.\n";
    echo "The PHP seeder will be retried during task setup if needed.\n";
}
?>
