-- ============================================================
-- OLIST E-COMMERCE DATASET
-- 01 - DATA VALIDATION
-- ============================================================
-- Purpose:
-- Validate table grain, key uniqueness, missing/invalid values,
-- and important relationships before cleaning and analysis.
--
-- Raw source tables are preserved. Any fixes or reporting-friendly
-- transformations are handled later in the cleaning layer.
-- ============================================================


-- ============================================================
-- 1. TABLE GRAIN / KEY VALIDATION
-- ============================================================

-- ------------------------------------------------------------
-- customers
-- Grain: one row per customer_id
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids
FROM customers;

-- Result:
-- row_count = 99,441
-- distinct_customer_ids = 99,441
-- Conclusion: customer_id is unique.


-- ------------------------------------------------------------
-- orders
-- Grain: one row per order_id
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT order_id) AS distinct_order_ids
FROM orders;

-- Result:
-- row_count = 99,441
-- distinct_order_ids = 99,441
-- Conclusion: order_id is unique.


-- ------------------------------------------------------------
-- order_items
-- Grain: one row per item within an order
-- Composite key: (order_id, order_item_id)
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT (order_id, order_item_id)) AS distinct_rows
FROM order_items;

-- Result:
-- row_count = 112,650
-- distinct_rows = 112,650
-- Conclusion: (order_id, order_item_id) is unique.


-- ------------------------------------------------------------
-- payments
-- Grain: one payment sequence within an order
-- Composite key: (order_id, payment_sequential)
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT (order_id, payment_sequential)) AS distinct_rows
FROM payments;

-- Result:
-- row_count = 103,886
-- distinct_rows = 103,886
-- Conclusion: (order_id, payment_sequential) is unique.


-- ------------------------------------------------------------
-- products
-- Grain: one row per product_id
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT product_id) AS distinct_product_ids
FROM products;

-- Result:
-- row_count = 32,951
-- distinct_product_ids = 32,951
-- Conclusion: product_id is unique.


-- ------------------------------------------------------------
-- sellers
-- Grain: one row per seller_id
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT seller_id) AS distinct_seller_ids
FROM sellers;

-- Result:
-- row_count = 3,095
-- distinct_seller_ids = 3,095
-- Conclusion: seller_id is unique.


-- ------------------------------------------------------------
-- product_category_translation
-- Grain: one row per Portuguese category name
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT product_category_name) AS distinct_category_names
FROM product_category_translation;

-- Result:
-- row_count = 71
-- distinct_category_names = 71
-- Conclusion: product_category_name is unique.


-- ------------------------------------------------------------
-- reviews
-- Grain: one review record identified by (review_id, order_id)
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT (review_id, order_id)) AS distinct_review_order_pairs
FROM reviews;

-- Conclusion:
-- (review_id, order_id) behaves as a composite key.


-- ------------------------------------------------------------
-- geolocation
-- Raw grain is not one row per zip prefix.
-- Multiple coordinates may exist for the same prefix.
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zip_prefixes
FROM geolocation;

-- Result:
-- row_count = 1,000,163
-- distinct_zip_prefixes = 19,015
-- Conclusion:
-- geolocation_zip_code_prefix is not unique.
-- The raw table must not be joined directly to customers or sellers
-- for analysis because it can multiply rows.


-- Check exact duplicate geolocation rows.
WITH duplicate_geolocation_groups AS (
    SELECT
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state,
        COUNT(*) AS row_count
    FROM geolocation
    GROUP BY
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state
    HAVING COUNT(*) > 1
)
SELECT
    SUM(row_count - 1) AS excess_duplicate_rows
FROM duplicate_geolocation_groups;

-- IMPORTANT:
-- Use SUM(row_count - 1), not SUM(row_count) - 1.
-- The latter subtracts only one row overall rather than one retained
-- row from each duplicate group.
-- Rerun this query if the previous duplicate total was produced using
-- the old formula.


-- ============================================================
-- 2. MISSING VALUES / FIELD VALIDITY
-- ============================================================

-- ------------------------------------------------------------
-- orders
-- Date fields were imported as text at this stage.
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE order_purchase_timestamp = '') AS blank_purchase_timestamp,
    COUNT(*) FILTER (WHERE order_approved_at = '') AS blank_approved_at,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date = '') AS blank_carrier_date,
    COUNT(*) FILTER (WHERE order_delivered_customer_date = '') AS blank_delivered_customer_date,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date = '') AS blank_estimated_delivery_date
FROM orders;

-- Missing timestamps are mostly consistent with order status.
-- Check missing customer-delivery timestamps by status.
SELECT
    order_status,
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date = ''
    ) AS missing_delivery_date
FROM orders
GROUP BY order_status
ORDER BY COUNT(*) DESC;

