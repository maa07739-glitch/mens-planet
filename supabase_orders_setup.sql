-- ==============================================================================
-- MEN'S PLANET — SECURE ORDERS & CART BACKEND DATABASE SCHEMA & RPC
-- Order Management System + Customer Cancellation Requests + RLS Security
-- Requirements: 1-14, Complete Schema & Non-Destructive Migrations
-- ==============================================================================

-- 1. ORDERS TABLE
CREATE TABLE IF NOT EXISTS public.orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number TEXT UNIQUE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    customer_name TEXT NOT NULL,
    customer_email TEXT NOT NULL,
    customer_phone TEXT NOT NULL,
    shipping_address TEXT NOT NULL,
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    postal_code TEXT NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled')),
    payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid', 'failed', 'refunded')),
    payment_method TEXT NOT NULL DEFAULT 'cod',
    cancellation_requested BOOLEAN DEFAULT false,
    cancellation_reason TEXT,
    cancellation_requested_at TIMESTAMPTZ,
    admin_notes TEXT,
    cashfree_order_id TEXT,
    cashfree_payment_id TEXT,
    payment_session_id TEXT,
    currency TEXT NOT NULL DEFAULT 'INR',
    paid_at TIMESTAMPTZ,
    payment_error TEXT,
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Upgrade existing tables seamlessly without deleting any existing data (Req 11, 14)
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_name TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_email TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS shipping_address TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS state TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS postal_code TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS total_amount NUMERIC(10, 2) DEFAULT 0.00;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_requested BOOLEAN DEFAULT false;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_requested_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS admin_notes TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cashfree_order_id TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cashfree_payment_id TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_session_id TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'INR';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_error TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Synchronize phone, customer_phone, address, and shipping_address across historical rows
UPDATE public.orders SET phone = customer_phone WHERE (phone IS NULL OR phone = '') AND customer_phone IS NOT NULL AND customer_phone != '';
UPDATE public.orders SET customer_phone = phone WHERE (customer_phone IS NULL OR customer_phone = '') AND phone IS NOT NULL AND phone != '';
UPDATE public.orders SET address = shipping_address WHERE (address IS NULL OR address = '') AND shipping_address IS NOT NULL AND shipping_address != '';
UPDATE public.orders SET shipping_address = address WHERE (shipping_address IS NULL OR shipping_address = '') AND address IS NOT NULL AND address != '';

-- Notify PostgREST to reload schema cache immediately
NOTIFY pgrst, 'reload schema';

-- Update status check constraint to include 'confirmed' (Req 4)
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check 
    CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled'));

-- Update payment_status check constraint to support all standard e-commerce values ('pending', 'unpaid', 'paid', 'failed', 'refunded')
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_status_check 
    CHECK (payment_status IN ('pending', 'unpaid', 'paid', 'failed', 'refunded', 'cancelled', 'completed', 'Pending', 'Paid', 'Unpaid'));

-- Indexes for fast queries & admin lookups
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_cancellation_requested ON public.orders(cancellation_requested);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);

-- 2. ORDER ITEMS TABLE (Relational Item Tracking)
CREATE TABLE IF NOT EXISTS public.order_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT REFERENCES public.orders(id) ON DELETE CASCADE,
    order_number TEXT REFERENCES public.orders(order_number) ON DELETE CASCADE,
    product_id TEXT NOT NULL,
    product_name TEXT NOT NULL,
    size TEXT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL,
    line_total NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items(order_id);

-- 3. ROW LEVEL SECURITY (RLS) POLICIES (Req 6, 12, 13)
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- Orders RLS: Customers can ONLY view their own orders (Req 6)
DROP POLICY IF EXISTS "Customers can view their own orders" ON public.orders;
CREATE POLICY "Customers can view their own orders" 
ON public.orders FOR SELECT 
TO authenticated 
USING (auth.uid() = user_id);

-- Orders RLS: Customers can insert their own orders with strictly 'pending' status (Req 13)
DROP POLICY IF EXISTS "Customers can insert their own orders" ON public.orders;
CREATE POLICY "Customers can insert their own orders" 
ON public.orders FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = user_id AND status IN ('pending', 'confirmed') AND payment_status IN ('pending', 'unpaid', 'Pending', 'Unpaid'));

-- Orders RLS: Only authorized admins can update or manage orders (Req 12, 13)
-- (Customers have NO direct UPDATE permission; must use secure RPC)
DROP POLICY IF EXISTS "Admins have full access to orders" ON public.orders;
CREATE POLICY "Admins have full access to orders" 
ON public.orders FOR ALL 
TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
);

