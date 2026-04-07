#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Java Concurrency Matching Engine Task ==="

WORKSPACE="/home/ga/workspace/matching_engine"
sudo -u ga mkdir -p "$WORKSPACE/src/matching"
sudo -u ga mkdir -p "$WORKSPACE/output"
sudo -u ga mkdir -p "$WORKSPACE/bin"

date +%s > /tmp/task_start_time.txt

# ──────────────────────────────────────────────────────────
# Create Java Source Files with Concurrency Bugs
# ──────────────────────────────────────────────────────────

# 1. Order.java (POJO)
cat > "$WORKSPACE/src/matching/Order.java" << 'EOF'
package matching;

public class Order {
    public final int id;
    public final String symbol;
    public final double price;
    public final int size;

    public Order(int id, String symbol, double price, int size) {
        this.id = id;
        this.symbol = symbol;
        this.price = price;
        this.size = size;
    }
}
EOF

# 2. Account.java (POJO)
cat > "$WORKSPACE/src/matching/Account.java" << 'EOF'
package matching;

public class Account {
    public final int id;
    public double balance;

    public Account(int id, double balance) {
        this.id = id;
        this.balance = balance;
    }
}
EOF

# 3. OrderProcessor.java (BUG: CPU Spin)
cat > "$WORKSPACE/src/matching/OrderProcessor.java" << 'EOF'
package matching;
import java.util.concurrent.*;

public class OrderProcessor extends Thread {
    private final MatchingEngine engine;
    private final BlockingQueue<Order> queue = new LinkedBlockingQueue<>();

    public OrderProcessor(MatchingEngine engine) {
        this.engine = engine;
    }

    public void submit(Order o) {
        queue.offer(o);
    }

    @Override
    public void run() {
        while (engine.isRunning()) {
            // BUG: Busy-wait loop consumes 100% CPU. Should block properly.
            Order o = queue.poll();
            if (o != null) {
                engine.processOrder(o);
            }
        }
    }
}
EOF

# 4. MatchingEngine.java (BUG: Visibility)
cat > "$WORKSPACE/src/matching/MatchingEngine.java" << 'EOF'
package matching;

public class MatchingEngine {
    // BUG: Missing visibility guarantee. Control thread updates may not be seen by processor thread.
    private boolean isRunning = true;
    
    private final OrderProcessor processor;
    private final MarketPublisher publisher;
    private final OrderBook book;

    public MatchingEngine() {
        this.publisher = new MarketPublisher();
        this.book = new OrderBook();
        this.processor = new OrderProcessor(this);
    }

    public void start() {
        processor.start();
    }

    public void stop() {
        isRunning = false;
    }

    public boolean isRunning() {
        return isRunning;
    }

    public void join() throws InterruptedException {
        processor.join();
    }

    public void addOrder(Order o) {
        processor.submit(o);
    }

    public void processOrder(Order o) {
        book.addOrder(o);
        publisher.publish("Processed Order: " + o.id + " at $" + o.price);
    }

    public MarketPublisher getPublisher() {
        return publisher;
    }
}
EOF

# 5. OrderBook.java (BUG: Race Condition)
cat > "$WORKSPACE/src/matching/OrderBook.java" << 'EOF'
package matching;
import java.util.*;

public class OrderBook {
    private final List<Order> orders = new ArrayList<>();
    private double bestBid = 0.0;

    public void addOrder(Order o) {
        // BUG: bestBid is updated outside the lock, causing a race condition.
        synchronized(this) {
            orders.add(o);
        }
        bestBid = calculateBestBid();
    }

    private double calculateBestBid() {
        return orders.stream().mapToDouble(o -> o.price).max().orElse(0.0);
    }

    public double getBestBid() {
        return bestBid;
    }
}
EOF

# 6. BalanceTransfer.java (BUG: Deadlock)
cat > "$WORKSPACE/src/matching/BalanceTransfer.java" << 'EOF'
package matching;

public class BalanceTransfer {
    // BUG: Inconsistent lock ordering causes cyclic deadlocks during concurrent transfers.
    public void transfer(Account from, Account to, double amount) {
        synchronized(from) {
            synchronized(to) {
                if (from.balance >= amount) {
                    from.balance -= amount;
                    to.balance += amount;
                }
            }
        }
    }
}
EOF

