-- Title: Course mentor section configuration
-- Purpose: Store per-course mentor/company section description and light/dark logos.
-- Affected schema: public
-- Affected tables: public.course_mentor_sections
-- Risk level: Medium - new table only, no existing data mutation.
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup or snapshot before running on production/staging.
-- Notes:
--   - This file is designed for Supabase SQL Editor manual execution.
--   - It does not use CREATE INDEX CONCURRENTLY because SQL Editor may run statements inside a transaction.
--   - Logo columns store raw Supabase Storage paths. Frontends must resolve them through /api/storage.

BEGIN;

CREATE TABLE IF NOT EXISTS public.course_mentor_sections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  course_id VARCHAR(255) NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  description TEXT NULL,
  logo_light_path TEXT NULL,
  logo_dark_path TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID NULL REFERENCES public.users(id) ON DELETE SET NULL,
  CONSTRAINT course_mentor_sections_tenant_course_key UNIQUE (tenant_id, course_id),
  CONSTRAINT course_mentor_sections_description_len CHECK (
    description IS NULL OR char_length(description) <= 2000
  ),
  CONSTRAINT course_mentor_sections_logo_light_len CHECK (
    logo_light_path IS NULL OR char_length(logo_light_path) <= 1000
  ),
  CONSTRAINT course_mentor_sections_logo_dark_len CHECK (
    logo_dark_path IS NULL OR char_length(logo_dark_path) <= 1000
  )
);

CREATE INDEX IF NOT EXISTS idx_course_mentor_sections_updated_by
  ON public.course_mentor_sections (updated_by)
  WHERE updated_by IS NOT NULL;

COMMENT ON TABLE public.course_mentor_sections IS
  'Per-course mentor/company section config for learner course detail.';
COMMENT ON COLUMN public.course_mentor_sections.description IS
  'Company/mentor section description rendered in FE learner course detail.';
COMMENT ON COLUMN public.course_mentor_sections.logo_light_path IS
  'Raw Supabase Storage path for light mode logo.';
COMMENT ON COLUMN public.course_mentor_sections.logo_dark_path IS
  'Raw Supabase Storage path for dark mode logo.';

COMMIT;

-- Verification queries:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'course_mentor_sections'
-- ORDER BY ordinal_position;
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public' AND tablename = 'course_mentor_sections'
-- ORDER BY indexname;

-- Rollback SQL, manual only:
-- DROP TABLE IF EXISTS public.course_mentor_sections;
