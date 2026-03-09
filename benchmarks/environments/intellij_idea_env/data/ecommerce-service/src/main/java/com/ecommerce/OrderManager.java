package com.ecommerce;

import java.util.List;

/**
 * Central service for processing customer orders: calculates totals and discounts,
 * validates payment instruments, and confirms orders.
 *
 * <p>Business rules:
 * <ul>
 *   <li>Orders with <b>10 or more</b> total items qualify for a 10% bulk discount.</li>
 *   <li>Premium members receive an additional 5% discount on top of any bulk discount.</li>
 *   <li>Payment cards must have a 16-digit number and a 3-digit CVV; expired cards are rejected.</li>
 *   <li>An order with no items must not be processed.</li>
 * </ul>
 */
public class OrderManager {

    /**
     * Calculates the subtotal of an order in cents by summing line-item totals.
     *
     * <p>BUG: The accumulator is declared as {@code int}. For large orders, the
     * intermediate sum can exceed {@link Integer#MAX_VALUE} (~$21 million), silently
     * wrapping to a negative value.  All monetary accumulation must use {@code long}.
     *
     * @param order the order to total
     * @return subtotal in cents
     */
    public long calculateSubtotalCents(Order order) {
        List<OrderItem> items = order.getItems();
        int total = 0;                          // BUG: should be long
        for (OrderItem item : items) {
            total += item.getLineTotalCents();  // BUG: int overflow for large orders
        }
        return total;
    }

    /**
     * Calculates any bulk or premium discount to deduct from the subtotal.
     *
     * <p>A 10% bulk discount applies when an order contains <b>10 or more</b> items.
     * Premium members receive an extra 5% on top of any bulk discount.
     *
     * <p>BUG: The bulk discount threshold is {@code > 10} instead of {@code >= 10},
     * so an order with exactly 10 items receives no discount even though the business
     * rule says it should.
     *
     * @param order    the order being evaluated
     * @param subtotal the already-computed subtotal in cents
     * @return discount amount in cents (0 if no discount applies)
     */
    public long calculateDiscountCents(Order order, long subtotal) {
        int totalItems = order.getTotalItemCount();
        long discount = 0L;

        if (totalItems > 10) {           // BUG: should be >= 10  (off-by-one: 10-item orders excluded)
            discount = subtotal / 10;    // 10% bulk discount
        }

        if (order.getCustomer().isPremiumMember()) {
            discount += subtotal / 20;   // additional 5% for premium members
        }

        return discount;
    }

    /**
     * Validates a payment card before charging.
     *
     * <p>A valid card must:
     * <ul>
     *   <li>Have a 16-digit card number (digits only, no spaces).</li>
     *   <li>Have a 3-digit CVV (digits only).</li>
     *   <li>Have an expiry year of the current year or later.</li>
     * </ul>
     *
     * <p>BUG: This method always returns {@code true}, performing no actual validation.
     * Invalid cards — including empty strings, short numbers, and non-numeric values —
     * are silently accepted, allowing fraudulent transactions to proceed.
     *
     * @param cardNumber 16-digit card number
     * @param cvv        3-digit security code
     * @param expiryYear 4-digit expiry year (e.g., 2026)
     * @return {@code true} if the card is valid
     */
    public boolean validatePaymentCard(String cardNumber, String cvv, int expiryYear) {
        // BUG: no validation performed — always accepts every card
        return true;
    }

    /**
     * Processes and confirms an order end-to-end:
     * validates the card, computes the final charge, and marks the order CONFIRMED.
     *
     * @param order      the order to process
     * @param cardNumber payment card number
     * @param cvv        payment card CVV
     * @param expiryYear payment card expiry year
     * @return final charge in cents after any applicable discounts
     * @throws IllegalArgumentException if the order has no items or the card is invalid
     */
    public long processOrder(Order order, String cardNumber, String cvv, int expiryYear) {
        List<OrderItem> items = order.getItems();
        if (items.isEmpty()) {
            throw new IllegalArgumentException("Cannot process an order with no items");
        }

        if (!validatePaymentCard(cardNumber, cvv, expiryYear)) {
            throw new IllegalArgumentException(
                "Payment card validation failed for card ending in " +
                (cardNumber != null && cardNumber.length() >= 4
                    ? cardNumber.substring(cardNumber.length() - 4)
                    : "????")
            );
        }

        long subtotal = calculateSubtotalCents(order);
        long discount = calculateDiscountCents(order, subtotal);
        long total    = subtotal - discount;

        order.setStatus(Order.Status.CONFIRMED);
        return total;
    }
}
