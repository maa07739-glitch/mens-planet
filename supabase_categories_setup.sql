-- ==============================================================================
-- MEN'S PLANET — PHASE 1: CATEGORIES & PRODUCT SKU DATABASE MIGRATION
-- Use in Supabase Dashboard > SQL Editor
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

-- Drop any conflicting policies
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

-- Public can view active categories
CREATE POLICY "Allow public read access to categories"
ON public.categories
FOR SELECT
TO public
USING (true);

-- Admins can insert categories
CREATE POLICY "Admins can insert categories"
ON public.categories
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    OR COALESCE(public.is_admin(), false)
);

-- Admins can update categories
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

-- Admins can delete categories
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

-- 5. RELOAD SCHEMA CACHE
NOTIFY pgrst, 'reload schema';
