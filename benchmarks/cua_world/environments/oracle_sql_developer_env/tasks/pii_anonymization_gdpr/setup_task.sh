#!/bin/bash
echo "=== Setting up PII Anonymization GDPR Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# Clean up previous run artifacts
echo "Cleaning up previous runs..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER gdpr_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# Create GDPR_ADMIN user
echo "Creating GDPR_ADMIN schema..."
oracle_query "CREATE USER gdpr_admin IDENTIFIED BY Gdpr2024
  DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE PROCEDURE, CREATE TABLE TO gdpr_admin;
EXIT;" "system"

# Create and populate tables
echo "Populating schema with realistic European data..."
sudo docker exec -i oracle-xe sqlplus -s gdpr_admin/Gdpr2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

CREATE TABLE customers (
    customer_id NUMBER PRIMARY KEY,
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    email VARCHAR2(100),
    phone VARCHAR2(30),
    date_of_birth DATE,
    street_address VARCHAR2(200),
    city VARCHAR2(100),
    postal_code VARCHAR2(20),
    country VARCHAR2(50),
    iban VARCHAR2(34),
    registration_date DATE,
    customer_segment VARCHAR2(20),
    is_active NUMBER(1)
);

CREATE TABLE transactions (
    transaction_id NUMBER PRIMARY KEY,
    customer_id NUMBER REFERENCES customers(customer_id),
    transaction_date DATE,
    amount NUMBER(12,2),
    currency VARCHAR2(3),
    category VARCHAR2(50),
    merchant_name VARCHAR2(100),
    description VARCHAR2(500),
    status VARCHAR2(20)
);

CREATE TABLE support_tickets (
    ticket_id NUMBER PRIMARY KEY,
    customer_id NUMBER REFERENCES customers(customer_id),
    customer_name VARCHAR2(100),
    customer_email VARCHAR2(100),
    ticket_date DATE,
    subject VARCHAR2(200),
    ticket_text CLOB,
    status VARCHAR2(20)
);

-- Insert realistic EU customer data
INSERT INTO customers VALUES (101, 'Lukas', 'Müller', 'l.mueller88@gmx.de', '+49 151 23456789', DATE '1988-03-12', 'Hauptstrasse 15', 'Berlin', '10115', 'Germany', 'DE89370400440532013000', DATE '2021-05-10', 'RETAIL', 1);
INSERT INTO customers VALUES (102, 'Sophie', 'Martin', 'sophie.m@orange.fr', '+33 6 12 34 56 78', DATE '1992-07-24', '10 Rue de Rivoli', 'Paris', '75001', 'France', 'FR1420041010050500013M02606', DATE '2022-01-15', 'PREMIUM', 1);
INSERT INTO customers VALUES (103, 'Emma', 'García', 'emma.garcia@telefonica.es', '+34 612 345 678', DATE '1985-11-05', 'Calle Gran Vía 12', 'Madrid', '28013', 'Spain', 'ES9121000418401234567891', DATE '2020-08-20', 'RETAIL', 1);
INSERT INTO customers VALUES (104, 'Daan', 'de Jong', 'daan.dejong@ziggo.nl', '+31 6 12345678', DATE '1990-02-18', 'Herengracht 100', 'Amsterdam', '1015CE', 'Netherlands', 'NL91ABNA0417164300', DATE '2023-03-05', 'BUSINESS', 1);
INSERT INTO customers VALUES (105, 'Giulia', 'Rossi', 'giulia.rossi@tim.it', '+39 331 1234567', DATE '1995-09-30', 'Via Roma 1', 'Rome', '00184', 'Italy', 'IT60X0542811101000000123456', DATE '2021-11-12', 'RETAIL', 1);

-- Insert transactions
INSERT INTO transactions VALUES (1001, 101, DATE '2024-02-01', 45.50, 'EUR', 'Groceries', 'REWE Supermarkt', 'Purchase at REWE Berlin by Lukas', 'COMPLETED');
INSERT INTO transactions VALUES (1002, 102, DATE '2024-02-02', 120.00, 'EUR', 'Dining', 'Le Meurice', 'Dinner at Le Meurice Paris', 'COMPLETED');
INSERT INTO transactions VALUES (1003, 103, DATE '2024-02-05', 850.00, 'EUR', 'Rent', 'Inmobiliaria Madrid', 'Monthly rent transfer to Emma', 'COMPLETED');
INSERT INTO transactions VALUES (1004, 104, DATE '2024-02-06', 15.99, 'EUR', 'Subscription', 'Netflix', 'Netflix monthly sub', 'COMPLETED');

-- Insert support tickets with embedded PII
INSERT INTO support_tickets VALUES (501, 101, 'Lukas Müller', 'l.mueller88@gmx.de', DATE '2024-01-15', 'Card declined', 'Hi, my card was declined yesterday. Please contact me at l.mueller88@gmx.de or call +49 151 23456789. Thanks, Lukas.', 'CLOSED');
INSERT INTO support_tickets VALUES (502, 102, 'Sophie Martin', 'sophie.m@orange.fr', DATE '2024-02-10', 'Address update', 'I moved to a new apartment. Can you update my file? My new email is sophie.new@gmail.com and phone is +33 6 98 76 54 32.', 'OPEN');

COMMIT;
EXIT;
EOSQL

echo "Data loaded successfully."

# Configure SQL Developer connection for GDPR_ADMIN
ensure_hr_connection "GDPR Database" "gdpr_admin" "Gdpr2024"

# Clear any previous task state
rm -f /home/ga/anonymization_report.csv 2>/dev/null || true

echo "=== Task Setup Complete ==="