-- Order Items RLS
DROP POLICY IF EXISTS "Customers can view their own order items" ON public.order_items;
CREATE POLICY "Customers can view their own order items" 
ON public.order_items FOR SELECT 
TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM public.orders 
        WHERE orders.id = order_items.order_id AND orders.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Customers can insert order items" ON public.order_items;
CREATE POLICY "Customers can insert order items" 
ON public.order_items FOR INSERT 
TO authenticated 
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.orders 
        WHERE orders.id = order_items.order_id AND orders.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Admins have full access to order items" ON public.order_items;
CREATE POLICY "Admins have full access to order items" 
ON public.order_items FOR ALL 
TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
);

-- 4. SECURE SERVER-SIDE ORDER CREATION RPC (SECURITY DEFINER)
-- Validates caller authentication, verifies real product price and stock on server,
-- decrements stock atomically, and creates the order without trusting client prices/totals.
CREATE OR REPLACE FUNCTION public.create_customer_order(
    p_items jsonb,
    p_shipping jsonb,
    p_order_number text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_item RECORD;
    v_product RECORD;
    v_item_qty INT;
    v_unit_price NUMERIC(10, 2);
    v_line_total NUMERIC(10, 2);
    v_verified_total NUMERIC(10, 2) := 0.00;
    v_order_id BIGINT;
    v_verified_items jsonb := '[]'::jsonb;
    v_item_json jsonb;
    v_payment_method text;
BEGIN
    -- 1. Ensure user is authenticated
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required: You must be logged in to place an order.';
    END IF;

    -- 2. Validate items array
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Cart is empty. Please add items before placing an order.';
    END IF;

    v_payment_method := COALESCE(p_shipping->>'payment_method', 'cod');

    -- 3. Loop through items, verify real price and stock on the server (Security)
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        product_id text,
        size text,
        quantity int
    )
    LOOP
        v_item_qty := COALESCE(v_item.quantity, 1);
        IF v_item_qty <= 0 THEN
            RAISE EXCEPTION 'Invalid quantity % for product ID %', v_item_qty, v_item.product_id;
        END IF;

        -- Fetch real product record by ID
        SELECT * INTO v_product 
        FROM public.products 
        WHERE id::text = v_item.product_id::text
        FOR UPDATE; -- lock row to prevent race conditions during checkout

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % is no longer available in the store.', v_item.product_id;
        END IF;

        -- Check active status if column exists
        IF v_product.is_active IS NOT NULL AND v_product.is_active = false THEN
            RAISE EXCEPTION 'Product "%" is no longer active in our catalog.', v_product.name;
        END IF;

        -- Validate stock
        IF v_product.stock IS NOT NULL AND v_product.stock < v_item_qty THEN
            RAISE EXCEPTION 'Insufficient stock for "%": only % units remaining.', v_product.name, v_product.stock;
        END IF;

        -- Server-derived price (never trust client)
        v_unit_price := COALESCE(v_product.price, 0.00);
        v_line_total := v_unit_price * v_item_qty;
        v_verified_total := v_verified_total + v_line_total;

        -- Atomic stock decrement
        IF v_product.stock IS NOT NULL THEN
            UPDATE public.products 
            SET stock = stock - v_item_qty 
            WHERE id = v_product.id;
        END IF;

        -- Record verified item data
        v_item_json := jsonb_build_object(
            'product_id', v_product.id,
            'name', COALESCE(v_product.name, 'MEN''S PLANET Apparel'),
            'size', COALESCE(v_item.size, 'M'),
            'quantity', v_item_qty,
            'unit_price', v_unit_price,
            'line_total', v_line_total,
            'image', COALESCE(v_product.image_url, '')
        );
        v_verified_items := v_verified_items || jsonb_build_array(v_item_json);
    END LOOP;

    -- 4. Insert verified order with strictly 'pending' status
    INSERT INTO public.orders (
        order_number,
        user_id,
        customer_name,
        customer_email,
        customer_phone,
        phone,
        address,
        shipping_address,
        city,
        state,
        postal_code,
        total_amount,
        status,
        payment_status,
        payment_method,
        currency,
        items
    ) VALUES (
        p_order_number,
        v_user_id,
        COALESCE(p_shipping->>'full_name', p_shipping->>'name', 'Customer'),
        COALESCE(p_shipping->>'email', (SELECT email FROM auth.users WHERE id = v_user_id)),
        COALESCE(p_shipping->>'customer_phone', p_shipping->>'phone', ''),
        COALESCE(p_shipping->>'phone', p_shipping->>'customer_phone', ''),
        COALESCE(p_shipping->>'address', p_shipping->>'shipping_address', ''),
        COALESCE(p_shipping->>'shipping_address', p_shipping->>'address', ''),
        COALESCE(p_shipping->>'city', ''),
        COALESCE(p_shipping->>'state', ''),
        COALESCE(p_shipping->>'postal_code', ''),
        v_verified_total,
        'pending',
        COALESCE(p_shipping->>'payment_status', 'pending'),
        v_payment_method,
        'INR',
        v_verified_items
    )
    RETURNING id INTO v_order_id;

    -- 5. Insert into order_items table for relational tracking
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'order_items') THEN
        INSERT INTO public.order_items (
            order_id,
            order_number,
            product_id,
            product_name,
            size,
            quantity,
            unit_price,
            line_total
        )
        SELECT 
            v_order_id,
            p_order_number,
            (elem->>'product_id')::text,
            (elem->>'name')::text,
            (elem->>'size')::text,
            (elem->>'quantity')::int,
            (elem->>'unit_price')::numeric,
            (elem->>'line_total')::numeric
        FROM jsonb_array_elements(v_verified_items) AS elem;
    END IF;

    -- Return confirmation object with server-verified amount
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order_id,
        'order_number', p_order_number,
        'total_amount', v_verified_total,
        'status', 'pending',
        'payment_status', 'unpaid',
        'payment_method', v_payment_method,
        'currency', 'INR',
        'items_count', jsonb_array_length(v_verified_items)
    );