-- Inspect delivered orders with missing delivery-related timestamps.
SELECT *
FROM orders
WHERE order_status = 'delivered'
  AND (
      order_approved_at = ''
      OR order_delivered_carrier_date = ''
      OR order_delivered_customer_date = ''
  );

-- Known delivered-order exceptions:
-- 14 missing approval dates
-- 2 missing carrier dates
-- 8 missing customer delivery dates
--
-- No reliable replacement values were identified.
-- These rows are retained but excluded from metrics that require the
-- missing timestamp.


-- ------------------------------------------------------------
-- products
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE product_id = '') AS product_id_blanks,
    COUNT(*) FILTER (WHERE product_category_name = '') AS category_name_blanks,
    COUNT(*) FILTER (WHERE product_name_lenght IS NULL) AS name_length_blanks,
    COUNT(*) FILTER (WHERE product_description_lenght IS NULL) AS description_length_blanks,
    COUNT(*) FILTER (WHERE product_photos_qty IS NULL) AS photos_blanks,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS weight_blanks,
    COUNT(*) FILTER (WHERE product_length_cm IS NULL) AS length_blanks,
    COUNT(*) FILTER (WHERE product_height_cm IS NULL) AS height_blanks,
    COUNT(*) FILTER (WHERE product_width_cm IS NULL) AS width_blanks
FROM products;

-- Check the repeated incomplete-metadata pattern.
SELECT
    COUNT(*) FILTER (
        WHERE product_category_name = ''
          AND product_name_lenght IS NULL
          AND product_description_lenght IS NULL
          AND product_photos_qty IS NULL
    ) AS incomplete_metadata_products
FROM products;

-- Result:
-- 610 products are simultaneously missing category name,
-- product name length, description length and photo quantity.
-- This looks like a consistent incomplete-metadata pattern rather
-- than unrelated missing values.


-- Find products with any missing physical dimension.
SELECT *
FROM products
WHERE product_weight_g IS NULL
   OR product_length_cm IS NULL
   OR product_height_cm IS NULL
   OR product_width_cm IS NULL;

-- Two products contain unusually incomplete metadata.
-- Both appear in order_items; one appears across 16 orders.
-- Retain these transactions for sales analysis, but exclude the rows
-- from analyses that require the missing product attributes.


-- ------------------------------------------------------------
-- customers
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE customer_id = '') AS id_blanks,
    COUNT(*) FILTER (WHERE customer_unique_id = '') AS unique_id_blanks,
    COUNT(*) FILTER (WHERE customer_zip_code_prefix IS NULL) AS zip_blanks,
    COUNT(*) FILTER (WHERE customer_city = '') AS city_blanks,
    COUNT(*) FILTER (WHERE customer_state = '') AS state_blanks
FROM customers;

-- Result: no missing values in the checked fields.


-- ------------------------------------------------------------
-- sellers
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE seller_id = '') AS id_blanks,
    COUNT(*) FILTER (WHERE seller_zip_code_prefix IS NULL) AS zip_blanks,
    COUNT(*) FILTER (WHERE seller_city = '') AS city_blanks,
    COUNT(*) FILTER (WHERE seller_state = '') AS state_blanks
FROM sellers;

-- Result: no missing values in the checked fields.


-- ------------------------------------------------------------
-- payments
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE order_id = '') AS id_blanks,
    COUNT(*) FILTER (WHERE payment_sequential IS NULL) AS sequential_blanks,
    COUNT(*) FILTER (WHERE payment_type = '') AS payment_type_blanks,
    COUNT(*) FILTER (WHERE payment_installments IS NULL) AS installments_blanks,
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS value_blanks
FROM payments;

-- Result: no missing values in the checked fields.


-- Check non-positive payment values.
SELECT
    COUNT(*) FILTER (WHERE payment_sequential <= 0) AS invalid_payment_sequence,
    COUNT(*) FILTER (WHERE payment_installments <= 0) AS non_positive_installments,
    COUNT(*) FILTER (WHERE payment_value <= 0) AS non_positive_payment_value
FROM payments;

-- Inspect the exceptions.
SELECT *
FROM payments
WHERE payment_installments <= 0
   OR payment_value <= 0;

-- Payment types.
SELECT
    payment_type,
    COUNT(*) AS row_count
FROM payments
GROUP BY payment_type
ORDER BY row_count DESC;

-- Findings:
-- 2 rows have payment_installments = 0 despite positive payment values.
-- 9 rows have payment_value = 0; none are negative.
-- Zero-value payments are mostly vouchers, plus 3 not_defined rows.
-- These records are retained as source-data exceptions.


