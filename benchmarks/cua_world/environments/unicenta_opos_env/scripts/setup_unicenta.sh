#!/bin/bash
# post_start hook — configure MySQL, initialize schema, seed data, warm-up launch
# Runs as root after the desktop starts

echo "=== Setting up uniCenta oPOS ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

if [ -f /tmp/unicenta_install_failed ]; then
    echo "ERROR: Installation failed in pre_start. Aborting setup."
    exit 1
fi

sleep 8

UNICENTA_DIR=$(cat /tmp/unicenta_install_dir.txt 2>/dev/null || echo "/opt/unicentaopos")
MYSQL_JAR=$(cat /tmp/unicenta_mysql_jar.txt 2>/dev/null || echo "")
if [ -z "$MYSQL_JAR" ]; then
    MYSQL_JAR=$(find "$UNICENTA_DIR" -name "mysql-connector-j*.jar" -o -name "mysql-connector-java*.jar" 2>/dev/null | head -1)
fi

chown -R ga:ga /opt/unicentaopos/
chmod -R 755 /opt/unicentaopos/

# -----------------------------------------------------------------------
# Start MySQL Service
# -----------------------------------------------------------------------
echo "Starting MySQL service..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || mysqld_safe &

wait_for_mysql() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
            echo "MySQL is ready (${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "ERROR: MySQL not ready after ${timeout}s"
    return 1
}

wait_for_mysql || {
    mkdir -p /var/run/mysqld
    chown mysql:mysql /var/run/mysqld
    mysqld_safe &
    sleep 5
    wait_for_mysql || exit 1
}

# -----------------------------------------------------------------------
# Create Database and User
# -----------------------------------------------------------------------
echo "Creating uniCenta database and user..."
mysql -u root << 'SQLEOF'
SET GLOBAL innodb_default_row_format=DYNAMIC;
SET GLOBAL innodb_strict_mode=OFF;
CREATE DATABASE IF NOT EXISTS unicentaopos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'unicenta'@'localhost' IDENTIFIED WITH mysql_native_password BY 'unicenta';
GRANT ALL PRIVILEGES ON unicentaopos.* TO 'unicenta'@'localhost';
FLUSH PRIVILEGES;
SQLEOF

echo "Database 'unicentaopos' and user 'unicenta' created"

# -----------------------------------------------------------------------
# Initialize Schema
# -----------------------------------------------------------------------
echo "Initializing database schema..."

