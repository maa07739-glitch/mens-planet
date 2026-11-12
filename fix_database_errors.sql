-- ==============================================================================
-- MEN'S PLANET — COMPLETE DATABASE & RLS REPAIR SCRIPT
-- Fixes:
--   1. "permission denied for function is_admin" (Products & Categories loading)
--   2. "Could not find the 'customer_phone' column of 'orders' in the schema cache"
--   3. Orders table constraints (orders_payment_status_check, orders_status_check)
--   4. Public read access to product catalog
--   5. Wishlist table and RLS for Phase 6 Customer Experience
--
-- Instructions:
--   1. Open your Supabase Dashboard: https://supabase.com/dashboard
--   2. Navigate to SQL Editor (left sidebar)
--   3. Paste this entire script into a new query and click "Run" (Ctrl+Enter)
--   4. Refresh your Men's Planet website
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. FIX is_admin FUNCTION & PERMISSIONS (Eliminates "permission denied for function is_admin")
-- ------------------------------------------------------------------------------
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

-- Grant execution to all standard roles so queries never get permission denied
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated, service_role, public;

-- Grant execution on any other overload of is_admin if one exists
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


-- ------------------------------------------------------------------------------
-- 2. FIX PRODUCTS TABLE RLS (Enables Public Store Catalog Browsing)
-- ------------------------------------------------------------------------------
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Clean up any broken or restrictive policies on products
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

-- Policy 1: Everyone (anon & authenticated) can view all products
CREATE POLICY "Allow public read access to products"
ON public.products
FOR SELECT
TO public
USING (true);

-- Policy 2: Only administrators can create products
CREATE POLICY "Admins can insert products"
ON public.products
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);

-- Policy 3: Only administrators can update products
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

-- Policy 4: Only administrators can delete products
CREATE POLICY "Admins can delete products"
ON public.products
FOR DELETE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);


-- ------------------------------------------------------------------------------
-- 3. FIX CATEGORIES TABLE RLS (If table exists)
-- ------------------------------------------------------------------------------
DO $$
DECLARE
    pol RECORD;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'categories') THEN
        EXECUTE 'ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;';
        
        FOR pol IN 
            SELECT policyname 
            FROM pg_policies 
            WHERE schemaname = 'public' AND tablename = 'categories'
        LOOP
            EXECUTE format('DROP POLICY IF EXISTS %I ON public.categories;', pol.policyname);
        END LOOP;

        EXECUTE 'CREATE POLICY "Allow public read access to categories" ON public.categories FOR SELECT TO public USING (true);';
        
        EXECUTE 'CREATE POLICY "Admins can manage categories" ON public.categories FOR ALL TO authenticated USING (
            EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = ''admin'')
            OR COALESCE(public.is_admin(), false)
        );';
    END IF;
END $$;


-- ------------------------------------------------------------------------------
-- 4. FIX ORDERS TABLE COLUMNS & SCHEMA CACHE (Eliminates "customer_phone" schema error)
-- ------------------------------------------------------------------------------
-- Ensure public.orders table exists
CREATE TABLE IF NOT EXISTS public.orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number TEXT UNIQUE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    customer_name TEXT,
    customer_email TEXT,
    customer_phone TEXT,
    phone TEXT,
    address TEXT,
    shipping_address TEXT,
    city TEXT,
    state TEXT,
    postal_code TEXT,
    total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    status TEXT NOT NULL DEFAULT 'pending',
    payment_status TEXT NOT NULL DEFAULT 'pending',
    payment_method TEXT NOT NULL DEFAULT 'cod',
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add all potential missing columns non-destructively
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_name TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_email TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS shipping_address TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS state TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS postal_code TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS total_amount NUMERIC(10, 2) DEFAULT 0.00;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cod';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_requested BOOLEAN DEFAULT false;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancellation_requested_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS admin_notes TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Synchronize historical rows between phone and customer_phone
UPDATE public.orders SET phone = customer_phone WHERE (phone IS NULL OR phone = '') AND customer_phone IS NOT NULL AND customer_phone != '';
UPDATE public.orders SET customer_phone = phone WHERE (customer_phone IS NULL OR customer_phone = '') AND phone IS NOT NULL AND phone != '';
UPDATE public.orders SET address = shipping_address WHERE (address IS NULL OR address = '') AND shipping_address IS NOT NULL AND shipping_address != '';
UPDATE public.orders SET shipping_address = address WHERE (shipping_address IS NULL OR shipping_address = '') AND address IS NOT NULL AND address != '';

-- Relax or update constraints so orders are never rejected due to check constraints
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check 
    CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled'));

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_status_check 
    CHECK (payment_status IN ('pending', 'unpaid', 'paid', 'failed', 'refunded', 'cancelled', 'completed', 'Pending', 'Paid', 'Unpaid'));

-- ------------------------------------------------------------------------------
-- 5. ORDERS ROW LEVEL SECURITY (RLS)
-- ------------------------------------------------------------------------------
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view their own orders" ON public.orders;
CREATE POLICY "Customers can view their own orders" 
ON public.orders FOR SELECT 
TO authenticated 
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Customers can insert their own orders" ON public.orders;
CREATE POLICY "Customers can insert their own orders" 
ON public.orders FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins have full access to orders" ON public.orders;
CREATE POLICY "Admins have full access to orders" 
ON public.orders FOR ALL 
TO authenticated 
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);


-- ------------------------------------------------------------------------------
-- 6. ORDER ITEMS TABLE (Relational tracking if used)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.order_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT REFERENCES public.orders(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    product_id TEXT NOT NULL,
    product_name TEXT NOT NULL,
    size TEXT NOT NULL DEFAULT 'M',
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    line_total NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    product_image TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

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
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);


-- ------------------------------------------------------------------------------
-- 7. WISHLIST TABLE (Phase 6 Customer Experience)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wishlist (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT wishlist_user_product_unique UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_wishlist_user_id ON public.wishlist(user_id);
CREATE INDEX IF NOT EXISTS idx_wishlist_product_id ON public.wishlist(product_id);

ALTER TABLE public.wishlist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage their own wishlist" ON public.wishlist;
CREATE POLICY "Users can manage their own wishlist"
ON public.wishlist
FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);


-- ------------------------------------------------------------------------------
-- 8. RELOAD SCHEMA CACHE IMMEDIATELY
-- ------------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
