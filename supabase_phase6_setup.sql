-- ==============================================================================
-- MEN'S PLANET — PHASE 6: WISHLIST & CUSTOMER EXPERIENCE DATABASE SCHEMA
-- Run in Supabase Dashboard > SQL Editor
-- ==============================================================================

-- 1. CREATE WISHLIST TABLE
CREATE TABLE IF NOT EXISTS public.wishlist (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    product_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT wishlist_user_product_unique UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_wishlist_user_id ON public.wishlist(user_id);
CREATE INDEX IF NOT EXISTS idx_wishlist_product_id ON public.wishlist(product_id);

-- 2. ENABLE ROW LEVEL SECURITY (RLS) FOR WISHLIST
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

-- Policy: Customers can only view and manage their own wishlist items (RLS Customer Isolation)
CREATE POLICY "Customers can manage their own wishlist"
ON public.wishlist
FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 3. RELOAD SCHEMA CACHE
NOTIFY pgrst, 'reload schema';