if [ -s /opt/unicentaopos/sql/MySQL-create-fixed.sql ]; then
    # Load schema with -f (force) to skip $FILE{} INSERT errors
    mysql -f -u unicenta -punicenta unicentaopos < /opt/unicentaopos/sql/MySQL-create-fixed.sql 2>/tmp/schema_load.log
    TABLE_COUNT=$(mysql -u unicenta -punicenta unicentaopos -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='unicentaopos';" 2>/dev/null || echo "0")
    echo "Tables created: $TABLE_COUNT"

    if [ "$TABLE_COUNT" -lt 20 ]; then
        echo "ERROR: Schema load incomplete ($TABLE_COUNT tables)"
    fi
else
    echo "ERROR: Schema SQL not found"
    exit 1
fi

# -----------------------------------------------------------------------
# Insert system data (roles, people, resources) from extracted templates
# The schema SQL uses $FILE{} placeholders that only work inside the Java app
# We extract the actual files and insert them via Python
# -----------------------------------------------------------------------
echo "Inserting system data from extracted templates..."
python3 << 'PYEOF'
import os, pymysql

template_dir = '/tmp/unicenta_resources/com/openbravo/pos/templates'

conn = pymysql.connect(host='localhost', user='unicenta', password='unicenta', database='unicentaopos')
cursor = conn.cursor()

# Insert roles with XML permissions
role_files = {
    '0': ('Administrator role', 'Role.Administrator.xml'),
    '1': ('Manager role', 'Role.Manager.xml'),
    '2': ('Employee role', 'Role.Employee.xml'),
    '3': ('Guest role', 'Role.Guest.xml'),
}
for role_id, (name, fname) in role_files.items():
    fpath = os.path.join(template_dir, fname)
    if os.path.exists(fpath):
        with open(fpath, 'rb') as f:
            content = f.read()
        try:
            cursor.execute('INSERT INTO roles(id, name, permissions) VALUES(%s, %s, %s)', (role_id, name, content))
        except: pass

# Insert people (default users with no password)
for pid, name, role in [('0','Administrator','0'),('1','Manager','1'),('2','Employee','2'),('3','Guest','3')]:
    try:
        cursor.execute('INSERT INTO people(id, name, apppassword, role, visible, image) VALUES(%s, %s, NULL, %s, TRUE, NULL)', (pid, name, role))
    except: pass

# Insert key resources (templates)
resource_files = [
    ('00', 'Menu.Root', 0, 'Menu.Root.txt'),
    ('01', 'Application.Started', 0, 'application.started.xml'),
    ('02', 'Cash.Close', 0, 'Cash.Close.xml'),
    ('03', 'Customer.Created', 0, 'customer.created.xml'),
    ('04', 'Customer.Deleted', 0, 'customer.deleted.xml'),
    ('05', 'Customer.Updated', 0, 'customer.updated.xml'),
    ('06', 'payment.cash', 0, 'payment.cash.txt'),
    ('07', 'Ticket.Buttons', 0, 'Ticket.Buttons.xml'),
    ('08', 'Ticket.Close', 0, 'Ticket.Close.xml'),
    ('09', 'Ticket.Line', 0, 'Ticket.Line.xml'),
    ('10', 'Window.Title', 0, 'Window.Title.txt'),
    ('12', 'Printer.Ticket', 0, 'Printer.Ticket.xml'),
    ('13', 'Printer.Ticket2', 0, 'Printer.Ticket2.xml'),
    ('14', 'Printer.TicketPreview', 0, 'Printer.TicketPreview.xml'),
    ('15', 'Printer.CloseCash', 0, 'Printer.CloseCash.xml'),
    ('16', 'Printer.CloseCash.Preview', 0, 'Printer.CloseCash.Preview.xml'),
    ('17', 'Printer.CustomerPaid', 0, 'Printer.CustomerPaid.xml'),
    ('18', 'Printer.CustomerPaid2', 0, 'Printer.CustomerPaid2.xml'),
    ('19', 'Printer.Start', 0, 'Printer.Start.xml'),
    ('20', 'Printer.OpenDrawer', 0, 'Printer.OpenDrawer.xml'),
    ('21', 'Printer.Inventory', 0, 'Printer.Inventory.xml'),
    ('22', 'Printer.FiscalTicket', 0, 'Printer.FiscalTicket.xml'),
    ('23', 'Printer.PartialCash', 0, 'Printer.PartialCash.xml'),
    ('24', 'Printer.PrintLastTicket', 0, 'Printer.PrintLastTicket.xml'),
]
for res_id, name, restype, fname in resource_files:
    fpath = os.path.join(template_dir, fname)
    if os.path.exists(fpath):
        with open(fpath, 'rb') as f:
            content = f.read()
        try:
            cursor.execute('INSERT INTO resources(id, name, restype, content) VALUES(%s, %s, %s, %s)', (res_id, name, restype, content))
        except: pass

# Insert applications record
try:
    cursor.execute("INSERT INTO applications(id, name, version) VALUES('unicentaopos', 'uniCenta oPOS', '4.6.4')")
except: pass

conn.commit()

# Verify
cursor.execute('SELECT COUNT(*) FROM roles')
print(f'Roles: {cursor.fetchone()[0]}')
cursor.execute('SELECT COUNT(*) FROM people')
print(f'People: {cursor.fetchone()[0]}')
cursor.execute('SELECT COUNT(*) FROM resources')
print(f'Resources: {cursor.fetchone()[0]}')
cursor.execute('SELECT COUNT(*) FROM applications')
print(f'Applications: {cursor.fetchone()[0]}')

cursor.close()
conn.close()
print('System data insertion complete')
PYEOF

# -----------------------------------------------------------------------
# Create uniCenta Properties File
# CRITICAL NOTES:
# 1. db.driver=com.mysql.jdbc.Driver is REQUIRED (app reads this property)
# 2. db.URL must NOT include the database name (app appends it automatically)
# 3. db.driverlib points to the MySQL connector JAR for dynamic loading
# -----------------------------------------------------------------------
echo "Creating uniCenta configuration..."
cat > /home/ga/unicentaopos.properties << PROPEOF
machine.hostname=unicenta-pos
machine.screenmode=window
machine.ticketsbag=standard
machine.department=
machine.printer=screen
machine.printer.2=Not defined
machine.printer.3=Not defined
machine.display=screen
machine.scale=Not defined
machine.scanner=Not defined
machine.ibutton=Not defined
machine.uniqueinstance=false
db.engine=MySQL
db.driver=com.mysql.jdbc.Driver
db.driverlib=$MYSQL_JAR
db.URL=jdbc:mysql://localhost:3306/
db.user=unicenta
db.password=unicenta
PROPEOF
chown ga:ga /home/ga/unicentaopos.properties
cp /home/ga/unicentaopos.properties "$UNICENTA_DIR/unicentaopos.properties" 2>/dev/null || true

echo "Configuration file created"

# -----------------------------------------------------------------------
# Desktop shortcut
# -----------------------------------------------------------------------
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/uniCentaoPOS.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=uniCenta oPOS
Comment=Point of Sale System
Exec=/usr/local/bin/unicenta-pos
Icon=applications-other
StartupNotify=true
Terminal=false
Categories=Office;
Type=Application
DESKTOPEOF
chown ga:ga /home/ga/Desktop/uniCentaoPOS.desktop
chmod +x /home/ga/Desktop/uniCentaoPOS.desktop
su - ga -c "gio set /home/ga/Desktop/uniCentaoPOS.desktop metadata::trusted true 2>/dev/null" || true

# -----------------------------------------------------------------------
# Load Seed Data (real products from Open Food Facts)
# -----------------------------------------------------------------------
echo "Loading seed data..."
mysql -u unicenta -punicenta unicentaopos < /workspace/config/seed_data.sql 2>/tmp/seed_load.log
PRODUCT_COUNT=$(mysql -u unicenta -punicenta unicentaopos -N -e "SELECT COUNT(*) FROM products;" 2>/dev/null || echo "0")
CATEGORY_COUNT=$(mysql -u unicenta -punicenta unicentaopos -N -e "SELECT COUNT(*) FROM categories;" 2>/dev/null || echo "0")
CUSTOMER_COUNT=$(mysql -u unicenta -punicenta unicentaopos -N -e "SELECT COUNT(*) FROM customers;" 2>/dev/null || echo "0")
echo "Seed data: Products=$PRODUCT_COUNT Categories=$CATEGORY_COUNT Customers=$CUSTOMER_COUNT"

# -----------------------------------------------------------------------
# Warm-up launch to verify everything works
# -----------------------------------------------------------------------
echo "Starting uniCenta oPOS warm-up launch..."
pkill -f "unicentaopos.jar" 2>/dev/null || true
sleep 2

su - ga -c "setsid /usr/local/bin/unicenta-pos > /tmp/unicenta_warmup.log 2>&1 &"

TIMEOUT=120
ELAPSED=0
WINDOW_FOUND=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "uniCenta" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "uniCenta window found (WID: $WID) after ${ELAPSED}s"
        WINDOW_FOUND=true
        break
    fi
    if ! pgrep -f "unicentaopos.jar" > /dev/null 2>&1; then
        echo "Java process not running, checking log..."
        cat /tmp/unicenta_warmup.log 2>/dev/null | tail -20
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 10
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/unicenta_warmup_screen.png 2>/dev/null || true

echo "Killing warm-up instance..."
pkill -f "unicentaopos.jar" 2>/dev/null || true
sleep 3
pkill -9 -f "unicentaopos.jar" 2>/dev/null || true
sleep 2

# -----------------------------------------------------------------------
# Save MySQL backup for per-task resets
# -----------------------------------------------------------------------
echo "Creating MySQL backup..."
mysqldump -u unicenta -punicenta unicentaopos > /opt/unicentaopos/unicentaopos_backup.sql 2>/dev/null
chown ga:ga /opt/unicentaopos/unicentaopos_backup.sql 2>/dev/null
echo "Database backup: $(du -sh /opt/unicentaopos/unicentaopos_backup.sql 2>/dev/null | cut -f1)"

# Convenience query script
cat > /usr/local/bin/unicenta-query << 'QUERYEOF'
#!/bin/bash
mysql -u unicenta -punicenta unicentaopos -N -e "$1" 2>/dev/null
QUERYEOF
chmod +x /usr/local/bin/unicenta-query

echo ""
echo "=== Setup Verification ==="
echo "OK: unicentaopos.jar exists ($(du -sh "$UNICENTA_DIR/unicentaopos.jar" 2>/dev/null | cut -f1))"
[ "$(mysqladmin ping -h localhost 2>/dev/null | grep -c alive)" -gt 0 ] && echo "OK: MySQL is running" || echo "WARN: MySQL status unclear"
echo "OK: Properties at /home/ga/unicentaopos.properties"
echo "=== uniCenta oPOS setup complete ==="
