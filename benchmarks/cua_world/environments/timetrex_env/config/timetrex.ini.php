;<?php die('Unauthorized Access...'); //SECURITY MECHANISM, DO NOT REMOVE//?>
;
; TimeTrex Configuration File
;

[path]
base_url = /interface
log = /var/log/timetrex
storage = /var/timetrex/storage
php_cli = /usr/bin/php

[database]
type = postgres
host = postgres
database_name = timetrex
user = timetrex
password = "timetrex"

[mail]
delivery_method = mail

[cache]
enable = TRUE
dir = /tmp/timetrex

[debug]
production = TRUE
enable = FALSE
enable_display = FALSE
buffer_output = TRUE
enable_log = FALSE
verbosity = 10

[other]
force_ssl = FALSE
installer_enabled = TRUE
primary_company_id = 0
hostname = localhost
demo_mode = TRUE
salt = gym_anything_timetrex_salt_2024
