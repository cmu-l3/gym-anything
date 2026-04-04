#!/bin/bash
set -e
echo "=== Exporting configure_floor_tables result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

RESULTS_FILE="/tmp/task_result.json"

# Take final screenshot before stopping app
take_screenshot /tmp/task_final_state.png

# Stop Floreant POS to release Derby DB lock
echo "Stopping Floreant POS for database verification..."
pkill -f "floreantpos.jar" 2>/dev/null || true
sleep 5
pkill -9 -f "floreantpos.jar" 2>/dev/null || true
sleep 2

# Find Derby database path
DB_PATH=$(find /opt/floreantpos/database -maxdepth 4 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
echo "Derby DB path: $DB_PATH"

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Could not find Derby database"
    echo '{"error": "Derby database not found"}' > "$RESULTS_FILE"
    exit 0
fi

# Find Derby JARs for classpath
DERBY_CP=""
for jar in derby.jar derbytools.jar derbyshared.jar; do
    found=$(find /opt/floreantpos -name "$jar" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        DERBY_CP="${DERBY_CP}:${found}"
    fi
done
DERBY_CP="${DERBY_CP#:}"  # Remove leading colon

echo "Derby classpath: $DERBY_CP"

if [ -z "$DERBY_CP" ]; then
    echo "ERROR: Could not find Derby JAR files"
    echo '{"error": "Derby JARs not found"}' > "$RESULTS_FILE"
    exit 0
fi

# Create a Java verification program to query the database
cat > /tmp/VerifyFloorTables.java << 'JAVAEOF'
import java.sql.*;
import java.util.HashMap;
import java.util.Map;

public class VerifyFloorTables {
    public static void main(String[] args) {
        String dbPath = args[0];
        String url = "jdbc:derby:" + dbPath;

        boolean patioFloorExists = false;
        int patioFloorId = -1;
        
        // Track findings
        Map<Integer, Integer> foundTables = new HashMap<>(); // Number -> Capacity
        Map<Integer, Integer> foundTableFloorIds = new HashMap<>(); // Number -> FloorID
        
        try {
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            Connection conn = DriverManager.getConnection(url);
            Statement stmt = conn.createStatement();

            // --- Check for Patio floor ---
            // Try common table names (schema might vary slightly by version)
            String[] floorQueries = {
                "SELECT ID, NAME FROM SHOP_FLOOR WHERE UPPER(NAME) LIKE '%PATIO%'",
                "SELECT ID, NAME FROM RESTAURANT_FLOOR WHERE UPPER(NAME) LIKE '%PATIO%'",
                "SELECT ID, NAME FROM FLOOR WHERE UPPER(NAME) LIKE '%PATIO%'"
            };

            for (String query : floorQueries) {
                try {
                    ResultSet rs = stmt.executeQuery(query);
                    if (rs.next()) {
                        patioFloorId = rs.getInt("ID");
                        patioFloorExists = true;
                    }
                    rs.close();
                    break; 
                } catch (SQLException e) {
                    continue; // Table doesn't exist, try next
                }
            }

            // --- Check for tables ---
            String[] tableQueries = {
                "SELECT NUMBER, CAPACITY, FLOOR_ID FROM SHOP_TABLE",
                "SELECT NUMBER, CAPACITY, FLOOR_ID FROM RESTAURANT_TABLE",
                "SELECT TABLE_NUMBER AS NUMBER, CAPACITY, FLOOR_ID FROM SHOP_TABLE"
            };

            ResultSet tableRs = null;
            for (String query : tableQueries) {
                try {
                    tableRs = stmt.executeQuery(query);
                    break;
                } catch (SQLException e) {
                    continue;
                }
            }

            if (tableRs != null) {
                while (tableRs.next()) {
                    int num = tableRs.getInt("NUMBER");
                    int cap = tableRs.getInt("CAPACITY");
                    int floorId = tableRs.getInt("FLOOR_ID");
                    
                    foundTables.put(num, cap);
                    foundTableFloorIds.put(num, floorId);
                }
                tableRs.close();
            }

            conn.close();

        } catch (Exception e) {
            System.out.println("ERROR: " + e.getMessage());
            e.printStackTrace();
        }

        // Output JSON manually
        System.out.println("{");
        System.out.println("  \"patio_floor_exists\": " + patioFloorExists + ",");
        System.out.println("  \"patio_floor_id\": " + patioFloorId + ",");
        
        System.out.println("  \"tables_found\": {");
        boolean first = true;
        for (Integer num : foundTables.keySet()) {
            if (!first) System.out.println(",");
            System.out.print("    \"" + num + "\": {\"capacity\": " + foundTables.get(num) + 
                             ", \"floor_id\": " + foundTableFloorIds.get(num) + "}");
            first = false;
        }
        System.out.println("\n  }");
        System.out.println("}");
    }
}
JAVAEOF

# Compile and run verification
echo "Compiling verification program..."
javac -cp "$DERBY_CP" /tmp/VerifyFloorTables.java -d /tmp/

echo "Running database verification..."
# Capture output (JSON)
java -cp "/tmp:$DERBY_CP" VerifyFloorTables "$DB_PATH" > "$RESULTS_FILE" 2>/tmp/db_err.log || echo "Java execution failed"

# Log output for debugging
cat "$RESULTS_FILE"
cat /tmp/db_err.log

# Ensure screenshot exists in result
if [ -f /tmp/task_final_state.png ]; then
    # Use python to merge screenshot path into JSON (safer than sed)
    python3 -c "import json; d=json.load(open('$RESULTS_FILE')); d['screenshot_path']='/tmp/task_final_state.png'; print(json.dumps(d))" > "${RESULTS_FILE}.tmp" && mv "${RESULTS_FILE}.tmp" "$RESULTS_FILE"
fi

echo "Result saved to $RESULTS_FILE"
chmod 666 "$RESULTS_FILE" 2>/dev/null || true