-- ------------------------------------------------------------
-- order_items
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE order_id = '') AS order_id_blanks,
    COUNT(*) FILTER (WHERE order_item_id IS NULL) AS order_item_id_blanks,
    COUNT(*) FILTER (WHERE product_id = '') AS product_id_blanks,
    COUNT(*) FILTER (WHERE seller_id = '') AS seller_id_blanks,
    COUNT(*) FILTER (WHERE shipping_limit_date = '') AS date_blanks,
    COUNT(*) FILTER (WHERE price IS NULL) AS price_blanks,
    COUNT(*) FILTER (WHERE freight_value IS NULL) AS freight_blanks
FROM order_items;

-- Result: no missing values in the checked fields.


SELECT
    COUNT(*) FILTER (WHERE order_item_id <= 0) AS invalid_order_item_id,
    COUNT(*) FILTER (WHERE price <= 0) AS non_positive_price,
    COUNT(*) FILTER (WHERE freight_value <= 0) AS non_positive_freight
FROM order_items;

-- Findings:
-- No zero/negative prices.
-- 383 rows have freight_value = 0.
-- These rows otherwise appear valid and are retained.
-- shipping_limit_date is text at this stage and will be converted
-- during cleaning.


-- ------------------------------------------------------------
-- reviews
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE review_id = '') AS review_id_blanks,
    COUNT(*) FILTER (WHERE order_id = '') AS order_id_blanks,
    COUNT(*) FILTER (WHERE review_score IS NULL) AS review_score_nulls,
    COUNT(*) FILTER (WHERE review_creation_date = '') AS creation_date_blanks,
    COUNT(*) FILTER (WHERE review_answer_timestamp = '') AS answer_timestamp_blanks
FROM reviews;

-- Result: no missing values in the checked fields.


-- Rating validity: expected range is 1 to 5.
SELECT *
FROM reviews
WHERE review_score <= 0
   OR review_score > 5;

-- Result: no invalid review scores.


-- Check exact duplicate structured review rows.
SELECT
    review_id,
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp,
    COUNT(*) AS duplicate_reviews
FROM reviews
GROUP BY
    review_id,
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp
HAVING COUNT(*) > 1;

-- Result: no exact duplicate rows.


-- ============================================================
-- 3. REFERENTIAL INTEGRITY / CROSS-TABLE COVERAGE
-- ============================================================

-- ------------------------------------------------------------
-- orders -> customers
-- ------------------------------------------------------------
SELECT COUNT(*) AS unmatched_orders
FROM orders o
LEFT JOIN customers c
    ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

-- Result: 0
-- Every order has a matching customer record.


-- ------------------------------------------------------------
-- orders -> order_items
-- ------------------------------------------------------------
SELECT COUNT(*) AS orders_without_items
FROM orders o
LEFT JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;

-- Result: 775


SELECT
    order_status,
    COUNT(*) AS order_count
FROM orders o
LEFT JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY order_status
ORDER BY order_count DESC;

-- Findings:
-- 603 unavailable
-- 164 canceled
-- 5 created
-- 2 invoiced
-- 1 shipped
--
-- 767 of 775 are canceled or unavailable.
-- The remaining 8 are retained as minor source-data exceptions.


-- ------------------------------------------------------------
-- order_items -> orders
-- ------------------------------------------------------------
SELECT COUNT(*) AS orphaned_order_items
FROM order_items oi
LEFT JOIN orders o
    ON o.order_id = oi.order_id
WHERE o.order_id IS NULL;

-- Result: 0


-- ------------------------------------------------------------
-- order_items <-> products
-- ------------------------------------------------------------
SELECT COUNT(*) AS order_items_without_product
FROM order_items oi
LEFT JOIN products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Result: 0


SELECT COUNT(*) AS products_never_ordered
FROM products p
LEFT JOIN order_items oi
    ON oi.product_id = p.product_id
WHERE oi.product_id IS NULL;

-- Result: 0
-- Every product is used by at least one order_item.


-- ------------------------------------------------------------
-- order_items <-> sellers
-- ------------------------------------------------------------
SELECT COUNT(*) AS order_items_without_seller
FROM order_items oi
LEFT JOIN sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

-- Result: 0


SELECT COUNT(*) AS sellers_without_order_items
FROM sellers s
LEFT JOIN order_items oi
    ON oi.seller_id = s.seller_id
WHERE oi.seller_id IS NULL;

-- Result: 0
-- Every seller appears in order_items.


-- ------------------------------------------------------------
-- payments <-> orders
-- ------------------------------------------------------------
SELECT COUNT(*) AS payments_without_order
FROM payments p
LEFT JOIN orders o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Result: 0


SELECT COUNT(*) AS orders_without_payment
FROM orders o
LEFT JOIN payments p
    ON p.order_id = o.order_id
WHERE p.order_id IS NULL;

-- Result: 1


SELECT
    o.order_id,
    o.order_status
FROM orders o
LEFT JOIN payments p
    ON p.order_id = o.order_id
WHERE p.order_id IS NULL;

-- Finding:
-- 1 delivered order has no matching payment record.
-- Retained as a source-data exception.