# 7. MarketPublisher.java (BUG: Concurrent Modification)
cat > "$WORKSPACE/src/matching/MarketPublisher.java" << 'EOF'
package matching;
import java.util.*;

public class MarketPublisher {
    // BUG: Iterating while other threads add subscribers causes ConcurrentModificationException.
    private final List<String> subscribers = new ArrayList<>();

    public void subscribe(String sub) {
        subscribers.add(sub);
    }

    public void publish(String message) {
        for (String sub : subscribers) {
            // Simulate network publish delay
            if (sub != null && message != null) {
                int dummy = sub.length() + message.length();
            }
        }
    }
}
EOF

# 8. Main.java (Load Tester)
cat > "$WORKSPACE/src/matching/Main.java" << 'EOF'
package matching;

public class Main {
    public static void main(String[] args) throws Exception {
        System.out.println("Starting load test...");
        MatchingEngine engine = new MatchingEngine();
        engine.start();

        // 1. Trigger Deadlock (BalanceTransfer)
        Account a1 = new Account(1, 10000);
        Account a2 = new Account(2, 10000);
        BalanceTransfer transfer = new BalanceTransfer();
        Thread t1 = new Thread(() -> {
            for(int i=0; i<5000; i++) transfer.transfer(a1, a2, 1);
        });
        Thread t2 = new Thread(() -> {
            for(int i=0; i<5000; i++) transfer.transfer(a2, a1, 1);
        });
        t1.start(); t2.start();

        // 2. Trigger Concurrent Modification (MarketPublisher)
        MarketPublisher pub = engine.getPublisher();
        Thread t3 = new Thread(() -> {
            for(int i=0; i<5000; i++) pub.subscribe("Sub-" + i);
        });
        Thread t4 = new Thread(() -> {
            for(int i=0; i<5000; i++) pub.publish("Tick");
        });
        t3.start(); t4.start();

        // 3. Feed Orders & Trigger Race Conditions
        Thread[] orderThreads = new Thread[4];
        for (int i=0; i<4; i++) {
            final int tId = i;
            orderThreads[i] = new Thread(() -> {
                for (int j=0; j<2500; j++) {
                    engine.addOrder(new Order(tId * 10000 + j, "AAPL", 150.0 + (j%10), 100));
                }
            });
            orderThreads[i].start();
        }

        // Wait for all feeder threads
        t1.join(); t2.join(); t3.join(); t4.join();
        for (Thread t : orderThreads) t.join();

        // 4. Stop engine (Triggers Visibility bug if not volatile)
        engine.stop();
        
        // Wait a max of 2 seconds for engine to shut down
        long start = System.currentTimeMillis();
        while(engine.isRunning() && System.currentTimeMillis() - start < 2000) {
            Thread.sleep(10);
        }
        
        System.out.println("status: SUCCESS");
        System.exit(0);
    }
}
EOF

# ──────────────────────────────────────────────────────────
# Create Load Test Script
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE/run_load_test.sh" << 'EOF'
#!/bin/bash
echo "Compiling..."
rm -rf bin/*
javac -d bin src/matching/*.java

if [ $? -eq 0 ]; then
    echo "Running engine load test..."
    # 10s timeout prevents infinite hangs from deadlocks/spins
    timeout 10s java -cp bin matching.Main
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        echo "ERROR: Process timed out (Deadlock or CPU Spin detected)."
    elif [ $EXIT_CODE -ne 0 ]; then
        echo "ERROR: Process crashed (Check for Exceptions)."
    fi
else
    echo "Compilation failed."
fi
EOF
chmod +x "$WORKSPACE/run_load_test.sh"
chown -R ga:ga "$WORKSPACE"

# ──────────────────────────────────────────────────────────
# Set up VSCode UI
# ──────────────────────────────────────────────────────────
if ! pgrep -f "code.*--ms-enable-electron" > /dev/null; then
    echo "Starting VSCode..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE &"
    sleep 5
fi

# Wait and maximize
wait_for_window "Visual Studio Code" 30 || true
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="