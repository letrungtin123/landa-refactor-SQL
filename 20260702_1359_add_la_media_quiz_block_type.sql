-- Title: Add la_media_quiz course block type
-- Purpose: Allow the new media-gated quiz component to be stored in course_blocks.block_type.
-- Affected schema: public
-- Affected tables: course_blocks
-- Risk level: Low schema enum extension; irreversible by simple DROP in PostgreSQL.
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Confirm no pending deploy is inserting la_media_quiz before this SQL is applied.
-- Notes: This only extends the block_type enum. It does not create or modify course content rows.

ALTER TYPE public.block_type ADD VALUE IF NOT EXISTS 'la_media_quiz';

-- Verification query:
-- SELECT e.enumlabel
-- FROM pg_type t
-- JOIN pg_enum e ON e.enumtypid = t.oid
-- JOIN pg_namespace n ON n.oid = t.typnamespace
-- WHERE n.nspname = 'public'
--   AND t.typname = 'block_type'
--   AND e.enumlabel = 'la_media_quiz';

-- Rollback note:
-- PostgreSQL does not support safely dropping enum values in-place on typical versions.
-- To roll back application behavior, revert code that creates/renders la_media_quiz and
-- delete or convert any test rows using block_type = 'la_media_quiz' before redeploying.
