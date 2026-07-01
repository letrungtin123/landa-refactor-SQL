-- Title: Study Time Momentum Range Query Indexes
-- Purpose: Keep historical study time forever while making per-user momentum charts and user deletion cleanup efficient.
-- Affected schema: public
-- Affected tables: study_sessions
-- Risk level: Low to medium. Index creation can consume I/O on large tables.
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup or snapshot before running on production.
-- Notes:
--   - This file is intentionally not executed by Codex.
--   - Existing installs may already have idx_study_sessions_user_date.
--   - The tenant/user/date covering index supports dashboard and learner momentum range queries.
--   - Run during a low-traffic window if study_sessions is already large.

BEGIN;

-- Supports daily upsert conflict checks, per-user date-range reads, and indexed FK cascade lookups.
CREATE UNIQUE INDEX IF NOT EXISTS idx_study_sessions_user_date
  ON public.study_sessions (user_id, study_date);

-- Supports tenant-scoped per-user date-range reads used by learner and admin momentum charts.
CREATE INDEX IF NOT EXISTS idx_study_sessions_tenant_user_study_date
  ON public.study_sessions (tenant_id, user_id, study_date)
  INCLUDE (duration_minutes);

COMMIT;

-- Verification queries:
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename = 'study_sessions'
--   AND indexname IN (
--     'idx_study_sessions_user_date',
--     'idx_study_sessions_tenant_user_study_date'
--   )
-- ORDER BY indexname;

-- Optional planner check, replace values before running:
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT study_date, duration_minutes
-- FROM public.study_sessions
-- WHERE tenant_id = '00000000-0000-0000-0000-000000000000'
--   AND user_id = '00000000-0000-0000-0000-000000000000'
--   AND study_date BETWEEN DATE '2026-01-01' AND DATE '2026-12-31'
-- ORDER BY study_date;

-- Rollback SQL, manual only:
-- DROP INDEX IF EXISTS public.idx_study_sessions_tenant_user_study_date;
-- Do not drop idx_study_sessions_user_date unless another unique constraint/index still supports
-- ON CONFLICT (user_id, study_date) in the application.