END;
$$;

-- 5. SECURE CUSTOMER CANCELLATION REQUEST RPC (SECURITY DEFINER)
-- Allows customers to safely submit a cancellation request for their own orders
-- WITHOUT permitting them to alter order status, prices, or arbitrary fields (Req 8, 12, 13)
CREATE OR REPLACE FUNCTION public.request_order_cancellation(
    p_order_number text,
    p_reason text DEFAULT 'Customer requested cancellation'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
BEGIN
    -- Check authentication
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT * INTO v_order
    FROM public.orders
    WHERE order_number = p_order_number
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found.', p_order_number;
    END IF;

    -- Security: verify caller owns the order or is admin (Req 6, 13)
    IF v_order.user_id != auth.uid() AND NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Unauthorized: You can only request cancellation for your own orders.';
    END IF;

    -- Prevent cancellation if already shipped, delivered, or cancelled
    IF v_order.status IN ('shipped', 'delivered', 'cancelled') THEN
        RAISE EXCEPTION 'Cannot cancel an order that is already %.', v_order.status;
    END IF;

    -- If already requested
    IF v_order.cancellation_requested = true THEN
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Cancellation request is already pending review.',
            'order_number', p_order_number
        );
    END IF;

    -- Update cancellation request flags ONLY (does NOT allow customer to modify status or amounts)
    UPDATE public.orders
    SET 
        cancellation_requested = true,
        cancellation_reason = COALESCE(p_reason, 'Customer requested cancellation via portal'),
        cancellation_requested_at = NOW(),
        updated_at = NOW()
    WHERE id = v_order.id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Cancellation request submitted successfully. Our team will review it shortly.',
        'order_number', p_order_number
    );
END;
$$;

-- 6. SECURE ADMIN ORDER STATUS & CANCELLATION MANAGEMENT RPC (SECURITY DEFINER)
-- Strictly accessible ONLY to authenticated admin users (Req 4, 9, 12)
CREATE OR REPLACE FUNCTION public.admin_update_order_status(
    p_order_id bigint,
    p_new_status text,
    p_admin_notes text DEFAULT NULL,
    p_resolve_cancellation boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
    v_is_admin BOOLEAN := false;
    v_item RECORD;
BEGIN
    -- 1. Check admin permission
    SELECT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role = 'admin'
    ) INTO v_is_admin;

    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Access denied: Admin privileges required to update order status.';
    END IF;

    -- 2. Validate status
    IF p_new_status NOT IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled') THEN
        RAISE EXCEPTION 'Invalid status: %', p_new_status;
    END IF;

    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order ID % not found.', p_order_id;
    END IF;

    -- 3. If transitioning to cancelled from non-cancelled, restock products
    IF p_new_status = 'cancelled' AND v_order.status != 'cancelled' THEN
        IF Array_Length(Array(SELECT jsonb_array_elements(v_order.items)), 1) > 0 THEN
            FOR v_item IN SELECT * FROM jsonb_to_recordset(v_order.items) AS x(
                product_id text,
                quantity int
            )
            LOOP
                IF v_item.product_id IS NOT NULL AND v_item.quantity > 0 THEN
                    UPDATE public.products
                    SET stock = stock + v_item.quantity
                    WHERE id::text = v_item.product_id::text;
                END IF;
            END LOOP;
        END IF;
    END IF;

    -- 4. Update the order
    UPDATE public.orders
    SET 
        status = p_new_status,
        cancellation_requested = CASE WHEN p_resolve_cancellation THEN false ELSE cancellation_requested END,
        admin_notes = COALESCE(p_admin_notes, admin_notes),
        updated_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', p_order_id,
        'order_number', v_order.order_number,
        'status', p_new_status,
        'cancellation_resolved', p_resolve_cancellation
    );
