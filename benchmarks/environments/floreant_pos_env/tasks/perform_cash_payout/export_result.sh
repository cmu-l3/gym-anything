#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_id.txt 2>/dev/null || echo "0")

# 1. Take final screenshot before killing app
take_screenshot /tmp/task_final.png

# 2. Check if app was running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Kill app to release Derby DB lock for querying
kill_floreant

# 4. Query Database for new transactions
echo "Querying database for results..."
mkdir -p /tmp/java_tools
cat > /tmp/java_tools/ExportTransactions.java << EOF
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class ExportTransactions {
    public static void main(String[] args) {
        String url = "jdbc:derby:/opt/floreantpos/database/derby-server";
        StringBuilder json = new StringBuilder();
        json.append("[");
        
        try (Connection conn = DriverManager.getConnection(url);
             Statement stmt = conn.createStatement()) {
            
            // Query for transactions created after our initial max ID
            // Using a broad query to catch generic transactions or specific payout tables
            // Note: Schema analysis suggests 'TRANSACTIONS' table holds payouts with transaction_type 'PAY_OUT'
            
            String query = "SELECT ID, TRANSACTION_TYPE, TOTAL_AMOUNT, TRANSACTION_TIME FROM TRANSACTIONS WHERE ID > $INITIAL_MAX_ID";
            ResultSet rs = stmt.executeQuery(query);
            
            boolean first = true;
            while (rs.next()) {
                if (!first) json.append(",");
                first = false;
                
                int id = rs.getInt("ID");
                String type = rs.getString("TRANSACTION_TYPE");
                double amount = rs.getDouble("TOTAL_AMOUNT");
                Timestamp time = rs.getTimestamp("TRANSACTION_TIME");
                
                // For 'Note' or 'Reason', it might be in a property or separate column
                // Floreant 1.4 often stores properties in a separate table or a specific column
                // Let's try to fetch a 'PROPERTIES' or 'NOTE' column if it exists, otherwise leave blank
                String note = "";
                
                // Sub-query for properties/notes if needed. For now, check common column names via try/catch in loop is messy.
                // We'll rely on the main transaction record first. 
                // However, Payout reasons are often stored. Let's try to query 'PAYOUT_REASON' if it exists in a joined table?
                // Simpler: Just check if we can get a "NOTE" column from this RS
                try {
                    note = rs.getString("NOTE"); // Common field
                } catch (SQLException e) {
                   // Column might not exist, ignore
                }

                json.append(String.format(
                    "{\"id\": %d, \"type\": \"%s\", \"amount\": %.2f, \"time\": \"%s\", \"note\": \"%s\"}",
                    id, type, amount, time.toString(), note != null ? note.replace("\"", "\\\"") : ""
                ));
            }
        } catch (Exception e) {
            e.printStackTrace();
            System.exit(1);
        }
        
        json.append("]");
        System.out.println(json.toString());
    }
}
EOF

# Find Floreant libs
LIB_CP=$(find /opt/floreantpos/lib -name "*.jar" | tr '\n' ':')
FLOREANT_CP="/opt/floreantpos/floreantpos.jar:$LIB_CP"

# Compile and Run
javac -cp "$FLOREANT_CP" /tmp/java_tools/ExportTransactions.java
DB_RESULT=$(java -cp ".:/tmp/java_tools:$FLOREANT_CP" ExportTransactions)

# 5. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "transactions": $DB_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json