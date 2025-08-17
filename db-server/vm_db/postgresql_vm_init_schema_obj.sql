--
-- Creative Energy Database Initialization Schema (Object Storage Version)
-- Compatible with PostgreSQL 16.8
-- Object Storage URL 적용 버전
--

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET statement_timeout = 0;
SET client_min_messages = warning;

-- Database must be created manually first:
-- CREATE DATABASE creative_energy_obj WITH ENCODING = 'UTF8';

-- Connect to creative_energy_obj database and run below:

--
-- SEQUENCES
--

CREATE SEQUENCE IF NOT EXISTS products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE IF NOT EXISTS inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE IF NOT EXISTS orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- TABLES
--

-- Products table
CREATE TABLE IF NOT EXISTS products (
    id integer NOT NULL DEFAULT nextval('products_id_seq'::regclass),
    title character varying(255) NOT NULL,
    subtitle character varying(255),
    price character varying(20) NOT NULL,
    price_numeric integer NOT NULL,
    image character varying(500),  -- Object Storage URL을 위해 길이 증가
    category character varying(50),
    type character varying(50),
    badge character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

-- Inventory table
CREATE TABLE IF NOT EXISTS inventory (
    id integer NOT NULL DEFAULT nextval('inventory_id_seq'::regclass),
    product_id integer NOT NULL,
    stock_quantity integer DEFAULT 100 NOT NULL,
    reserved_quantity integer DEFAULT 0 NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

-- Orders table
CREATE TABLE IF NOT EXISTS orders (
    id integer NOT NULL DEFAULT nextval('orders_id_seq'::regclass),
    customer_name character varying(100) NOT NULL,
    product_id integer NOT NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    total_price integer NOT NULL,
    order_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(20) DEFAULT 'completed'::character varying
);

--
-- FUNCTIONS
--

-- Function to process order inventory
CREATE OR REPLACE FUNCTION process_order_inventory(p_product_id integer, p_quantity integer) 
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    current_stock INTEGER;
BEGIN
    -- Get current stock with lock
    SELECT stock_quantity INTO current_stock 
    FROM inventory 
    WHERE product_id = p_product_id
    FOR UPDATE;
    
    -- Check if stock is sufficient
    IF current_stock IS NULL OR current_stock < p_quantity THEN
        RETURN FALSE;
    END IF;
    
    -- Reduce stock
    UPDATE inventory 
    SET stock_quantity = stock_quantity - p_quantity,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = p_product_id;
    
    RETURN TRUE;
END;
$$;

-- Function to reset daily inventory
CREATE OR REPLACE FUNCTION reset_daily_inventory() 
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE inventory 
    SET stock_quantity = 100, 
        reserved_quantity = 0,
        updated_at = CURRENT_TIMESTAMP;
    
    RAISE NOTICE 'Daily inventory reset completed at %', CURRENT_TIMESTAMP;
END;
$$;

-- Function to update inventory timestamp
CREATE OR REPLACE FUNCTION update_inventory_timestamp() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

-- Function to update products timestamp
CREATE OR REPLACE FUNCTION update_products_timestamp() 
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

--
-- PRIMARY KEY CONSTRAINTS
--

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'products_pkey' AND contype = 'p'
    ) THEN
        ALTER TABLE ONLY products ADD CONSTRAINT products_pkey PRIMARY KEY (id);
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'inventory_pkey' AND contype = 'p'
    ) THEN
        ALTER TABLE ONLY inventory ADD CONSTRAINT inventory_pkey PRIMARY KEY (id);
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'orders_pkey' AND contype = 'p'
    ) THEN
        ALTER TABLE ONLY orders ADD CONSTRAINT orders_pkey PRIMARY KEY (id);
    END IF;
END;
$$;

--
-- INDEXES
--

CREATE INDEX IF NOT EXISTS idx_products_category ON products USING btree (category);
CREATE INDEX IF NOT EXISTS idx_products_type ON products USING btree (type);
CREATE INDEX IF NOT EXISTS idx_inventory_product_id ON inventory USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_orders_product_id ON orders USING btree (product_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_date ON orders USING btree (order_date);
CREATE INDEX IF NOT EXISTS idx_orders_customer_name ON orders USING btree (customer_name);

--
-- FOREIGN KEY CONSTRAINTS
--

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'inventory_product_id_fkey'
    ) THEN
        ALTER TABLE inventory
            ADD CONSTRAINT inventory_product_id_fkey 
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'orders_product_id_fkey'
    ) THEN
        ALTER TABLE orders
            ADD CONSTRAINT orders_product_id_fkey 
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
    END IF;
END;
$$;

--
-- TRIGGERS
--

