-- ==============================================================================
-- MEN'S PLANET — PHASE 2: SHOPPING CART PERSISTENCE & CUSTOMER ISOLATION
-- Run in Supabase Dashboard > SQL Editor
-- ==============================================================================

-- 1. CREATE CART_ITEMS TABLE (Persistent across logins/logouts & devices)
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

-- Indexes for lightning fast lookups
CREATE INDEX IF NOT EXISTS idx_cart_items_user_id ON public.cart_items(user_id);

-- 2. ENABLE ROW LEVEL SECURITY (RLS) FOR CART_ITEMS
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

-- Drop conflicting policies if any
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

-- Policy: Customers can only manage their own cart items (Customer Data Isolation)
CREATE POLICY "Customers can manage their own cart items"
ON public.cart_items
FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 3. VERIFY ORDER_ITEMS TABLE
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
    OR EXISTS (
        SELECT 1 FROM public.orders
        WHERE orders.order_number = order_items.order_number AND orders.user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Customers can insert their own order items" ON public.order_items;
CREATE POLICY "Customers can insert their own order items"
ON public.order_items FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.orders
        WHERE (orders.id = order_items.order_id OR orders.order_number = order_items.order_number)
          AND orders.user_id = auth.uid()
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
    OR COALESCE(public.is_admin(), false)
);

-- 4. RELOAD SCHEMA CACHE
NOTIFY pgrst, 'reload schema';
