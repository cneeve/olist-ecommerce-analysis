-- ============================================================
-- OLIST E-COMMERCE DATASET
-- 02 - DATA CLEANING / ANALYSIS PREPARATION
-- ============================================================
-- Purpose:
-- Convert imported text fields to suitable data types, standardise
-- reporting fields, and create analysis-ready views while preserving
-- the original source structure as much as possible.
--
-- NOTE:
-- The ALTER TABLE statements below are one-time type corrections.
-- Once the columns have been converted to timestamp, those statements
-- should not be rerun against the same database without adjustment.
-- ============================================================


-- ============================================================
-- 1. DATE / TIMESTAMP CLEANING
-- ============================================================

-- ------------------------------------------------------------
-- orders
-- Empty strings must be converted to NULL before text -> timestamp.
-- ------------------------------------------------------------
UPDATE orders
SET order_approved_at = NULL
WHERE order_approved_at = '';

UPDATE orders
SET order_delivered_carrier_date = NULL
WHERE order_delivered_carrier_date = '';

UPDATE orders
SET order_delivered_customer_date = NULL
WHERE order_delivered_customer_date = '';


-- Convert imported text date fields to timestamp.
ALTER TABLE orders
ALTER COLUMN order_purchase_timestamp TYPE timestamp
USING order_purchase_timestamp::timestamp;

ALTER TABLE orders
ALTER COLUMN order_approved_at TYPE timestamp
USING order_approved_at::timestamp;

ALTER TABLE orders
ALTER COLUMN order_delivered_carrier_date TYPE timestamp
USING order_delivered_carrier_date::timestamp;

ALTER TABLE orders
ALTER COLUMN order_delivered_customer_date TYPE timestamp
USING order_delivered_customer_date::timestamp;

ALTER TABLE orders
ALTER COLUMN order_estimated_delivery_date TYPE timestamp
USING order_estimated_delivery_date::timestamp;


-- ------------------------------------------------------------
-- order_items
-- ------------------------------------------------------------
ALTER TABLE order_items
ALTER COLUMN shipping_limit_date TYPE timestamp
USING shipping_limit_date::timestamp;


-- ------------------------------------------------------------
-- reviews
-- ------------------------------------------------------------
ALTER TABLE reviews
ALTER COLUMN review_creation_date TYPE timestamp
USING review_creation_date::timestamp;

ALTER TABLE reviews
ALTER COLUMN review_answer_timestamp TYPE timestamp
USING review_answer_timestamp::timestamp;


-- ============================================================
-- 2. CLEANED PRODUCT VIEW
-- ============================================================
-- Correct source-column spelling while keeping raw values unchanged.
CREATE OR REPLACE VIEW product_view AS
SELECT
    product_id,
    product_category_name,
    product_name_lenght AS product_name_length,
    product_description_lenght AS product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM products;


-- ============================================================
-- 3. CLEANED ORDER ITEMS / PAYMENTS VIEWS
-- ============================================================
-- Raw monetary fields were imported as floating-point values.
-- Cast individual values to NUMERIC before aggregation to avoid
-- floating-point rounding artefacts in revenue calculations.

CREATE OR REPLACE VIEW order_items_view AS
SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price::numeric(12,2) AS price,
    freight_value::numeric(12,2) AS freight_value
FROM order_items;


CREATE OR REPLACE VIEW payments_view AS
SELECT
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value::numeric(12,2) AS payment_value
FROM payments;


-- ============================================================
-- 4. CLEANED GEOLOCATION VIEW
-- ============================================================
-- The raw geolocation table contains repeated coordinate rows and
-- multiple coordinate pairs for a single zip prefix.
--
-- First deduplicate complete (zip, lat, lng) coordinate pairs.
-- Then calculate one representative coordinate per zip prefix.
--
-- Do NOT use AVG(DISTINCT lat) and AVG(DISTINCT lng) separately,
-- because that would break the original latitude/longitude pairing.

CREATE OR REPLACE VIEW geolocation_view AS
WITH geolocation_cte AS (
    SELECT DISTINCT
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng
    FROM geolocation
)
SELECT
    geolocation_zip_code_prefix,
    AVG(geolocation_lat) AS avg_geolocation_lat,
    AVG(geolocation_lng) AS avg_geolocation_lng
FROM geolocation_cte
GROUP BY geolocation_zip_code_prefix;


-- Sanity check:
-- Expected row count = 19,015 (one row per zip prefix).
SELECT COUNT(*) AS geolocation_view_rows
FROM geolocation_view;


-- ============================================================
-- 5. CLEANED PRODUCT CATEGORY TRANSLATION VIEW
-- ============================================================
-- Preserve:
--   1) original Portuguese category
--   2) supplied English translation
--   3) cleaned display label for reporting
--
-- Most labels are formatted automatically from the supplied English
-- translation. CASE handles labels that are awkward or unclear.
-- Two source categories missing from the supplied translation table
-- are added explicitly with UNION ALL.

