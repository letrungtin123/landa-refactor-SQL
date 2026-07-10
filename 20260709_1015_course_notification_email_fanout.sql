-- Title: Course notification SMTP fanout support
-- Purpose:
--   - Allow course notifications to queue SMTP emails safely through email_outbox.
--   - Track notification email fanout as resumable jobs for large tenant audiences.
--   - Add indexes for group -> sub_group -> team -> team_members + team_course_categories recipient selection.
-- Affected schema: public
-- Affected tables:
--   - email_outbox
--   - notification_email_jobs (new)
--   - team_course_categories
--   - team_members
--   - course_category_courses
--   - teams
--   - sub_groups
--   - org_groups
-- Risk level: Medium. Index creation on large tables can take time and may briefly lock writes.
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation:
--   - Take a Supabase backup or ensure point-in-time recovery is available before running on production.
-- Notes:
--   - This file intentionally does NOT use CREATE INDEX CONCURRENTLY because Supabase SQL editor may wrap
--     statements in a transaction block and reject CONCURRENTLY.
--   - Run manually in Supabase SQL editor before deploying backend code that writes related_notification_id.

BEGIN;

ALTER TABLE public.email_outbox
  ADD COLUMN IF NOT EXISTS related_notification_id UUID REFERENCES public.notifications(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.notification_email_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  notification_id UUID NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  course_id VARCHAR(255) NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'done', 'failed')),
  last_user_id UUID,
  queued_count INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_notification_email_jobs_notification
  ON public.notification_email_jobs (notification_id);

CREATE INDEX IF NOT EXISTS idx_notification_email_jobs_runnable
  ON public.notification_email_jobs (next_attempt_at, updated_at, id)
  WHERE status IN ('pending', 'running', 'failed');

CREATE INDEX IF NOT EXISTS idx_notification_email_jobs_tenant_status
  ON public.notification_email_jobs (tenant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_outbox_notification_status
  ON public.email_outbox (related_notification_id, status, created_at DESC)
  WHERE related_notification_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_email_outbox_notification_email
  ON public.email_outbox (related_notification_id, lower(recipient_email))
  WHERE related_notification_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_team_course_categories_category_team
  ON public.team_course_categories (category_id, team_id);

CREATE INDEX IF NOT EXISTS idx_team_members_team_user
  ON public.team_members (team_id, user_id);

CREATE INDEX IF NOT EXISTS idx_course_category_courses_course_category
  ON public.course_category_courses (course_id, category_id);

CREATE INDEX IF NOT EXISTS idx_teams_sub_group
  ON public.teams (sub_group_id, id);

CREATE INDEX IF NOT EXISTS idx_sub_groups_org_group
  ON public.sub_groups (org_group_id, id);

CREATE INDEX IF NOT EXISTS idx_org_groups_tenant_id
  ON public.org_groups (tenant_id, id);

COMMENT ON TABLE public.notification_email_jobs IS
  'Resumable fanout jobs for queueing SMTP emails from course notifications.';

COMMENT ON COLUMN public.email_outbox.related_notification_id IS
  'Notification that generated this email, used for dedupe and delivery tracing.';

COMMIT;

-- Verification queries:
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'email_outbox'
--   AND column_name = 'related_notification_id';
--
-- SELECT to_regclass('public.notification_email_jobs') AS notification_email_jobs_table;
--
-- SELECT indexname
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND indexname IN (
--     'ux_notification_email_jobs_notification',
--     'idx_notification_email_jobs_runnable',
--     'idx_notification_email_jobs_tenant_status',
--     'idx_email_outbox_notification_status',
--     'ux_email_outbox_notification_email',
--     'idx_team_course_categories_category_team',
--     'idx_team_members_team_user',
--     'idx_course_category_courses_course_category',
--     'idx_teams_sub_group',
--     'idx_sub_groups_org_group',
--     'idx_org_groups_tenant_id'
--   )
-- ORDER BY indexname;

-- Rollback SQL, manual only:
-- DROP INDEX IF EXISTS public.idx_org_groups_tenant_id;
-- DROP INDEX IF EXISTS public.idx_sub_groups_org_group;
-- DROP INDEX IF EXISTS public.idx_teams_sub_group;
-- DROP INDEX IF EXISTS public.idx_course_category_courses_course_category;
-- DROP INDEX IF EXISTS public.idx_team_members_team_user;
-- DROP INDEX IF EXISTS public.idx_team_course_categories_category_team;
-- DROP INDEX IF EXISTS public.ux_email_outbox_notification_email;
-- DROP INDEX IF EXISTS public.idx_email_outbox_notification_status;
-- DROP INDEX IF EXISTS public.idx_notification_email_jobs_tenant_status;
-- DROP INDEX IF EXISTS public.idx_notification_email_jobs_runnable;
-- DROP INDEX IF EXISTS public.ux_notification_email_jobs_notification;
-- DROP TABLE IF EXISTS public.notification_email_jobs;
-- ALTER TABLE public.email_outbox DROP COLUMN IF EXISTS related_notification_id;
