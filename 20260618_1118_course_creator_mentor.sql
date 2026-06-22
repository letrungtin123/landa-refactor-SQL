-- Title: Course creator and mentor fields
-- Purpose: Store the user who created each course and the current mentor shown to learners.
-- Affected schema: public
-- Affected tables: courses, users
-- Risk level: Medium - adds nullable foreign keys and indexes for large user/course tables
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup/snapshot before running. Run during low-traffic hours for large tables.
-- Notes:
--   1. This script intentionally does not backfill existing courses.
--   2. New courses should set created_by and mentor_id in backend code.
--   3. CREATE INDEX CONCURRENTLY cannot run inside a transaction block.
--   4. If your SQL runner wraps statements in a transaction, run the CREATE INDEX CONCURRENTLY statements one by one.

ALTER TABLE courses
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS mentor_id UUID REFERENCES users(id) ON DELETE SET NULL;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_courses_tenant_created_by
  ON courses (tenant_id, created_by)
  WHERE created_by IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_courses_tenant_mentor_id
  ON courses (tenant_id, mentor_id)
  WHERE mentor_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_mentor_candidates_staff
  ON users (tenant_id, role, is_active, id)
  WHERE role = 'staff' AND is_active = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_mentor_candidates_full_name_trgm
  ON users USING gin (lower(full_name) gin_trgm_ops)
  WHERE role = 'staff' AND is_active = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_mentor_candidates_email_trgm
  ON users USING gin (lower(email) gin_trgm_ops)
  WHERE role = 'staff' AND is_active = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_mentor_candidates_username_trgm
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
-- SELECT tc.constraint_name, kcu.column_name, ccu.table_name AS foreign_table_name, ccu.column_name AS foreign_column_name
-- FROM information_schema.table_constraints tc
-- JOIN information_schema.key_column_usage kcu
--   ON tc.constraint_name = kcu.constraint_name
--  AND tc.table_schema = kcu.table_schema
-- JOIN information_schema.constraint_column_usage ccu
--   ON ccu.constraint_name = tc.constraint_name
--  AND ccu.table_schema = tc.table_schema
-- WHERE tc.table_schema = 'public'
--   AND tc.table_name = 'courses'
--   AND tc.constraint_type = 'FOREIGN KEY'
--   AND kcu.column_name IN ('created_by', 'mentor_id')
-- ORDER BY kcu.column_name;
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
-- DROP INDEX CONCURRENTLY IF EXISTS idx_users_mentor_candidates_username_trgm;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_users_mentor_candidates_email_trgm;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_users_mentor_candidates_full_name_trgm;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_users_mentor_candidates_staff;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_courses_tenant_mentor_id;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_courses_tenant_created_by;
-- ALTER TABLE courses
--   DROP COLUMN IF EXISTS mentor_id,
--   DROP COLUMN IF EXISTS created_by;