CREATE OR REPLACE VIEW product_category_translation_view AS
SELECT
    product_category_name,
    product_category_name_english,
    CASE
        WHEN product_category_name_english = 'health_beauty'
            THEN 'Health & Beauty'
        WHEN product_category_name_english = 'auto'
            THEN 'Automotive'
        WHEN product_category_name_english = 'bed_bath_table'
            THEN 'Bed, Bath & Table'
        WHEN product_category_name_english = 'furniture_decor'
            THEN 'Furniture & Decor'
        WHEN product_category_name_english = 'sports_leisure'
            THEN 'Sports & Leisure'
        WHEN product_category_name_english = 'housewares'
            THEN 'Houseware'
        WHEN product_category_name_english = 'telephony'
            THEN 'Telephones'
        WHEN product_category_name_english = 'watches_gifts'
            THEN 'Watches & Gifts'
        WHEN product_category_name_english = 'food_drink'
            THEN 'Food & Drink'
        WHEN product_category_name_english = 'tablets_printing_image'
            THEN 'Tablets, Printing & Imaging'
        WHEN product_category_name_english = 'fixed_telephony'
            THEN 'Landline'
        WHEN product_category_name_english = 'luggage_accessories'
            THEN 'Luggage Accessories'
        WHEN product_category_name_english = 'consoles_games'
            THEN 'Consoles & Games'
        WHEN product_category_name_english = 'construction_tools_construction'
            THEN 'Construction Tools'
        WHEN product_category_name_english = 'furniture_kitchen_dining_laundry_garden'
            THEN 'Kitchen, Dining, Laundry & Garden Furniture'
        WHEN product_category_name_english = 'construction_tools_garden'
            THEN 'Construction & Garden Tools'
        WHEN product_category_name_english = 'fashion_male_clothing'
            THEN 'Men''s Clothing'
        WHEN product_category_name_english = 'market_place'
            THEN 'Marketplace'
        WHEN product_category_name_english = 'home_confort'
            THEN 'Home Comfort'
        WHEN product_category_name_english = 'construction_tools_tools'
            THEN 'Construction Tools & Equipment'
        WHEN product_category_name_english = 'agro_industry_and_commerce'
            THEN 'Agriculture, Industry & Commerce'
        WHEN product_category_name_english = 'furniture_mattress_and_upholstery'
            THEN 'Furniture, Mattresses & Upholstery'
        WHEN product_category_name_english = 'books_technical'
            THEN 'Technical Books'
        WHEN product_category_name_english = 'furniture_living_room'
            THEN 'Living Room Furniture'
        WHEN product_category_name_english = 'construction_tools_lights'
            THEN 'Construction Lighting'
        WHEN product_category_name_english = 'industry_commerce_and_business'
            THEN 'Industry, Commerce & Business'
        WHEN product_category_name_english = 'furniture_bedroom'
            THEN 'Bedroom Furniture'
        WHEN product_category_name_english = 'books_general_interest'
            THEN 'General Interest Books'
        WHEN product_category_name_english = 'construction_tools_safety'
            THEN 'Construction Safety Equipment'
        WHEN product_category_name_english = 'fashion_underwear_beach'
            THEN 'Underwear & Beachwear'
        WHEN product_category_name_english = 'fashion_sport'
            THEN 'Sports Fashion'
        WHEN product_category_name_english = 'signaling_and_security'
            THEN 'Signage & Security'
        WHEN product_category_name_english = 'fashion_womens_clothing'
            THEN 'Women''s Clothing'
        WHEN product_category_name_english = 'books_imported'
            THEN 'Imported Books'
        WHEN product_category_name_english = 'cine_photo'
            THEN 'Photo & Video'
        WHEN product_category_name_english = 'la_cuisine'
            THEN 'Kitchen'
        WHEN product_category_name_english = 'small_appliances_home_oven_and_coffee'
            THEN 'Small Home Appliances, Oven & Coffee'
        WHEN product_category_name_english = 'cds_dvds_musicals'
            THEN 'Music CDs & DVDs'
        WHEN product_category_name_english = 'dvds_blu_ray'
            THEN 'DVDs & Blu-ray'
        WHEN product_category_name_english = 'arts_and_craftmanship'
            THEN 'Arts & Crafts'
        WHEN product_category_name_english = 'diapers_and_hygiene'
            THEN 'Diapers & Hygiene'
        WHEN product_category_name_english = 'fashion_childrens_clothes'
            THEN 'Children''s Clothes'
        WHEN product_category_name_english = 'security_and_services'
            THEN 'Insurance & Services'
        ELSE INITCAP(REPLACE(product_category_name_english, '_', ' '))
    END AS product_category_name_clean
FROM product_category_translation

UNION ALL

SELECT
    'pc_gamer',
    'PC Gaming',
    'PC Gaming'

UNION ALL

SELECT
    'portateis_cozinha_e_preparadores_de_alimentos',
    'Food Processors',
    'Food Processors';


