#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Clean Malformed CSV Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_cleanup"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create requirements.txt explaining the task
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
# CSV Cleaning Requirements

Input File: customer_export_broken.csv
Output File: customer_export_clean.csv

Expected Output Format:
- Exactly 5 columns: CustomerID, Name, Email, Description, SignupDate
- Consistent comma delimiters (no semicolons)
- Proper UTF-8 encoding (all special characters preserved)
- All fields properly quoted if they contain commas
- No leading/trailing whitespace in fields
- At least 40 valid rows (out of 50 input rows)

Known Issues in Input:
- Some rows use semicolons as delimiters
- Some description fields have unquoted commas
- UTF-8 encoding issues with international names
- Some rows have wrong number of columns
- Extra whitespace throughout

Approach:
Write a Python script that uses the csv module with proper error handling
to clean and normalize the data.
EOF

# Create malformed CSV with realistic issues
cat > "$WORKSPACE_DIR/customer_export_broken.csv" << 'EOF'
CustomerID,Name,Email,Description,SignupDate
1,John Smith,john@example.com,Regular customer,2024-01-15
2;Maria García;maria@example.com;Frequent buyer premium member;2024-01-20
3,Bob Johnson,bob@example.com,"Ordered widgets, very satisfied",2024-01-22
4,José Martínez,jose@example.com,New customer,2024-01-25
5,"Alice Wong"alice@example.com,Premium member,2024-01-28
6,Charlie Brown,charlie@example.com,Referred by friend,2024-02-01,extra,columns
7,David Lee,david@example.com,Loyal customer,2024-02-03
8;Emma Wilson;emma@example.com;Regular shopper loves products;2024-02-05
9,Frank Zhang,frank@example.com,"Bulk orders, corporate account",2024-02-07
10,Grace O'Neill,grace@example.com,VIP customer,2024-02-10
11,Henry Taylor,henry@example.com,New signup,2024-02-12
12;Sophie Müller;sophie@example.com;International customer Germany;2024-02-14
13,Ivan Petrov,ivan@example.com,Good reviews,2024-02-16
14,Julia Santos,julia@example.com,"Repeat customer, always satisfied",2024-02-18
15,Kevin White
16,Laura Green,laura@example.com,Active shopper,2024-02-22
17;Pierre Dubois;pierre@example.com;French customer loves service;2024-02-24
18,Quinn Black,quinn@example.com,Monthly subscriber,2024-02-26
19,Rachel Adams,rachel@example.com,"Large orders, wholesale",2024-02-28
20,Sam Thompson,sam@example.com,  Referred customer  ,2024-03-01
21,Tina Chen,tina@example.com,Premium tier,2024-03-03
22;Hans Jørgensen;hans@example.com;Scandinavian customer satisfied;2024-03-05
23,Uma Patel,uma@example.com,First time buyer,2024-03-07
24,Victor Ross,victor@example.com,"Corporate account, bulk orders",2024-03-09
25,Wendy Clark,wendy@example.com,  Regular shopper  ,2024-03-11
26,Xavier King,xavier@example.com,Gold member,2024-03-13
27;Yuki Tanaka;yuki@example.com;Japanese customer international shipping;2024-03-15
28,Zoe Martin,zoe@example.com,Active buyer,2024-03-17
29,Alex Turner,alex@example.com,"Subscribed to newsletter, engaged",2024-03-19
30,Beth Cooper,beth@example.com,Seasonal shopper,2024-03-21
31,Carlos Rodríguez,carlos@example.com,Latino customer,2024-03-23
32;Diana López;diana@example.com;Frequent orders fast shipping;2024-03-25
33,Eric Foster,eric@example.com,Weekend buyer,2024-03-27
34,Fiona Scott,fiona@example.com,"Loves product quality, reviews",2024-03-29
35,George Wright,george@example.com
36,Hannah Moore,hannah@example.com,Student discount,2024-04-02
37;Igor Volkov;igor@example.com;Russian customer satisfied service;2024-04-04
38,Jenny Hill,jenny@example.com,Mobile app user,2024-04-06
39,Kyle Perry,kyle@example.com,"Bulk buyer, corporate",2024-04-08,extra
40,Lisa Barnes,lisa@example.com,  Premium account  ,2024-04-10
41,Mike Jordan,mike@example.com,Sports enthusiast,2024-04-12
42;Natasha Ivanova;natasha@example.com;International customer fast delivery;2024-04-14
43,Oscar Bell,oscar@example.com,Loyal since 2020,2024-04-16
44,Paula Reed,paula@example.com,"Gift purchases, holidays",2024-04-18
45,Quincy Hayes,quincy@example.com,Business account,2024-04-20
46,Rita Ward,rita@example.com,Newsletter subscriber,2024-04-22
47;Sven Andersson;sven@example.com;Swedish customer satisfied quality;2024-04-24
48,Tracy Long,tracy@example.com,Repeat buyer,2024-04-26
49,Ulysses Grant,ulysses@example.com,"Historical buff, themed orders",2024-04-28
50,Vera Coleman,vera@example.com,New member,2024-04-30
EOF

# Create empty Python script file
cat > "$WORKSPACE_DIR/clean_data.py" << 'EOF'
# TODO: Write a script to clean customer_export_broken.csv
# and produce customer_export_clean.csv with proper formatting

EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the key files
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/customer_export_broken.csv' '$WORKSPACE_DIR/requirements.txt' '$WORKSPACE_DIR/clean_data.py'" || true

echo "=== Clean Malformed CSV Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Inspect customer_export_broken.csv to see data issues"
echo "  2. Read requirements.txt for output specifications"
echo "  3. Write cleaning script in clean_data.py"
echo "  4. Open integrated terminal (Ctrl+Shift+\`)"
echo "  5. Run: python clean_data.py"
echo "  6. Verify output in customer_export_clean.csv"
echo ""
echo "Expected output: customer_export_clean.csv with 5 columns, proper encoding, ~40+ valid rows"