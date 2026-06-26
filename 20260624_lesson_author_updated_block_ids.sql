-- Title: Add updated_block_ids to lesson_author_jobs
-- Purpose: Track which blocks were updated (not just created) when a proposal is applied.
-- Affected table: lesson_author_jobs
-- Risk level: Low - additive column with default
-- Execution owner: Manual only
-- Direct execution by Codex: Forbidden

BEGIN;

ALTER TABLE lesson_author_jobs
  ADD COLUMN IF NOT EXISTS updated_block_ids UUID[] NOT NULL DEFAULT '{}'::uuid[];

COMMENT ON COLUMN lesson_author_jobs.updated_block_ids IS
  'Block IDs that were updated (not created) when the proposal was applied. Used for audit trail.';

COMMIT;

-- Verification:
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'lesson_author_jobs' AND column_name = 'updated_block_ids';
