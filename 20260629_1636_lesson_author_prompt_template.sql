-- Title: Global lesson-author prompt template flag
-- Purpose: Move the lesson-author persona source of truth from per-tenant bot persona assignment to one globally active system prompt template managed by superadmin.
-- Affected schema: public
-- Affected tables: system_prompt_templates
-- Risk level: Low - additive boolean column and partial unique index only
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup/snapshot before running, especially in production.
-- Notes:
--   1. This file is intended for manual review/execution in Supabase SQL Editor.
--   2. Codex must not execute this SQL directly.
--   3. The partial unique index enforces at most one active lesson-author prompt template globally.
--   4. Existing rows default to false. After running this file, choose one template in Prompt he thong.

BEGIN;

ALTER TABLE system_prompt_templates
  ADD COLUMN IF NOT EXISTS is_lesson_author BOOLEAN NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS system_prompt_templates_one_lesson_author_idx
  ON system_prompt_templates ((is_lesson_author))
  WHERE is_lesson_author = true;

COMMIT;

-- Verification queries:
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'system_prompt_templates'
--   AND column_name = 'is_lesson_author';
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename = 'system_prompt_templates'
--   AND indexname = 'system_prompt_templates_one_lesson_author_idx';
--
-- SELECT id, name, is_active, is_lesson_author
-- FROM system_prompt_templates
-- WHERE is_lesson_author = true;

-- Rollback SQL, review carefully before using:
-- DROP INDEX IF EXISTS system_prompt_templates_one_lesson_author_idx;
-- ALTER TABLE system_prompt_templates DROP COLUMN IF EXISTS is_lesson_author;