DO $$
BEGIN
    -- Drop trigger if exists and recreate
    DROP TRIGGER IF EXISTS trigger_update_inventory_timestamp ON inventory;
    CREATE TRIGGER trigger_update_inventory_timestamp 
        BEFORE UPDATE ON inventory 
        FOR EACH ROW EXECUTE FUNCTION update_inventory_timestamp();
    
    DROP TRIGGER IF EXISTS trigger_update_products_timestamp ON products;
    CREATE TRIGGER trigger_update_products_timestamp 
        BEFORE UPDATE ON products 
        FOR EACH ROW EXECUTE FUNCTION update_products_timestamp();
END;
$$;

--
-- VIEWS
--

CREATE OR REPLACE VIEW product_inventory_view AS
SELECT 
    p.id,
    p.title,
    p.subtitle,
    p.price,
    p.price_numeric,
    p.image,
    p.category,
    p.type,
    p.badge,
    COALESCE(i.stock_quantity, 0) AS stock_quantity,
    COALESCE(i.reserved_quantity, 0) AS reserved_quantity,
    CASE 
        WHEN COALESCE(i.stock_quantity, 0) = 0 THEN '매진'
        ELSE COALESCE(i.stock_quantity, 0)::text
    END AS stock_display
FROM products p
LEFT JOIN inventory i ON p.id = i.product_id;

--
-- INITIAL DATA (Object Storage URL 적용)
--

INSERT INTO products (id, title, subtitle, price, price_numeric, image, category, type, badge, created_at, updated_at) VALUES
(1, 'BigBoys 1st Full Album [SimplyFit] Standard Edition', 'Standard Edition', '18,500원', 18500, 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/bb_prod1.png', 'bigboys', 'album', 'NEW', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(2, 'BigBoys 1st Full Album [SimplyFit] Limited Edition', 'with Photo Book & Photo Cards', '35,000원', 35000, 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/bb_prod2.png', 'bigboys', 'album', 'LIMITED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(3, 'BigBoys Official Light Stick', 'Ver. 1.0', '42,000원', 42000, 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/bb_prod3.png', 'bigboys', 'goods', 'LIMITED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(4, 'BigBoys Official T-Shirt', 'Black / White Available', '28,000원', 28000, 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/bb_prod4.png', 'bigboys', 'goods', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(5, 'Cloudy 2nd Official Album [In the Sky]', 'Sky Blue Ver.', '16,800원', 16800, 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/cloudy_prod1.png', 'cloudy', 'album', 'NEW', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(6, 'Cloudy 1st Official Album [FEARLESS]', 'Purple Ver.', '16,800원', 16800, 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/cloudy_prod2.png', 'cloudy', 'album', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(7, 'Cloudy Official Merchandise', 'Eco Bag', '40,000원', 40000, 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/cloudy_prod3.png', 'cloudy', 'goods', 'LIMITED', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
(8, 'Cloudy Official Light Stick', 'Ver. 2.0', '42,000원', 42000, 'https://object-store.kr-west1.e.samsungsdscloud.com/thisneedstobereplaced1234:ceweb/media/img/cloudy_prod4.png', 'cloudy', 'goods', NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO NOTHING;

INSERT INTO inventory (id, product_id, stock_quantity, reserved_quantity, updated_at) VALUES
(1, 1, 100, 0, CURRENT_TIMESTAMP),
(2, 2, 100, 0, CURRENT_TIMESTAMP),
(3, 3, 100, 0, CURRENT_TIMESTAMP),
(4, 4, 100, 0, CURRENT_TIMESTAMP),
(5, 5, 100, 0, CURRENT_TIMESTAMP),
(6, 6, 100, 0, CURRENT_TIMESTAMP),
(7, 7, 100, 0, CURRENT_TIMESTAMP),
(8, 8, 100, 0, CURRENT_TIMESTAMP)
ON CONFLICT (id) DO NOTHING;

--
-- SEQUENCE ADJUSTMENTS
--

ALTER SEQUENCE products_id_seq OWNED BY products.id;
ALTER SEQUENCE inventory_id_seq OWNED BY inventory.id;
ALTER SEQUENCE orders_id_seq OWNED BY orders.id;

SELECT setval('products_id_seq', 8, true);
SELECT setval('inventory_id_seq', 8, true);
SELECT setval('orders_id_seq', 1, false);

-- Verification
SELECT 'Creative Energy Database Schema (Object Storage Version) Installation Complete!' as status;

-- Object Storage URL 확인
SELECT 
    id,
    title,
    image as object_storage_url
FROM products 
ORDER BY id;

-- Object Storage 설정 정보 표시
SELECT 
    'Object Storage 설정 정보' as info_type,
    'https://object-store.kr-west1.e.samsungsdscloud.com' as public_endpoint,
    'thisneedstobereplaced1234:ceweb' as bucket_info,
    'media/img, files/audition' as folder_structure;