-- ============================================================
-- 6. PRODUCT ANALYSIS VIEW
-- ============================================================
-- Join cleaned product fields to reporting-friendly category labels.
-- Products with no source category are retained and labelled Unknown
-- only in the final reporting field.

CREATE OR REPLACE VIEW product_analysis_view AS
SELECT
    pv.*,
    pctv.product_category_name_english,
    pctv.product_category_name_clean,
    COALESCE(
        pctv.product_category_name_clean,
        'Unknown'
    ) AS product_category_final
FROM product_view pv
LEFT JOIN product_category_translation_view pctv
    ON pv.product_category_name = pctv.product_category_name;


-- Sanity checks:
-- Row count should match products = 32,951.
SELECT COUNT(*) AS product_analysis_rows
FROM product_analysis_view;

-- product_category_final should contain no NULL values.
SELECT COUNT(*) AS null_final_categories
FROM product_analysis_view
WHERE product_category_final IS NULL;


-- ============================================================
-- 7. ORDER ANALYSIS VIEW
-- ============================================================
-- Add commonly used analytical fields without altering raw orders.
--
-- delivery_time:
--   time from order purchase to customer delivery.
--
-- delivery_status:
--   compare DATE values rather than full timestamps because the
--   estimated delivery timestamp is commonly stored at midnight.
--   Same-day delivery should therefore count as On Time.

CREATE OR REPLACE VIEW order_view AS
SELECT
    o.*,
    DATE_TRUNC('month', order_purchase_timestamp) AS order_month,
    order_delivered_customer_date - order_purchase_timestamp AS delivery_time,
    CASE
        WHEN order_delivered_customer_date IS NULL THEN NULL
        WHEN order_estimated_delivery_date IS NULL THEN NULL
        WHEN order_delivered_customer_date::date >
             order_estimated_delivery_date::date
            THEN 'Late'
        ELSE 'On Time'
    END AS delivery_status
FROM orders o;


-- Sanity check:
-- Row count should match orders = 99,441.
SELECT COUNT(*) AS order_view_rows
FROM order_view;


-- ============================================================
-- 8. POST-CLEAN JOIN / COVERAGE CHECKS
-- ============================================================

-- ------------------------------------------------------------
-- Product category mapping
-- ------------------------------------------------------------
SELECT COUNT(*) AS products_without_clean_translation
FROM product_view pv
LEFT JOIN product_category_translation_view pctv
    ON pv.product_category_name = pctv.product_category_name
WHERE pctv.product_category_name IS NULL;

-- Expected result: 610
-- These are the known products with missing source category values.
-- The 13 previously unmatched non-null categories are now resolved.


SELECT COUNT(*) AS unused_clean_translation_categories
FROM product_category_translation_view pctv
LEFT JOIN product_view pv
    ON pctv.product_category_name = pv.product_category_name
WHERE pv.product_category_name IS NULL;

-- Expected result: 0


-- ------------------------------------------------------------
-- Customer geolocation coverage
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS unmatched_customer_rows,
    COUNT(DISTINCT c.customer_zip_code_prefix) AS unmatched_zip_prefixes
FROM customers c
LEFT JOIN geolocation_view gv
    ON c.customer_zip_code_prefix = gv.geolocation_zip_code_prefix
WHERE gv.geolocation_zip_code_prefix IS NULL;

-- Expected:
-- 278 customer records across 157 zip prefixes have no geolocation match.
-- Retain these customers; coordinate-based mapping is unavailable for them.


-- ------------------------------------------------------------
-- Seller geolocation coverage
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS unmatched_seller_rows,
    COUNT(DISTINCT s.seller_zip_code_prefix) AS unmatched_zip_prefixes
FROM sellers s
LEFT JOIN geolocation_view gv
    ON s.seller_zip_code_prefix = gv.geolocation_zip_code_prefix
WHERE gv.geolocation_zip_code_prefix IS NULL;

-- Expected:
-- 7 seller records across 7 zip prefixes have no geolocation match.
-- Retain these sellers; coordinate-based mapping is unavailable for them.


-- ============================================================
-- 9. CLEANING SUMMARY
-- ============================================================
-- Main cleaning decisions:
--
-- 1. Converted blank order timestamps to NULL before type conversion.
-- 2. Converted order, order_item and review date fields to timestamp.
-- 3. Corrected misspelled product length aliases in product_view.
-- 4. Converted monetary values to NUMERIC in analysis-ready views.
-- 5. Reduced raw geolocation to one representative row per zip prefix.
-- 6. Preserved source category taxonomy and supplied translations while
--    adding cleaner reporting labels.
-- 7. Added the two translation mappings missing from the supplied table.
-- 8. Labelled products with missing source category as Unknown only in the
--    final reporting field; raw category values remain unchanged.
-- 9. Added reusable order_month, delivery_time and delivery_status fields.
-- 10. Retained known source-data exceptions rather than inventing values.
--
-- Analysis should use the cleaned views where appropriate:
--   product_view
--   product_analysis_view
--   product_category_translation_view
--   order_items_view
--   payments_view
--   geolocation_view
--   order_view
