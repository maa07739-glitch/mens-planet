-- ==============================================================================
-- MEN'S PLANET — FIX: permission denied for function is_admin & Products RLS
-- Run this in your Supabase Dashboard > SQL Editor
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

-- Grant EXECUTE permission to anon, authenticated, service_role, and public
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated, service_role, public;

-- Grant execute on any other overload of is_admin if one exists in public
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

-- Drop all existing policies on products to clear any broken or conflicting rules
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

-- 3. Policy: Public can view all products (Vital for e-commerce store catalog)
CREATE POLICY "Allow public read access to products"
ON public.products
FOR SELECT
TO public
USING (true);

-- 4. Policies: Only authenticated administrators can create, update, or delete products
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

-- 5. Reload PostgREST API schema cache
NOTIFY pgrst, 'reload schema';
