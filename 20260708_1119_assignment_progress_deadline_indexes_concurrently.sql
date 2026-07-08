-- Title: Assignment progress concurrent indexes
-- Purpose:
--   - Create indexes used by assignment-aware course progress recalculation.
--   - Keep index creation non-blocking for large production tables.
-- Affected schema: public
-- Affected tables: public.course_assignments, public.assignment_submissions
-- Risk level: Low/Medium
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation:
--   - Backup public.course_assignments and public.assignment_submissions before execution.
-- Notes:
--   - Run this file after 20260707_1636_assignment_progress_deadline_modes.sql.
--   - These CREATE INDEX CONCURRENTLY statements must run outside any transaction block.
--   - If your SQL runner wraps a full file in one transaction, run each CREATE INDEX
--     statement below separately.

CREATE INDEX IF NOT EXISTS idx_course_assignments_progress_published
  ON public.course_assignments (course_id, id)
  WHERE deleted_at IS NULL AND is_published = true;

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_progress_completed
  ON public.assignment_submissions (enrollment_id, assignment_id)
  WHERE status IN ('submitted', 'feedback_given');

-- Verification queries:
-- SELECT indexname
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename IN ('course_assignments', 'assignment_submissions')
--   AND indexname IN (
--     'idx_course_assignments_progress_published',
--     'idx_assignment_submissions_progress_completed'
--   )
-- ORDER BY indexname;

-- Rollback SQL, manual only:
-- DROP INDEX CONCURRENTLY IF EXISTS public.idx_assignment_submissions_progress_completed;
-- DROP INDEX CONCURRENTLY IF EXISTS public.idx_course_assignments_progress_published;