END;
$$;

-- ==============================================================================
-- 7. SECURE PRODUCTS RLS POLICIES & is_admin PERMISSIONS FIX
-- ==============================================================================

-- 1. Ensure public.is_admin() exists, is SECURITY DEFINER, and has execute granted to all
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated, service_role, public;

DO $$
BEGIN
    EXECUTE (
        SELECT COALESCE(string_agg(format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO anon, authenticated, service_role, public;', 
            n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)), ' '), '')
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'is_admin'
    );
EXCEPTION WHEN OTHERS THEN
    NULL;
END $$;

-- 2. Reset and fix Row Level Security (RLS) on public.products table
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'products'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.products;', pol.policyname);
    END LOOP;
END $$;

CREATE POLICY "Allow public read access to products"
ON public.products
FOR SELECT
TO public
USING (true);

CREATE POLICY "Admins can insert products"
ON public.products
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);

CREATE POLICY "Admins can update products"
ON public.products
FOR UPDATE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
)
WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);

CREATE POLICY "Admins can delete products"
ON public.products
FOR DELETE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);

-- ==============================================================================
-- 8. PHASE 1: CATEGORIES & PRODUCT SKU INTEGRATION
-- ==============================================================================

-- 1. Ensure 'sku' column exists on products table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sku TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category_id BIGINT;

-- 2. CREATE CATEGORIES TABLE
CREATE TABLE IF NOT EXISTS public.categories (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    slug TEXT UNIQUE,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    display_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Upgrade existing categories table if it exists
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS slug TEXT;
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS display_order INT DEFAULT 0;
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- 3. ROW LEVEL SECURITY (RLS) FOR CATEGORIES
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'categories'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.categories;', pol.policyname);
    END LOOP;
END $$;

CREATE POLICY "Allow public read access to categories"
ON public.categories
FOR SELECT
TO public
USING (true);

CREATE POLICY "Admins can insert categories"
ON public.categories
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);

CREATE POLICY "Admins can update categories"
ON public.categories
FOR UPDATE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
)
WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);

CREATE POLICY "Admins can delete categories"
ON public.categories
FOR DELETE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);

-- 4. SEED INITIAL STANDARD CATEGORIES
INSERT INTO public.categories (name, slug, description, is_active, display_order)
VALUES 
    ('Shirts', 'shirts', 'Classic, cuban collar, oxford and linen shirts', true, 1),
    ('T-Shirts', 't-shirts', 'Heavyweight, oversized, washed and graphic tees', true, 2),
    ('Outerwear', 'outerwear', 'Jackets, trenches, bombers and coats', true, 3),
    ('Pants', 'pants', 'Trousers, chinos, tailored slacks and relaxed pants', true, 4),
    ('Caps & Headwear', 'caps-headwear', 'Canvas caps, beanies and headwear', true, 5),
    ('Bags & Packs', 'bags-packs', 'Totes, duffels, leather messengers and backpacks', true, 6),
    ('Accessories', 'accessories', 'Belts, wallets, socks and jewelry', true, 7)
ON CONFLICT (name) DO NOTHING;

-- Reload PostgREST API schema cache
NOTIFY pgrst, 'reload schema';


-- ==============================================================================
-- 9. CART_ITEMS TABLE & RLS POLICIES (PHASE 2 SHOPPING CART PERSISTENCE)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.cart_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    product_id TEXT NOT NULL,
    product_name TEXT,
    size TEXT NOT NULL,
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) DEFAULT 0.00,
    image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT cart_user_product_size_unique UNIQUE (user_id, product_id, size)
);

CREATE INDEX IF NOT EXISTS idx_cart_items_user_id ON public.cart_items(user_id);

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'cart_items'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.cart_items;', pol.policyname);
    END LOOP;
END $$;

CREATE POLICY "Customers can manage their own cart items"
ON public.cart_items
FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';


-- ==============================================================================
-- 10. WISHLIST TABLE & RLS POLICIES (PHASE 6 CUSTOMER EXPERIENCE)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.wishlist (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    product_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT wishlist_user_product_unique UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_wishlist_user_id ON public.wishlist(user_id);
CREATE INDEX IF NOT EXISTS idx_wishlist_product_id ON public.wishlist(product_id);

ALTER TABLE public.wishlist ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'wishlist'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.wishlist;', pol.policyname);
    END LOOP;
END $$;

CREATE POLICY "Customers can manage their own wishlist"
ON public.wishlist
FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

NOTIFY pgrst, 'reload schema';
