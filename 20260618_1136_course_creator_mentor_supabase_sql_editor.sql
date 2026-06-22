-- Title: Course creator and mentor fields - Supabase SQL Editor compatible
-- Purpose: Store the user who created each course and the current mentor shown to learners.
-- Affected schema: public
-- Affected tables: courses, users
-- Risk level: Medium - adds nullable foreign keys and indexes for large user/course tables
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup/snapshot before running. Run during low-traffic hours for large tables.
--
-- Why this file exists:
-- Supabase SQL Editor may wrap a multi-statement script in a transaction.
-- PostgreSQL does not allow CREATE INDEX CONCURRENTLY inside a transaction block.
-- This variant intentionally uses normal CREATE INDEX IF NOT EXISTS so it can run in Supabase SQL Editor.
--
-- Operational note:
-- Normal CREATE INDEX can lock writes while each index is being built. For very large tables,
-- run during low-traffic hours. If you can run SQL through psql without a transaction wrapper,
-- prefer the CONCURRENTLY version in 20260618_1118_course_creator_mentor.sql.

ALTER TABLE courses
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS mentor_id UUID REFERENCES users(id) ON DELETE SET NULL;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_courses_tenant_created_by
  ON courses (tenant_id, created_by)
  WHERE created_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_courses_tenant_mentor_id
  ON courses (tenant_id, mentor_id)
  WHERE mentor_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_mentor_candidates_staff
  ON users (tenant_id, role, is_active, id)
  WHERE role = 'staff' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_users_mentor_candidates_full_name_trgm
  ON users USING gin (lower(full_name) gin_trgm_ops)
  WHERE role = 'staff' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_users_mentor_candidates_email_trgm
  ON users USING gin (lower(email) gin_trgm_ops)
  WHERE role = 'staff' AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_users_mentor_candidates_username_trgm
  ON users USING gin (lower(username) gin_trgm_ops)
  WHERE role = 'staff' AND is_active = true;

-- Verification queries:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'courses'
--   AND column_name IN ('created_by', 'mentor_id')
-- ORDER BY column_name;
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND indexname IN (
--     'idx_courses_tenant_created_by',
--     'idx_courses_tenant_mentor_id',
--     'idx_users_mentor_candidates_staff',
--     'idx_users_mentor_candidates_full_name_trgm',
--     'idx_users_mentor_candidates_email_trgm',
--     'idx_users_mentor_candidates_username_trgm'
--   )
-- ORDER BY indexname;

-- Rollback SQL, review carefully before using:
-- DROP INDEX IF EXISTS idx_users_mentor_candidates_username_trgm;
-- DROP INDEX IF EXISTS idx_users_mentor_candidates_email_trgm;
-- DROP INDEX IF EXISTS idx_users_mentor_candidates_full_name_trgm;
-- DROP INDEX IF EXISTS idx_users_mentor_candidates_staff;
-- DROP INDEX IF EXISTS idx_courses_tenant_mentor_id;
-- DROP INDEX IF EXISTS idx_courses_tenant_created_by;
-- ALTER TABLE courses
--   DROP COLUMN IF EXISTS mentor_id,
--   DROP COLUMN IF EXISTS created_by;
