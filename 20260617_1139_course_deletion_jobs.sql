-- Title: Course soft delete and background purge jobs
-- Purpose: Hide deleted courses/blocks immediately, then let backend RabbitMQ workers purge data/storage safely.
-- Affected schema: public
-- Affected tables: courses, course_blocks, course_assets, course_deletion_jobs
-- Risk level: Medium/High - deletion flow and large-table indexes
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup/snapshot before running. Run during low-traffic hours for large tables.
-- Notes:
--   1. Supabase SQL Editor wraps all statements in a transaction, so CONCURRENTLY is NOT used.
--      This means CREATE INDEX will briefly lock the table. Run during low-traffic hours for large tables.
--   2. Phần 1 (line 15-68): CREATE TABLE + ALTER TABLE — chạy trước.
--      Phần 2 (line 70-131): CREATE INDEX — chạy sau (paste riêng nếu Phần 1 đã chạy xong).
--   3. Run this manually in Supabase SQL Editor. Codex must not execute it.
--   4. Existing rows remain active by default.

CREATE TABLE IF NOT EXISTS course_deletion_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id VARCHAR(255) NOT NULL,
  root_block_id UUID,
  target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('course', 'block')),
  status VARCHAR(20) NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
  requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  attempts INT NOT NULL DEFAULT 0,
  last_error TEXT,
  stats JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE courses
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delete_status VARCHAR(20) NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS delete_job_id UUID,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE course_blocks
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delete_status VARCHAR(20) NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS delete_job_id UUID,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users(id) ON DELETE SET NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'courses_delete_status_check'
      AND conrelid = 'courses'::regclass
  ) THEN
    ALTER TABLE courses
      ADD CONSTRAINT courses_delete_status_check
      CHECK (delete_status IN ('active', 'queued', 'running', 'failed'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'course_blocks_delete_status_check'
      AND conrelid = 'course_blocks'::regclass
  ) THEN
    ALTER TABLE course_blocks
      ADD CONSTRAINT course_blocks_delete_status_check
      CHECK (delete_status IN ('active', 'queued', 'running', 'failed'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_course_deletion_jobs_status
  ON course_deletion_jobs (status, requested_at);

CREATE INDEX IF NOT EXISTS idx_course_deletion_jobs_tenant_course
  ON course_deletion_jobs (tenant_id, course_id, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_courses_tenant_active_updated
  ON courses (tenant_id, updated_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_courses_delete_status
  ON courses (delete_status, deleted_at)
  WHERE deleted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_course_blocks_active_tree
  ON course_blocks (course_id, parent_id, sort_order)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_course_blocks_delete_status
  ON course_blocks (delete_status, deleted_at)
  WHERE deleted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_course_blocks_course_parent_all
  ON course_blocks (course_id, parent_id);

CREATE INDEX IF NOT EXISTS idx_course_blocks_parent_all
  ON course_blocks (parent_id);

CREATE INDEX IF NOT EXISTS idx_course_assets_tenant_course_storage
  ON course_assets (tenant_id, course_id, storage_path);

CREATE INDEX IF NOT EXISTS idx_course_assets_tenant_course_url
  ON course_assets (tenant_id, course_id, url);

CREATE INDEX IF NOT EXISTS idx_enrollments_tenant_course_id
  ON enrollments (tenant_id, course_id, id);

CREATE INDEX IF NOT EXISTS idx_notifications_course_id
  ON notifications (course_id)
  WHERE course_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_study_sessions_course_id
  ON study_sessions (course_id)
  WHERE course_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_team_courses_course_id
  ON team_courses (course_id);

CREATE INDEX IF NOT EXISTS idx_course_category_courses_course_id
  ON course_category_courses (course_id);

CREATE INDEX IF NOT EXISTS idx_course_modal_configs_course_id
  ON course_modal_configs (course_id);

CREATE INDEX IF NOT EXISTS idx_course_modal_states_course_id
  ON course_modal_states (course_id);

CREATE INDEX IF NOT EXISTS idx_section_modal_configs_course_section
  ON section_modal_configs (course_id, section_id);

CREATE INDEX IF NOT EXISTS idx_section_modal_shown_course_section
  ON section_modal_shown (course_id, section_id);

-- Verification queries:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name IN ('courses', 'course_blocks', 'course_deletion_jobs')
--   AND column_name IN ('deleted_at', 'delete_status', 'delete_job_id', 'deleted_by', 'status', 'target_type')
-- ORDER BY table_name, column_name;
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND indexname IN (
--     'idx_course_deletion_jobs_status',
--     'idx_course_deletion_jobs_tenant_course',
--     'idx_courses_tenant_active_updated',
--     'idx_courses_delete_status',
--     'idx_course_blocks_active_tree',
--     'idx_course_blocks_delete_status',
--     'idx_course_blocks_course_parent_all',
--     'idx_course_blocks_parent_all',
--     'idx_course_assets_tenant_course_storage',
--     'idx_course_assets_tenant_course_url',
--     'idx_enrollments_tenant_course_id',
--     'idx_notifications_course_id',
--     'idx_study_sessions_course_id',
--     'idx_team_courses_course_id',
--     'idx_course_category_courses_course_id',
--     'idx_course_modal_configs_course_id',
--     'idx_course_modal_states_course_id',
--     'idx_section_modal_configs_course_section',
--     'idx_section_modal_shown_course_section'
--   )
-- ORDER BY indexname;

-- Rollback SQL, review carefully before using:
-- DROP INDEX IF EXISTS idx_section_modal_shown_course_section;
-- DROP INDEX IF EXISTS idx_section_modal_configs_course_section;
-- DROP INDEX IF EXISTS idx_course_modal_states_course_id;
-- DROP INDEX IF EXISTS idx_course_modal_configs_course_id;
-- DROP INDEX IF EXISTS idx_course_category_courses_course_id;
-- DROP INDEX IF EXISTS idx_team_courses_course_id;
-- DROP INDEX IF EXISTS idx_study_sessions_course_id;
-- DROP INDEX IF EXISTS idx_notifications_course_id;
-- DROP INDEX IF EXISTS idx_enrollments_tenant_course_id;
-- DROP INDEX IF EXISTS idx_course_assets_tenant_course_url;
-- DROP INDEX IF EXISTS idx_course_assets_tenant_course_storage;
-- DROP INDEX IF EXISTS idx_course_blocks_parent_all;
-- DROP INDEX IF EXISTS idx_course_blocks_course_parent_all;
-- DROP INDEX IF EXISTS idx_course_blocks_delete_status;
-- DROP INDEX IF EXISTS idx_course_blocks_active_tree;
-- DROP INDEX IF EXISTS idx_courses_delete_status;
-- DROP INDEX IF EXISTS idx_courses_tenant_active_updated;
-- DROP INDEX IF EXISTS idx_course_deletion_jobs_tenant_course;
-- DROP INDEX IF EXISTS idx_course_deletion_jobs_status;
-- ALTER TABLE course_blocks DROP CONSTRAINT IF EXISTS course_blocks_delete_status_check;
-- ALTER TABLE courses DROP CONSTRAINT IF EXISTS courses_delete_status_check;
-- ALTER TABLE course_blocks
--   DROP COLUMN IF EXISTS deleted_at,
--   DROP COLUMN IF EXISTS delete_status,
--   DROP COLUMN IF EXISTS delete_job_id,
--   DROP COLUMN IF EXISTS deleted_by;
-- ALTER TABLE courses
--   DROP COLUMN IF EXISTS deleted_at,
--   DROP COLUMN IF EXISTS delete_status,
--   DROP COLUMN IF EXISTS delete_job_id,
--   DROP COLUMN IF EXISTS deleted_by;
-- DROP TABLE IF EXISTS course_deletion_jobs;
