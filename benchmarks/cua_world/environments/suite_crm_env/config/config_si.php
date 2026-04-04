<?php
/**
 * SuiteCRM Silent Install Configuration
 * This file is used by install.php when accessed with ?goto=SilentInstall&cli=true
 */
$sugar_config_si = array(
    'setup_db_host_name' => 'suitecrm-db',
    'setup_db_sugarsales_user' => 'suitecrm',
    'setup_db_sugarsales_password' => 'suitecrm_pass',
    'setup_db_database_name' => 'suitecrm',
    'setup_db_type' => 'mysql',
    'setup_db_port_num' => '3306',
    'setup_db_admin_user_name' => 'root',
    'setup_db_admin_password' => 'root_pass',
    'setup_db_create_database' => 0,
    'setup_db_drop_tables' => 0,
    'setup_db_create_sugarsales_user' => 0,
    'setup_site_url' => 'http://localhost:8000',
    'setup_site_admin_user_name' => 'admin',
    'setup_site_admin_password' => 'Admin1234!',
    'setup_license_accept' => true,
    'setup_site_sugarbeet_automatic_checks' => false,
    'default_currency_iso4217' => 'USD',
    'default_currency_name' => 'US Dollar',
    'default_currency_significant_digits' => '2',
    'default_currency_symbol' => '$',
    'default_date_format' => 'Y-m-d',
    'default_time_format' => 'H:i',
    'default_decimal_seperator' => '.',
    'default_export_charset' => 'UTF-8',
    'default_language' => 'en_us',
    'default_locale_name_format' => 's f l',
    'default_number_grouping_seperator' => ',',
    'export_delimiter' => ',',
    'setup_system_name' => 'SuiteCRM',
    'demoData' => 'no',
);