-- ------------------------------------------------------------
-- order_items <-> payments
-- Coverage check at order level.
-- These are one-to-many tables, so DISTINCT order_id is important.
-- ------------------------------------------------------------
SELECT COUNT(DISTINCT oi.order_id) AS item_orders_without_payment
FROM order_items oi
LEFT JOIN payments p
    ON oi.order_id = p.order_id
WHERE p.order_id IS NULL;

-- Result: 1 order


SELECT COUNT(DISTINCT p.order_id) AS payment_orders_without_items
FROM payments p
LEFT JOIN order_items oi
    ON p.order_id = oi.order_id
WHERE oi.order_id IS NULL;

-- Result: 775 orders

-- This is consistent with the known set of orders without order_items.
-- These checks describe coverage and should not be interpreted as a
-- broken direct foreign-key relationship between order_items and payments.


-- ------------------------------------------------------------
-- products <-> product_category_translation
-- ------------------------------------------------------------
SELECT
    p.product_category_name,
    COUNT(*) AS product_count
FROM products p
LEFT JOIN product_category_translation pct
    ON p.product_category_name = pct.product_category_name
WHERE pct.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY product_count DESC;

-- Findings:
-- 623 products do not match the raw translation table.
-- 610 have missing product_category_name values.
-- The remaining 13 use two categories absent from the supplied
-- translation table:
--   pc_gamer = 3 products
--   portateis_cozinha_e_preparadores_de_alimentos = 10 products


SELECT COUNT(*) AS unused_translation_categories
FROM product_category_translation pct
LEFT JOIN products p
    ON pct.product_category_name = p.product_category_name
WHERE p.product_category_name IS NULL;

-- Result: 0
-- Every category supplied in the translation table is used.


-- ------------------------------------------------------------
-- reviews -> orders
-- ------------------------------------------------------------
SELECT COUNT(*) AS reviews_without_order
FROM reviews r
LEFT JOIN orders o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Result: 0
-- Every review references a valid order.


-- ------------------------------------------------------------
-- orders -> reviews
-- ------------------------------------------------------------
SELECT COUNT(*) AS orders_without_review
FROM orders o
LEFT JOIN reviews r
    ON r.order_id = o.order_id
WHERE r.order_id IS NULL;

-- Result: 768


SELECT
    order_status,
    COUNT(*) AS order_count
FROM orders o
LEFT JOIN reviews r
    ON r.order_id = o.order_id
WHERE r.order_id IS NULL
GROUP BY order_status
ORDER BY order_count DESC;

-- Findings:
-- 768 orders have no review record.
-- 646 are delivered.
-- Missing reviews are therefore not limited to canceled or incomplete
-- orders. Review analysis has high coverage, but not complete coverage.


-- ------------------------------------------------------------
-- reviews <-> order_items
-- Coverage check at distinct-order level.
-- ------------------------------------------------------------
SELECT COUNT(DISTINCT r.order_id) AS reviewed_orders_without_items
FROM reviews r
LEFT JOIN order_items oi
    ON r.order_id = oi.order_id
WHERE oi.order_id IS NULL;

-- Result: 756


SELECT COUNT(DISTINCT oi.order_id) AS item_orders_without_review
FROM order_items oi
LEFT JOIN reviews r
    ON r.order_id = oi.order_id
WHERE r.order_id IS NULL;

-- Result: 749

-- These are coverage gaps rather than necessarily broken relationships.


-- ------------------------------------------------------------
-- geolocation relationship checks
-- ------------------------------------------------------------
-- Do not validate customer/seller geographic joins against the raw
-- geolocation table because multiple rows per zip prefix would multiply
-- records. Those checks are performed after creating a cleaned
-- one-row-per-prefix geolocation view.


-- ============================================================
-- 4. VALIDATION SUMMARY / KNOWN EXCEPTIONS
-- ============================================================
-- Overall conclusion:
-- The dataset is suitable for analysis, but several known exceptions
-- should be preserved and handled explicitly rather than "fixed" by
-- inventing values.
--
-- Key exceptions identified:
-- 1. 775 orders have no order_items; 767 are canceled/unavailable.
-- 2. 1 delivered order has no payment record.
-- 3. A small number of delivered orders have missing approval/carrier/
--    delivery timestamps.
-- 4. 610 products have incomplete category/name-description/photo metadata.
-- 5. 13 products use 2 category names missing from the raw translation table.
-- 6. 2 payment rows have zero installments; 9 have payment_value = 0.
-- 7. 383 order_item rows have freight_value = 0.
-- 8. 768 orders have no review record; 646 of them are delivered.
-- 9. Raw geolocation contains repeated/multiple coordinates per zip prefix
--    and must be cleaned before geographic joins.
--
-- These exceptions are retained in the raw data and handled in the
-- cleaning/analysis layer where appropriate.
