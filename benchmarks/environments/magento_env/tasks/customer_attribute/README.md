# Customer Attribute Task

## Overview

This task tests a Magento administrator's ability to extend the customer data model with custom EAV attributes. Adding custom customer attributes is a core CRM configuration task performed by e-commerce platform administrators who need to capture additional customer profile data for personalization and segmentation.

**Domain context**: Skincare and beauty brands extensively use customer profiling for product recommendations. Capturing "skin concern" at registration enables personalized product recommendations, targeted email campaigns, and audience segmentation — all standard in the beauty retail industry. Configuring Magento's custom attribute system with the correct input type, form visibility settings, and dropdown options is a multi-step admin workflow.

## Goal

Create a customer attribute with these exact properties:

- Attribute Code: `skin_concern`
- Default Label: `Primary Skin Concern`
- Input Type: Dropdown
- Values Required: Yes
- Show on Storefront: Yes
- Sort Order: 10
- Used in forms: Customer Registration AND Customer Account Edit

Five dropdown options (in this order):
1. `Acne & Blemishes`
2. `Anti-Aging`
3. `Hyperpigmentation`
4. `Dryness & Dehydration`
5. `Sensitivity`

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Attribute `skin_concern` exists as a dropdown (select) input | 25 |
| Attribute is required (`is_required=1`) | 15 |
| Attribute is visible on storefront (`is_visible_on_front=1`) | 15 |
| At least 4 of the 5 required dropdown options exist | 25 |
| Attribute is used in Customer Registration form | 10 |
| Attribute sort order is 10 | 10 |

**Pass threshold: 60 points**

## Verification Strategy

- `setup_task.sh` records initial customer attribute count and the customer entity type ID
- `export_result.sh` queries `eav_attribute` by `attribute_code='skin_concern'` and `entity_type_id` (customer entity), checks `customer_eav_attribute` for storefront visibility and form usage, queries `eav_attribute_option_value` for the option labels
- `verifier.py` gates on attribute existence, then scores each criterion independently; option matching is case-insensitive and allows for minor whitespace variations

## Database Schema Reference

```sql
-- Find customer entity type ID
SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code='customer';

-- Find the attribute
SELECT attribute_id, attribute_code, frontend_input, is_required, frontend_label
FROM eav_attribute
WHERE attribute_code='skin_concern' AND entity_type_id=<customer_entity_type_id>;

-- Storefront and form visibility
SELECT is_visible, is_visible_on_front
FROM customer_eav_attribute WHERE attribute_id=<attr_id>;

-- Form usage
SELECT form_code FROM customer_form_attribute WHERE attribute_id=<attr_id>;

-- Dropdown options
SELECT eaov.value
FROM eav_attribute_option eao
JOIN eav_attribute_option_value eaov ON eao.option_id=eaov.option_id
WHERE eao.attribute_id=<attr_id> AND eaov.store_id=0
ORDER BY eao.sort_order;
```

## Edge Cases

- In Magento admin, the "Used in forms" checkboxes require both "Customer Registration" and "Customer Account Edit" to be selected — these are stored as separate rows in `customer_form_attribute`.
- The attribute code `skin_concern` must use only lowercase letters and underscores (Magento validation enforces this).
- Dropdown option values are stored in `eav_attribute_option_value` with `store_id=0` for the admin label. The verifier checks for these labels case-insensitively.
- Sort order 10 is stored in `customer_eav_attribute.sort_order` (not the base `eav_attribute` table).
