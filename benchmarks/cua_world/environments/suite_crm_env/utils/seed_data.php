<?php
/**
 * SuiteCRM data seeder - seeds realistic CRM data using direct database access.
 * Uses real company data from Fortune 500 / major tech companies.
 */
error_reporting(E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT);
set_time_limit(0);
ini_set('memory_limit', '512M');

chdir('/var/www/html');

// Bootstrap SuiteCRM
if (!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');

global $db;

echo "=== SuiteCRM Data Seeder ===\n";

// Helper: create a record via SugarBean
function create_record($module, $fields) {
    global $db;
    $bean = BeanFactory::newBean($module);
    if (!$bean) {
        echo "ERROR: Could not create bean for module $module\n";
        return null;
    }
    foreach ($fields as $k => $v) {
        $bean->$k = $v;
    }
    $bean->save();
    echo "  Created $module: " . ($fields['name'] ?? $fields['first_name'] ?? $fields['last_name'] ?? $bean->id) . " (ID: {$bean->id})\n";
    return $bean->id;
}

// Helper: create relationship
function create_relationship($module, $id, $rel_module, $rel_id, $rel_name) {
    $bean = BeanFactory::getBean($module, $id);
    if ($bean && $bean->load_relationship($rel_name)) {
        $bean->$rel_name->add($rel_id);
    }
}

// ---------------------------------------------------------------
// 1. Seed Accounts (Real Fortune 500 / Tech Companies)
// ---------------------------------------------------------------
echo "\n--- Seeding Accounts ---\n";

$accounts = [
    ['name' => 'Apple Inc.', 'industry' => 'Technology', 'account_type' => 'Customer', 'website' => 'https://www.apple.com', 'phone_office' => '(408) 996-1010', 'billing_address_street' => 'One Apple Park Way', 'billing_address_city' => 'Cupertino', 'billing_address_state' => 'CA', 'billing_address_postalcode' => '95014', 'billing_address_country' => 'USA', 'employees' => '164000', 'annual_revenue' => '383285000000', 'ticker_symbol' => 'AAPL', 'sic_code' => '3571', 'description' => 'Consumer electronics, software and online services multinational.'],
    ['name' => 'Microsoft Corporation', 'industry' => 'Technology', 'account_type' => 'Customer', 'website' => 'https://www.microsoft.com', 'phone_office' => '(425) 882-8080', 'billing_address_street' => 'One Microsoft Way', 'billing_address_city' => 'Redmond', 'billing_address_state' => 'WA', 'billing_address_postalcode' => '98052', 'billing_address_country' => 'USA', 'employees' => '228000', 'annual_revenue' => '245122000000', 'ticker_symbol' => 'MSFT', 'sic_code' => '7372', 'description' => 'Enterprise software, cloud computing, and AI services.'],
    ['name' => 'Alphabet Inc.', 'industry' => 'Technology', 'account_type' => 'Customer', 'website' => 'https://www.abc.xyz', 'phone_office' => '(650) 253-0000', 'billing_address_street' => '1600 Amphitheatre Parkway', 'billing_address_city' => 'Mountain View', 'billing_address_state' => 'CA', 'billing_address_postalcode' => '94043', 'billing_address_country' => 'USA', 'employees' => '182502', 'annual_revenue' => '307394000000', 'ticker_symbol' => 'GOOGL', 'sic_code' => '7372', 'description' => 'Internet services, search, advertising, and cloud platform.'],
    ['name' => 'Amazon.com Inc.', 'industry' => 'Retail', 'account_type' => 'Customer', 'website' => 'https://www.amazon.com', 'phone_office' => '(206) 266-1000', 'billing_address_street' => '410 Terry Avenue North', 'billing_address_city' => 'Seattle', 'billing_address_state' => 'WA', 'billing_address_postalcode' => '98109', 'billing_address_country' => 'USA', 'employees' => '1525000', 'annual_revenue' => '574785000000', 'ticker_symbol' => 'AMZN', 'sic_code' => '5961', 'description' => 'E-commerce, cloud computing (AWS), and digital streaming.'],
    ['name' => 'Meta Platforms Inc.', 'industry' => 'Technology', 'account_type' => 'Prospect', 'website' => 'https://www.meta.com', 'phone_office' => '(650) 543-4800', 'billing_address_street' => '1 Hacker Way', 'billing_address_city' => 'Menlo Park', 'billing_address_state' => 'CA', 'billing_address_postalcode' => '94025', 'billing_address_country' => 'USA', 'employees' => '67317', 'annual_revenue' => '134902000000', 'ticker_symbol' => 'META', 'sic_code' => '7372', 'description' => 'Social media, virtual reality, and advertising technology.'],
    ['name' => 'NVIDIA Corporation', 'industry' => 'Electronics', 'account_type' => 'Customer', 'website' => 'https://www.nvidia.com', 'phone_office' => '(408) 486-2000', 'billing_address_street' => '2788 San Tomas Expressway', 'billing_address_city' => 'Santa Clara', 'billing_address_state' => 'CA', 'billing_address_postalcode' => '95051', 'billing_address_country' => 'USA', 'employees' => '29600', 'annual_revenue' => '60922000000', 'ticker_symbol' => 'NVDA', 'sic_code' => '3674', 'description' => 'GPU computing, AI chips, and data center accelerators.'],
    ['name' => 'Tesla Inc.', 'industry' => 'Manufacturing', 'account_type' => 'Customer', 'website' => 'https://www.tesla.com', 'phone_office' => '(512) 516-8177', 'billing_address_street' => '1 Tesla Road', 'billing_address_city' => 'Austin', 'billing_address_state' => 'TX', 'billing_address_postalcode' => '78725', 'billing_address_country' => 'USA', 'employees' => '140473', 'annual_revenue' => '96773000000', 'ticker_symbol' => 'TSLA', 'sic_code' => '3711', 'description' => 'Electric vehicles, energy storage, and solar technology.'],
    ['name' => 'Salesforce Inc.', 'industry' => 'Technology', 'account_type' => 'Competitor', 'website' => 'https://www.salesforce.com', 'phone_office' => '(415) 901-7000', 'billing_address_street' => 'Salesforce Tower, 415 Mission Street', 'billing_address_city' => 'San Francisco', 'billing_address_state' => 'CA', 'billing_address_postalcode' => '94105', 'billing_address_country' => 'USA', 'employees' => '79390', 'annual_revenue' => '34857000000', 'ticker_symbol' => 'CRM', 'sic_code' => '7372', 'description' => 'Cloud-based CRM platform and enterprise SaaS applications.'],
    ['name' => 'JPMorgan Chase & Co.', 'industry' => 'Banking', 'account_type' => 'Customer', 'website' => 'https://www.jpmorganchase.com', 'phone_office' => '(212) 270-6000', 'billing_address_street' => '383 Madison Avenue', 'billing_address_city' => 'New York', 'billing_address_state' => 'NY', 'billing_address_postalcode' => '10179', 'billing_address_country' => 'USA', 'employees' => '309926', 'annual_revenue' => '177600000000', 'ticker_symbol' => 'JPM', 'sic_code' => '6020', 'description' => 'Global financial services, investment banking, and asset management.'],
    ['name' => 'Goldman Sachs Group Inc.', 'industry' => 'Finance', 'account_type' => 'Customer', 'website' => 'https://www.goldmansachs.com', 'phone_office' => '(212) 902-1000', 'billing_address_street' => '200 West Street', 'billing_address_city' => 'New York', 'billing_address_state' => 'NY', 'billing_address_postalcode' => '10282', 'billing_address_country' => 'USA', 'employees' => '49100', 'annual_revenue' => '46254000000', 'ticker_symbol' => 'GS', 'sic_code' => '6211', 'description' => 'Investment banking, securities, and investment management.'],
    ['name' => 'Johnson & Johnson', 'industry' => 'Healthcare', 'account_type' => 'Customer', 'website' => 'https://www.jnj.com', 'phone_office' => '(732) 524-0400', 'billing_address_street' => 'One Johnson & Johnson Plaza', 'billing_address_city' => 'New Brunswick', 'billing_address_state' => 'NJ', 'billing_address_postalcode' => '08933', 'billing_address_country' => 'USA', 'employees' => '131900', 'annual_revenue' => '85159000000', 'ticker_symbol' => 'JNJ', 'sic_code' => '2834', 'description' => 'Pharmaceuticals, medical devices, and consumer health products.'],
    ['name' => 'Boeing Company', 'industry' => 'Manufacturing', 'account_type' => 'Customer', 'website' => 'https://www.boeing.com', 'phone_office' => '(703) 465-3500', 'billing_address_street' => '929 Long Bridge Drive', 'billing_address_city' => 'Arlington', 'billing_address_state' => 'VA', 'billing_address_postalcode' => '22202', 'billing_address_country' => 'USA', 'employees' => '171000', 'annual_revenue' => '77794000000', 'ticker_symbol' => 'BA', 'sic_code' => '3721', 'description' => 'Aerospace, defense, and commercial aviation.'],
    ['name' => 'Cisco Systems Inc.', 'industry' => 'Technology', 'account_type' => 'Customer', 'website' => 'https://www.cisco.com', 'phone_office' => '(408) 526-4000', 'billing_address_street' => '170 West Tasman Drive', 'billing_address_city' => 'San Jose', 'billing_address_state' => 'CA', 'billing_address_postalcode' => '95134', 'billing_address_country' => 'USA', 'employees' => '90400', 'annual_revenue' => '53803000000', 'ticker_symbol' => 'CSCO', 'sic_code' => '3577', 'description' => 'Networking hardware, software, and cybersecurity.'],
    ['name' => 'Adobe Inc.', 'industry' => 'Technology', 'account_type' => 'Partner', 'website' => 'https://www.adobe.com', 'phone_office' => '(408) 536-6000', 'billing_address_street' => '345 Park Avenue', 'billing_address_city' => 'San Jose', 'billing_address_state' => 'CA', 'billing_address_postalcode' => '95110', 'billing_address_country' => 'USA', 'employees' => '30000', 'annual_revenue' => '19409000000', 'ticker_symbol' => 'ADBE', 'sic_code' => '7372', 'description' => 'Creative software, digital marketing, and document management.'],
    ['name' => 'Walmart Inc.', 'industry' => 'Retail', 'account_type' => 'Customer', 'website' => 'https://www.walmart.com', 'phone_office' => '(479) 273-4000', 'billing_address_street' => '702 SW 8th Street', 'billing_address_city' => 'Bentonville', 'billing_address_state' => 'AR', 'billing_address_postalcode' => '72716', 'billing_address_country' => 'USA', 'employees' => '2100000', 'annual_revenue' => '648125000000', 'ticker_symbol' => 'WMT', 'sic_code' => '5311', 'description' => 'Multinational retail corporation and e-commerce leader.'],
    ['name' => 'AT&T Inc.', 'industry' => 'Telecommunications', 'account_type' => 'Customer', 'website' => 'https://www.att.com', 'phone_office' => '(210) 821-4105', 'billing_address_street' => '208 S. Akard Street', 'billing_address_city' => 'Dallas', 'billing_address_state' => 'TX', 'billing_address_postalcode' => '75202', 'billing_address_country' => 'USA', 'employees' => '150000', 'annual_revenue' => '122428000000', 'ticker_symbol' => 'T', 'sic_code' => '4813', 'description' => 'Telecommunications, media, and technology conglomerate.'],
    ['name' => 'Accenture plc', 'industry' => 'Consulting', 'account_type' => 'Partner', 'website' => 'https://www.accenture.com', 'phone_office' => '+353 1 646 2000', 'billing_address_street' => '1 Grand Canal Square', 'billing_address_city' => 'Dublin', 'billing_address_state' => 'Leinster', 'billing_address_postalcode' => 'D02 P820', 'billing_address_country' => 'Ireland', 'employees' => '743000', 'annual_revenue' => '64112000000', 'ticker_symbol' => 'ACN', 'sic_code' => '7371', 'description' => 'Professional services and IT consulting.'],
    ['name' => 'ExxonMobil Corporation', 'industry' => 'Energy', 'account_type' => 'Prospect', 'website' => 'https://www.exxonmobil.com', 'phone_office' => '(972) 940-6000', 'billing_address_street' => '22777 Springwoods Village Parkway', 'billing_address_city' => 'Spring', 'billing_address_state' => 'TX', 'billing_address_postalcode' => '77389', 'billing_address_country' => 'USA', 'employees' => '62000', 'annual_revenue' => '344582000000', 'ticker_symbol' => 'XOM', 'sic_code' => '2911', 'description' => 'Petroleum refining, natural gas, and petrochemicals.'],
    ['name' => 'General Electric Company', 'industry' => 'Engineering', 'account_type' => 'Customer', 'website' => 'https://www.ge.com', 'phone_office' => '(617) 443-3000', 'billing_address_street' => '1 Neumann Way', 'billing_address_city' => 'Evendale', 'billing_address_state' => 'OH', 'billing_address_postalcode' => '45215', 'billing_address_country' => 'USA', 'employees' => '125000', 'annual_revenue' => '67954000000', 'ticker_symbol' => 'GE', 'sic_code' => '3511', 'description' => 'Aviation, power, renewable energy, and healthcare technology.'],
    ['name' => 'Deloitte LLP', 'industry' => 'Consulting', 'account_type' => 'Partner', 'website' => 'https://www.deloitte.com', 'phone_office' => '(212) 489-1600', 'billing_address_street' => '30 Rockefeller Plaza', 'billing_address_city' => 'New York', 'billing_address_state' => 'NY', 'billing_address_postalcode' => '10112', 'billing_address_country' => 'USA', 'employees' => '457000', 'annual_revenue' => '67200000000', 'description' => 'Audit, consulting, tax, and advisory services.'],
];

$account_ids = [];
foreach ($accounts as $acct) {
    $id = create_record('Accounts', $acct);
    if ($id) $account_ids[$acct['name']] = $id;
}
echo "Accounts created: " . count($account_ids) . "\n";

// ---------------------------------------------------------------
// 2. Seed Contacts
// ---------------------------------------------------------------
echo "\n--- Seeding Contacts ---\n";

$contacts = [
    ['salutation' => 'Mr.', 'first_name' => 'James', 'last_name' => 'Chen', 'title' => 'VP of Engineering', 'department' => 'Engineering', 'account_name' => 'Apple Inc.', 'phone_work' => '(408) 996-1011', 'email1' => 'j.chen@apple.com', 'lead_source' => 'Trade Show'],
    ['salutation' => 'Ms.', 'first_name' => 'Sarah', 'last_name' => 'Williams', 'title' => 'Director of Procurement', 'department' => 'Procurement', 'account_name' => 'Apple Inc.', 'phone_work' => '(408) 996-1025', 'email1' => 's.williams@apple.com', 'lead_source' => 'Existing Customer'],
    ['salutation' => 'Mr.', 'first_name' => 'David', 'last_name' => 'Patel', 'title' => 'Chief Technology Officer', 'department' => 'Technology', 'account_name' => 'Microsoft Corporation', 'phone_work' => '(425) 882-8081', 'email1' => 'd.patel@microsoft.com', 'lead_source' => 'Conference'],
    ['salutation' => 'Dr.', 'first_name' => 'Emily', 'last_name' => 'Rodriguez', 'title' => 'Senior Program Manager', 'department' => 'Azure Platform', 'account_name' => 'Microsoft Corporation', 'phone_work' => '(425) 882-8090', 'email1' => 'e.rodriguez@microsoft.com', 'lead_source' => 'Web Site'],
    ['salutation' => 'Ms.', 'first_name' => 'Lisa', 'last_name' => 'Thompson', 'title' => 'Head of Vendor Relations', 'department' => 'Operations', 'account_name' => 'Amazon.com Inc.', 'phone_work' => '(206) 266-1050', 'email1' => 'l.thompson@amazon.com', 'lead_source' => 'Partner'],
    ['salutation' => 'Mr.', 'first_name' => 'Michael', 'last_name' => 'O\'Brien', 'title' => 'Solutions Architect', 'department' => 'AWS', 'account_name' => 'Amazon.com Inc.', 'phone_work' => '(206) 266-2000', 'email1' => 'm.obrien@amazon.com', 'lead_source' => 'Cold Call'],
    ['salutation' => 'Ms.', 'first_name' => 'Catherine', 'last_name' => 'Park', 'title' => 'Managing Director', 'department' => 'Investment Banking', 'account_name' => 'JPMorgan Chase & Co.', 'phone_work' => '(212) 270-6050', 'email1' => 'c.park@jpmorgan.com', 'lead_source' => 'Conference'],
    ['salutation' => 'Mr.', 'first_name' => 'Robert', 'last_name' => 'Martinez', 'title' => 'VP of IT Infrastructure', 'department' => 'Technology', 'account_name' => 'JPMorgan Chase & Co.', 'phone_work' => '(212) 270-7000', 'email1' => 'r.martinez@jpmorgan.com', 'lead_source' => 'Existing Customer'],
    ['salutation' => 'Mr.', 'first_name' => 'Kevin', 'last_name' => 'Zhang', 'title' => 'Director of AI Research', 'department' => 'Research', 'account_name' => 'NVIDIA Corporation', 'phone_work' => '(408) 486-2010', 'email1' => 'k.zhang@nvidia.com', 'lead_source' => 'Trade Show'],
    ['salutation' => 'Ms.', 'first_name' => 'Priya', 'last_name' => 'Sharma', 'title' => 'Procurement Manager', 'department' => 'Procurement', 'account_name' => 'NVIDIA Corporation', 'phone_work' => '(408) 486-2050', 'email1' => 'p.sharma@nvidia.com', 'lead_source' => 'Cold Call'],
    ['salutation' => 'Mr.', 'first_name' => 'Andrew', 'last_name' => 'Kim', 'title' => 'Head of Manufacturing Systems', 'department' => 'Manufacturing', 'account_name' => 'Tesla Inc.', 'phone_work' => '(512) 516-8200', 'email1' => 'a.kim@tesla.com', 'lead_source' => 'Web Site'],
    ['salutation' => 'Ms.', 'first_name' => 'Jennifer', 'last_name' => 'Davis', 'title' => 'VP of Platform Engineering', 'department' => 'Engineering', 'account_name' => 'Salesforce Inc.', 'phone_work' => '(415) 901-7050', 'email1' => 'j.davis@salesforce.com', 'lead_source' => 'Conference'],
    ['salutation' => 'Mr.', 'first_name' => 'Thomas', 'last_name' => 'Anderson', 'title' => 'Director of Supply Chain', 'department' => 'Supply Chain', 'account_name' => 'Boeing Company', 'phone_work' => '(703) 465-3550', 'email1' => 't.anderson@boeing.com', 'lead_source' => 'Trade Show'],
    ['salutation' => 'Ms.', 'first_name' => 'Maria', 'last_name' => 'Gonzalez', 'title' => 'Network Architecture Lead', 'department' => 'Engineering', 'account_name' => 'Cisco Systems Inc.', 'phone_work' => '(408) 526-4050', 'email1' => 'm.gonzalez@cisco.com', 'lead_source' => 'Partner'],
    ['salutation' => 'Mr.', 'first_name' => 'William', 'last_name' => 'Foster', 'title' => 'CIO', 'department' => 'Technology', 'account_name' => 'Goldman Sachs Group Inc.', 'phone_work' => '(212) 902-1050', 'email1' => 'w.foster@gs.com', 'lead_source' => 'Direct Mail'],
    ['salutation' => 'Ms.', 'first_name' => 'Angela', 'last_name' => 'Wright', 'title' => 'VP of Digital Commerce', 'department' => 'eCommerce', 'account_name' => 'Walmart Inc.', 'phone_work' => '(479) 273-4100', 'email1' => 'a.wright@walmart.com', 'lead_source' => 'Conference'],
    ['salutation' => 'Dr.', 'first_name' => 'Daniel', 'last_name' => 'Lee', 'title' => 'VP of Clinical Operations', 'department' => 'R&D', 'account_name' => 'Johnson & Johnson', 'phone_work' => '(732) 524-0450', 'email1' => 'd.lee@jnj.com', 'lead_source' => 'Trade Show'],
    ['salutation' => 'Mr.', 'first_name' => 'Christopher', 'last_name' => 'Brown', 'title' => 'Director of Enterprise Solutions', 'department' => 'Business Solutions', 'account_name' => 'AT&T Inc.', 'phone_work' => '(210) 821-4200', 'email1' => 'c.brown@att.com', 'lead_source' => 'Existing Customer'],
    ['salutation' => 'Ms.', 'first_name' => 'Rachel', 'last_name' => 'Taylor', 'title' => 'Managing Director, Technology', 'department' => 'Technology Consulting', 'account_name' => 'Accenture plc', 'phone_work' => '+353 1 646 2100', 'email1' => 'r.taylor@accenture.com', 'lead_source' => 'Partner'],
    ['salutation' => 'Mr.', 'first_name' => 'Nathan', 'last_name' => 'Singh', 'title' => 'Senior Product Manager', 'department' => 'Creative Cloud', 'account_name' => 'Adobe Inc.', 'phone_work' => '(408) 536-6050', 'email1' => 'n.singh@adobe.com', 'lead_source' => 'Web Site'],
];

$contact_ids = [];
foreach ($contacts as $contact) {
    $acct_name = $contact['account_name'];
    unset($contact['account_name']);
    if (isset($account_ids[$acct_name])) {
        $contact['account_id'] = $account_ids[$acct_name];
    }
    $id = create_record('Contacts', $contact);
    if ($id) $contact_ids[$contact['first_name'] . ' ' . $contact['last_name']] = $id;
}
echo "Contacts created: " . count($contact_ids) . "\n";

// ---------------------------------------------------------------
// 3. Seed Opportunities
// ---------------------------------------------------------------
echo "\n--- Seeding Opportunities ---\n";

$opportunities = [
    ['name' => 'Apple - Enterprise Data Platform License', 'account_name' => 'Apple Inc.', 'amount' => '2500000', 'sales_stage' => 'Closed Won', 'probability' => '100', 'date_closed' => '2025-03-15', 'lead_source' => 'Trade Show', 'description' => 'Annual enterprise data platform license renewal with 3-year commitment.'],
    ['name' => 'Microsoft - Cloud Migration Services', 'account_name' => 'Microsoft Corporation', 'amount' => '1800000', 'sales_stage' => 'Closed Won', 'probability' => '100', 'date_closed' => '2025-01-22', 'lead_source' => 'Existing Customer', 'description' => 'Professional services engagement for Azure migration project.'],
    ['name' => 'Walmart - POS Integration Suite', 'account_name' => 'Walmart Inc.', 'amount' => '4200000', 'sales_stage' => 'Closed Won', 'probability' => '100', 'date_closed' => '2025-06-10', 'lead_source' => 'Conference', 'description' => 'Point-of-sale integration across 500 retail locations.'],
    ['name' => 'Boeing - Supply Chain Analytics Platform', 'account_name' => 'Boeing Company', 'amount' => '3100000', 'sales_stage' => 'Closed Won', 'probability' => '100', 'date_closed' => '2024-11-30', 'lead_source' => 'Trade Show', 'description' => 'Real-time supply chain visibility and predictive analytics solution.'],
    ['name' => 'JPMorgan - Fraud Detection AI Module', 'account_name' => 'JPMorgan Chase & Co.', 'amount' => '5500000', 'sales_stage' => 'Negotiation/Review', 'probability' => '80', 'date_closed' => '2026-04-30', 'lead_source' => 'Conference', 'description' => 'ML-powered fraud detection system for consumer banking division.'],
    ['name' => 'Cisco - Network Monitoring Expansion', 'account_name' => 'Cisco Systems Inc.', 'amount' => '890000', 'sales_stage' => 'Proposal/Price Quote', 'probability' => '65', 'date_closed' => '2026-03-15', 'lead_source' => 'Existing Customer', 'description' => 'Expansion of network monitoring to APAC data centers.'],
    ['name' => 'Goldman Sachs - Compliance Dashboard', 'account_name' => 'Goldman Sachs Group Inc.', 'amount' => '1200000', 'sales_stage' => 'Negotiation/Review', 'probability' => '80', 'date_closed' => '2026-05-01', 'lead_source' => 'Direct Mail', 'description' => 'Regulatory compliance reporting and dashboard solution.'],
    ['name' => 'NVIDIA - GPU Cluster Management Platform', 'account_name' => 'NVIDIA Corporation', 'amount' => '750000', 'sales_stage' => 'Proposal/Price Quote', 'probability' => '65', 'date_closed' => '2026-06-30', 'lead_source' => 'Trade Show', 'description' => 'Cluster orchestration platform for DGX SuperPOD deployments.'],
    ['name' => 'AT&T - Customer Experience Analytics', 'account_name' => 'AT&T Inc.', 'amount' => '2100000', 'sales_stage' => 'Value Proposition', 'probability' => '30', 'date_closed' => '2026-08-15', 'lead_source' => 'Existing Customer', 'description' => 'Customer journey analytics platform for wireless division.'],
    ['name' => 'Tesla - Manufacturing Execution System', 'account_name' => 'Tesla Inc.', 'amount' => '3800000', 'sales_stage' => 'Needs Analysis', 'probability' => '25', 'date_closed' => '2026-09-30', 'lead_source' => 'Web Site', 'description' => 'Next-gen MES for Gigafactory production line optimization.'],
    ['name' => 'Johnson & Johnson - Clinical Trial Mgmt', 'account_name' => 'Johnson & Johnson', 'amount' => '1650000', 'sales_stage' => 'Id. Decision Makers', 'probability' => '40', 'date_closed' => '2026-07-15', 'lead_source' => 'Trade Show', 'description' => 'Cloud-based CTMS for Phase III oncology trials.'],
    ['name' => 'ExxonMobil - IoT Sensor Analytics', 'account_name' => 'ExxonMobil Corporation', 'amount' => '2900000', 'sales_stage' => 'Prospecting', 'probability' => '10', 'date_closed' => '2026-12-31', 'lead_source' => 'Cold Call', 'description' => 'Predictive maintenance using IoT sensor data from refineries.'],
    ['name' => 'Meta - Content Moderation Tooling', 'account_name' => 'Meta Platforms Inc.', 'amount' => '3200000', 'sales_stage' => 'Closed Lost', 'probability' => '0', 'date_closed' => '2025-09-15', 'lead_source' => 'Conference', 'description' => 'AI-assisted content moderation workflow platform - lost to internal build.'],
    ['name' => 'Amazon - Warehouse Robotics Interface', 'account_name' => 'Amazon.com Inc.', 'amount' => '4500000', 'sales_stage' => 'Closed Lost', 'probability' => '0', 'date_closed' => '2025-07-20', 'lead_source' => 'Partner', 'description' => 'Robotics fleet management for fulfillment centers - lost to competitor.'],
];

$opp_ids = [];
foreach ($opportunities as $opp) {
    $acct_name = $opp['account_name'];
    unset($opp['account_name']);
    if (isset($account_ids[$acct_name])) {
        $opp['account_id'] = $account_ids[$acct_name];
    }
    $id = create_record('Opportunities', $opp);
    if ($id) $opp_ids[$opp['name']] = $id;
}
echo "Opportunities created: " . count($opp_ids) . "\n";

// ---------------------------------------------------------------
// 4. Seed Cases (Support Tickets)
// ---------------------------------------------------------------
echo "\n--- Seeding Cases ---\n";

$cases = [
    ['name' => 'API rate limiting causing data sync failures', 'account_name' => 'Apple Inc.', 'status' => 'Open_New', 'priority' => 'P1', 'type' => 'Product', 'description' => 'Since the v3.2 update, our nightly data sync jobs are hitting 429 rate limit errors after approximately 10,000 API calls. Previous limit was 50,000/hour. Sync window is 2am-6am EST. This is blocking our daily reporting pipeline.'],
    ['name' => 'Dashboard export PDF formatting broken', 'account_name' => 'Microsoft Corporation', 'status' => 'Open_Assigned', 'priority' => 'P2', 'type' => 'Product', 'description' => 'When exporting quarterly revenue dashboard to PDF, charts are overlapping with tables. Works fine in browser. Affects Chrome and Edge.'],
    ['name' => 'SSO integration returning 503 errors', 'account_name' => 'JPMorgan Chase & Co.', 'status' => 'Open_New', 'priority' => 'P1', 'type' => 'Product', 'description' => 'SAML SSO integration with Okta is intermittently returning 503 errors. Approximately 15% of login attempts fail. Started after Okta tenant upgrade to version 2024.09. 800+ users affected.'],
    ['name' => 'Custom report query timeout on large datasets', 'account_name' => 'Walmart Inc.', 'status' => 'Open_Assigned', 'priority' => 'P2', 'type' => 'Product', 'description' => 'Custom reports with date ranges exceeding 90 days are timing out at the 30-second mark. Dataset contains 2.3M transaction records. Need query optimization or configurable timeout.'],
    ['name' => 'Mobile app crashes on iOS 18 devices', 'account_name' => 'Cisco Systems Inc.', 'status' => 'Open_New', 'priority' => 'P1', 'type' => 'Product', 'description' => 'Mobile companion app crashes immediately on launch for users running iOS 18.2. Crash logs show null pointer exception in authentication module. Approximately 200 field engineers affected.'],
    ['name' => 'Bulk user import failing at row 127', 'account_name' => 'Accenture plc', 'status' => 'Open_Assigned', 'priority' => 'P2', 'type' => 'User', 'description' => 'Attempting to bulk import 350 new consultant users via CSV. Import fails at row 127 with duplicate email error, but the email is not a duplicate. Suspect encoding issue with international characters.'],
    ['name' => 'Permission escalation after role change', 'account_name' => 'Goldman Sachs Group Inc.', 'status' => 'Open_New', 'priority' => 'P1', 'type' => 'Administration', 'description' => 'After changing user from Analyst to Associate role, user retains old permissions AND gains new ones instead of replacing. Potential compliance concern as user can access restricted trading data.'],
    ['name' => 'Custom field request - Security Clearance', 'account_name' => 'Boeing Company', 'status' => 'Closed', 'priority' => 'P3', 'type' => 'Administration', 'description' => 'Need to add Security Clearance Level dropdown to contact records. Values: Unclassified, Confidential, Secret, Top Secret. Required for defense contract compliance.'],
    ['name' => 'Email template rendering issues in Outlook', 'account_name' => 'AT&T Inc.', 'status' => 'Open_Assigned', 'priority' => 'P2', 'type' => 'Product', 'description' => 'HTML email templates sent from platform render correctly in Gmail and Apple Mail but display broken formatting in Outlook 365. Tables lose styling and images misaligned.'],
    ['name' => 'GDPR data export request', 'account_name' => 'Deloitte LLP', 'status' => 'Closed', 'priority' => 'P2', 'type' => 'Administration', 'description' => 'Full data export for 3 EU-based contacts per GDPR Article 15 right of access request. Need all stored PII in machine-readable format.'],
    ['name' => 'Webhook delivery delays for deal changes', 'account_name' => 'Tesla Inc.', 'status' => 'Open_Assigned', 'priority' => 'P2', 'type' => 'Product', 'description' => 'Webhook notifications for deal stage changes delayed by 15-45 minutes. Expected under 30 seconds. Impacting automated provisioning workflow for manufacturing orders.'],
    ['name' => 'Training request - advanced reporting', 'account_name' => 'Johnson & Johnson', 'status' => 'Closed', 'priority' => 'P3', 'type' => 'User', 'description' => 'Requesting 4-hour training session for 12 clinical ops staff on advanced reporting features including cross-object reports, scheduled delivery, and custom formula fields.'],
];

$case_ids = [];
foreach ($cases as $case_data) {
    $acct_name = $case_data['account_name'];
    unset($case_data['account_name']);
    if (isset($account_ids[$acct_name])) {
        $case_data['account_id'] = $account_ids[$acct_name];
    }
    $id = create_record('Cases', $case_data);
    if ($id) $case_ids[$case_data['name']] = $id;
}
echo "Cases created: " . count($case_ids) . "\n";

// ---------------------------------------------------------------
// 5. Seed Meetings
// ---------------------------------------------------------------
echo "\n--- Seeding Meetings ---\n";

$meetings = [
    ['name' => 'Executive Sponsor Dinner - JPMorgan Deal', 'status' => 'Held', 'duration_hours' => '2', 'duration_minutes' => '0', 'date_start' => '2026-01-28 18:30:00', 'location' => 'Eleven Madison Park, 11 Madison Ave, New York, NY', 'description' => 'Executive dinner with Catherine Park and CFO. Discussed strategic partnership vision and multi-year commitment framework.'],
    ['name' => 'Quarterly Business Review - Walmart', 'status' => 'Planned', 'duration_hours' => '2', 'duration_minutes' => '0', 'date_start' => '2026-03-05 09:00:00', 'location' => 'Walmart Home Office, 702 SW 8th St, Bentonville, AR', 'description' => 'Q1 QBR covering: system uptime (99.97%), active users (12,450), support ticket resolution metrics, and expansion into Sam\'s Club locations.'],
    ['name' => 'Technical Deep Dive - Tesla MES Requirements', 'status' => 'Planned', 'duration_hours' => '3', 'duration_minutes' => '0', 'date_start' => '2026-03-10 10:00:00', 'location' => 'Tesla Gigafactory, 1 Tesla Road, Austin, TX', 'description' => 'On-site technical workshop for MES requirements. 4 from our team, 8 from Tesla manufacturing engineering. Focus on real-time production tracking and quality control.'],
    ['name' => 'Partner Enablement Workshop - Accenture', 'status' => 'Held', 'duration_hours' => '4', 'duration_minutes' => '0', 'date_start' => '2026-01-15 09:00:00', 'location' => 'Virtual - Microsoft Teams', 'description' => 'Full-day workshop for 25 Accenture consultants on implementation methodology, API integration patterns, and certification prep.'],
    ['name' => 'Compliance Review - Goldman Sachs Dashboard', 'status' => 'Planned', 'duration_hours' => '1', 'duration_minutes' => '30', 'date_start' => '2026-03-12 14:00:00', 'location' => '200 West Street, New York, NY - 28th Floor', 'description' => 'Review compliance dashboard mockups with GS legal and compliance team. Must meet SEC reporting and MiFID II transparency obligations.'],
    ['name' => 'Annual Contract Negotiation - Apple', 'status' => 'Planned', 'duration_hours' => '2', 'duration_minutes' => '0', 'date_start' => '2026-03-20 10:00:00', 'location' => 'Apple Park, Cupertino, CA - Visitor Center', 'description' => 'Annual contract renewal negotiation. Volume pricing for FY2027, SLA adjustments, new module licensing, and professional services retainer.'],
    ['name' => 'User Group Meetup - Healthcare Vertical', 'status' => 'Held', 'duration_hours' => '3', 'duration_minutes' => '0', 'date_start' => '2026-02-05 13:00:00', 'location' => 'Marriott Marquis, 1535 Broadway, New York, NY', 'description' => 'Quarterly user group for healthcare customers. Attendees from J&J, UnitedHealth, and 6 other pharma/insurance accounts. Case study presentation and product roadmap preview.'],
];

foreach ($meetings as $meeting) {
    // Set date_end based on duration
    $start = new DateTime($meeting['date_start']);
    $start->add(new DateInterval("PT{$meeting['duration_hours']}H{$meeting['duration_minutes']}M"));
    $meeting['date_end'] = $start->format('Y-m-d H:i:s');
    create_record('Meetings', $meeting);
}

// ---------------------------------------------------------------
// 6. Seed Calls
// ---------------------------------------------------------------
echo "\n--- Seeding Calls ---\n";

$calls = [
    ['name' => 'Q1 License Renewal Discussion', 'direction' => 'Outbound', 'status' => 'Held', 'duration_hours' => '0', 'duration_minutes' => '45', 'date_start' => '2026-01-15 10:00:00', 'description' => 'Discussed Q1 license renewal terms with procurement. They want 15% volume discount for 3-year commit. Need to run numbers with finance.'],
    ['name' => 'Technical Architecture Review', 'direction' => 'Inbound', 'status' => 'Held', 'duration_hours' => '1', 'duration_minutes' => '0', 'date_start' => '2026-01-20 14:30:00', 'description' => 'David Patel called to discuss Azure migration integration architecture. Needs REST API documentation and sandbox access.'],
    ['name' => 'Fraud Detection POC Feedback', 'direction' => 'Outbound', 'status' => 'Held', 'duration_hours' => '0', 'duration_minutes' => '30', 'date_start' => '2026-02-03 11:00:00', 'description' => 'Catherine Park provided positive feedback on POC results. 94% detection accuracy exceeded 90% threshold. Scheduling executive demo for Feb 15.'],
    ['name' => 'Support Escalation - SSO Outage', 'direction' => 'Inbound', 'status' => 'Held', 'duration_hours' => '0', 'duration_minutes' => '20', 'date_start' => '2026-02-10 08:15:00', 'description' => 'Urgent call from Robert Martinez re: SSO failures affecting 800+ users. Escalated to engineering. Promised status update within 2 hours.'],
    ['name' => 'Cold Call - ExxonMobil IoT Initiative', 'direction' => 'Outbound', 'status' => 'Held', 'duration_hours' => '0', 'duration_minutes' => '15', 'date_start' => '2026-02-12 09:00:00', 'description' => 'Initial outreach to refinery operations director. Interested in predictive maintenance. Sending capabilities deck and case study.'],
    ['name' => 'Follow-up: Network Monitoring Pricing', 'direction' => 'Outbound', 'status' => 'Planned', 'duration_hours' => '0', 'duration_minutes' => '30', 'date_start' => '2026-02-20 15:00:00', 'description' => 'Scheduled call with Maria Gonzalez to review revised pricing for APAC expansion. Need to confirm 3-year vs 5-year pricing tiers.'],
    ['name' => 'Quarterly Business Review Prep', 'direction' => 'Outbound', 'status' => 'Planned', 'duration_hours' => '0', 'duration_minutes' => '45', 'date_start' => '2026-02-25 10:00:00', 'description' => 'Pre-QBR call with Angela Wright to align on metrics, success stories, and expansion roadmap before formal QBR on March 5.'],
    ['name' => 'Product Demo - Clinical Trial Management', 'direction' => 'Outbound', 'status' => 'Planned', 'duration_hours' => '1', 'duration_minutes' => '0', 'date_start' => '2026-03-01 13:00:00', 'description' => 'Full product demonstration for J&J clinical ops team. Focus on Phase III trial workflows, randomization module, and regulatory reporting.'],
];

foreach ($calls as $call) {
    $start = new DateTime($call['date_start']);
    $start->add(new DateInterval("PT{$call['duration_hours']}H{$call['duration_minutes']}M"));
    $call['date_end'] = $start->format('Y-m-d H:i:s');
    create_record('Calls', $call);
}

// ---------------------------------------------------------------
// Summary
// ---------------------------------------------------------------
echo "\n=== Data Seeding Complete ===\n";
echo "Accounts: " . count($account_ids) . "\n";
echo "Contacts: " . count($contact_ids) . "\n";
echo "Opportunities: " . count($opp_ids) . "\n";
echo "Cases: " . count($case_ids) . "\n";
echo "Meetings: " . count($meetings) . "\n";
echo "Calls: " . count($calls) . "\n";
?>
