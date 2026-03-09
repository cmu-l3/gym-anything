package com.ecommerce;

import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;

/**
 * Unit tests for OrderManager — covers discount calculation, price precision,
 * payment validation, and order confirmation logic.
 */
public class OrderManagerTest {

    private OrderManager manager;
    private Customer regularCustomer;
    private Customer premiumCustomer;

    @Before
    public void setUp() {
        manager = new OrderManager();
        regularCustomer = new Customer("C-001", "Jane Smith", "jane@example.com", false);
        premiumCustomer = new Customer("C-002", "Bob Patel",  "bob@example.com",  true);
    }

    // -----------------------------------------------------------------------
    // Discount boundary test — exercises the > 10 vs >= 10 bug
    // -----------------------------------------------------------------------

    @Test
    public void testExactlyTenItemsQualifyForBulkDiscount() {
        // Business rule: 10 OR MORE items → 10% discount
        // BUG: code uses > 10, so exactly 10 items get no discount
        Order order = new Order("ORD-101", regularCustomer);
        for (int i = 0; i < 10; i++) {
            order.addItem(new OrderItem("SKU-" + i, "Product " + i, 10_00, 1)); // $10 each × 10 = $100
        }
        assertEquals("Order should have exactly 10 items", 10, order.getTotalItemCount());

        long subtotal = manager.calculateSubtotalCents(order);
        assertEquals("Subtotal should be $100.00 (10000 cents)", 10000L, subtotal);

        long discount = manager.calculateDiscountCents(order, subtotal);
        assertEquals(
            "An order with exactly 10 items must receive a 10% bulk discount (1000 cents). " +
            "Fix: change the threshold from > 10 to >= 10.",
            1000L, discount
        );

        long finalTotal = subtotal - discount;
        assertEquals("Final total after discount should be $90.00 (9000 cents)", 9000L, finalTotal);
    }

    @Test
    public void testElevenItemsAlsoGetDiscount() {
        // This should pass even with the buggy > 10 threshold
        Order order = new Order("ORD-102", regularCustomer);
        for (int i = 0; i < 11; i++) {
            order.addItem(new OrderItem("SKU-" + i, "Widget " + i, 5_00, 1)); // $5 each × 11 = $55
        }
        long subtotal = manager.calculateSubtotalCents(order);
        long discount = manager.calculateDiscountCents(order, subtotal);
        assertEquals("11-item order should get 10% discount (275 cents)", 275L, discount);
    }

    // -----------------------------------------------------------------------
    // Integer overflow test — exercises the int accumulator bug
    // -----------------------------------------------------------------------

    @Test
    public void testSubtotalDoesNotOverflowForLargeOrder() {
        // Three enterprise licenses at $8,000,000 each = $24,000,000 total
        // Each individual item total (800_000_000 cents) fits within int range.
        // But the running sum (2,400,000,000 cents) exceeds Integer.MAX_VALUE (2,147,483,647),
        // causing a silent int overflow and a negative result in the buggy implementation.
        Order order = new Order("ORD-CORP-01", regularCustomer);
        order.addItem(new OrderItem("ENT-LIC-1", "Enterprise License A", 800_000_000, 1)); // $8M
        order.addItem(new OrderItem("ENT-LIC-2", "Enterprise License B", 800_000_000, 1)); // $8M
        order.addItem(new OrderItem("ENT-LIC-3", "Enterprise License C", 800_000_000, 1)); // $8M
        // Each getLineTotalCents() = 800,000,000 (fits in int)
        // Sum = 2,400,000,000 → overflows int, gives -1,894,967,296 with the bug

        long subtotal = manager.calculateSubtotalCents(order);

        assertTrue(
            "Subtotal is negative — integer overflow detected. " +
            "Fix: change the accumulator variable in calculateSubtotalCents() from 'int total' to 'long total' " +
            "so the running sum does not overflow. Got: " + subtotal,
            subtotal > 0
        );
        assertEquals(
            "Subtotal must be exactly 2,400,000,000 cents ($24,000,000) for three $8M licenses",
            2_400_000_000L, subtotal
        );
    }

    // -----------------------------------------------------------------------
    // Payment validation test — exercises the always-true validation bug
    // -----------------------------------------------------------------------

    @Test
    public void testInvalidPaymentCardIsRejected() {
        Order order = new Order("ORD-201", regularCustomer);
        order.addItem(new OrderItem("ITEM-1", "Gadget", 50_00, 1));

        // Attempt to process with obviously invalid card data
        try {
            manager.processOrder(order, "1234", "ab", 2000);  // 4-digit number, non-numeric CVV, expired year
            fail(
                "processOrder() should have thrown IllegalArgumentException for an invalid payment card, " +
                "but it completed successfully. " +
                "Fix: implement validatePaymentCard() to check card number length (16 digits), " +
                "CVV length (3 digits), and expiry year (>= current year)."
            );
        } catch (IllegalArgumentException e) {
            // Expected: invalid card must be rejected
            assertTrue("Exception message should mention card or validation",
                       e.getMessage().toLowerCase().contains("card") ||
                       e.getMessage().toLowerCase().contains("valid") ||
                       e.getMessage().toLowerCase().contains("payment"));
        }

        // Order status must not have changed
        assertEquals("Order status must remain PENDING after failed payment",
                     Order.Status.PENDING, order.getStatus());
    }

    @Test
    public void testValidPaymentCardIsAccepted() {
        Order order = new Order("ORD-202", regularCustomer);
        order.addItem(new OrderItem("ITEM-2", "Gizmo", 25_00, 2));

        // Valid card: 16 digits, valid CVV, future year
        long total = manager.processOrder(order, "4111111111111111", "123", 2030);

        assertTrue("Charge must be positive for a valid order", total > 0);
        assertEquals("Order must be CONFIRMED after successful payment",
                     Order.Status.CONFIRMED, order.getStatus());
    }
}
