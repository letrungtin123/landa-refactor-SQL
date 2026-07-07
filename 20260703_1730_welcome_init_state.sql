-- Title: FE 5173 welcome_init modal state
-- Purpose: Store one-time app-level welcome modal visibility per user, while allowing demo accounts to show per login session.
-- Affected schema: public
-- Affected tables: user_welcome_init_states
-- Risk level: Low/Medium - new table and indexes only
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup/snapshot before running in production.
-- Notes:
--   1. Run this manually in Supabase SQL Editor / psql.
--   2. Codex must not execute this file.
--   3. Backend is expected to write this table through authenticated API logic.

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_welcome_init_states (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  tenant_id uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  shown_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_welcome_init_states_tenant
  ON public.user_welcome_init_states (tenant_id);

CREATE INDEX IF NOT EXISTS idx_user_welcome_init_states_shown_at
  ON public.user_welcome_init_states (shown_at DESC);

ALTER TABLE public.user_welcome_init_states ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.set_welcome_init_state_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_welcome_init_states_updated_at ON public.user_welcome_init_states;
CREATE TRIGGER trg_user_welcome_init_states_updated_at
BEFORE UPDATE ON public.user_welcome_init_states
FOR EACH ROW
EXECUTE FUNCTION public.set_welcome_init_state_updated_at();

COMMIT;

-- Verification queries:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'user_welcome_init_states'
-- ORDER BY ordinal_position;
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename = 'user_welcome_init_states'
-- ORDER BY indexname;
--
-- SELECT schemaname, tablename, rowsecurity
-- FROM pg_tables
-- WHERE schemaname = 'public'
--   AND tablename = 'user_welcome_init_states';

-- Rollback SQL, review carefully before using:
-- DROP TRIGGER IF EXISTS trg_user_welcome_init_states_updated_at ON public.user_welcome_init_states;
-- DROP FUNCTION IF EXISTS public.set_welcome_init_state_updated_at();
-- DROP INDEX IF EXISTS public.idx_user_welcome_init_states_shown_at;
-- DROP INDEX IF EXISTS public.idx_user_welcome_init_states_tenant;
-- DROP TABLE IF EXISTS public.user_welcome_init_states;
