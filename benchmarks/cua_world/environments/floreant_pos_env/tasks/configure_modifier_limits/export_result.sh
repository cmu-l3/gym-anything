#!/bin/bash
echo "=== Exporting configure_modifier_limits results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot for VLM verification
take_screenshot /tmp/floreant_final.png

# 2. Kill Floreant POS to release the Derby database lock
# (Derby in embedded mode locks the DB, preventing external queries)
kill_floreant
sleep 3

# 3. Create a Java verification tool to query the Derby database
# We use the app's own libraries to ensure driver compatibility
echo "Compiling DB verification tool..."

CAT_DIR="/opt/floreantpos"
LIB_DIR="$CAT_DIR/lib"
CP=".:$CAT_DIR/floreantpos.jar:$LIB_DIR/*"

cat > VerifyModifiers.java << 'EOF'
import java.sql.*;
import java.util.Properties;
import java.io.File;

public class VerifyModifiers {
    public static void main(String[] args) {
        String dbPath = args[0];
        String targetName = args[1];
        Connection conn = null;
        
        System.out.println("{");
        
        try {
            // Locate the database definition usually found in floreantpos.properties or similar
            // For verification, we connect directly to the embedded Derby DB
            String jdbcUrl = "jdbc:derby:" + dbPath;
            
            conn = DriverManager.getConnection(jdbcUrl);
            Statement stmt = conn.createStatement();
            
            // Query for the specific modifier group
            // Note: Table names in Floreant are usually uppercase
            String query = "SELECT NAME, MIN_QUANTITY, MAX_QUANTITY FROM MODIFIER_GROUP WHERE UPPER(NAME) = UPPER('" + targetName + "')";
            ResultSet rs = stmt.executeQuery(query);
            
            if (rs.next()) {
                String name = rs.getString("NAME");
                int min = rs.getInt("MIN_QUANTITY");
                int max = rs.getInt("MAX_QUANTITY");
                
                System.out.println("  \"found\": true,");
                System.out.println("  \"name\": \"" + name + "\",");
                System.out.println("  \"min_quantity\": " + min + ",");
                System.out.println("  \"max_quantity\": " + max);
            } else {
                System.out.println("  \"found\": false");
            }
            
            rs.close();
            stmt.close();
            conn.close();
            
        } catch (Exception e) {
            System.out.println("  \"found\": false,");
            System.out.println("  \"error\": \"" + e.getMessage().replace("\"", "'") + "\"");
            e.printStackTrace();
        }
        
        System.out.println("}");
    }
}
EOF

# Find the actual database path
# Look for the directory containing 'service.properties' which denotes a Derby DB
DB_PATH=$(find /opt/floreantpos/database -name "service.properties" | head -1 | xargs dirname)

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Could not locate Derby database"
    echo "{ \"found\": false, \"error\": \"Database path not found\" }" > /tmp/task_result.json
else
    echo "Database found at: $DB_PATH"
    
    # Compile and run the verifier
    # We run as 'ga' user to avoid permission issues if the DB files are owned by ga
    chown ga:ga VerifyModifiers.java
    
    # Compile
    su - ga -c "javac -cp '$CP' VerifyModifiers.java"
    
    # Run verification (querying for 'Omelet Fillings')
    su - ga -c "java -cp '$CP' VerifyModifiers '$DB_PATH' 'Omelet Fillings'" > /tmp/db_query_result.json
    
    cat /tmp/db_query_result.json
fi

# 4. Construct final result JSON
# Merge the DB result with other metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use python to merge simple JSONs safely
python3 -c "
import json
import os
import sys

try:
    with open('/tmp/db_query_result.json', 'r') as f:
        db_res = json.load(f)
except:
    db_res = {'found': False, 'error': 'Failed to parse DB output'}

final_res = {
    'db_check': db_res,
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'screenshot_path': '/tmp/floreant_final.png',
    'screenshot_exists': os.path.exists('/tmp/floreant_final.png')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_res, f, indent=2)
"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="