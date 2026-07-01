-- Title: Tenant role display labels
-- Purpose: Store per-tenant display-name overrides for fixed system roles.
-- Affected schema: public
-- Affected tables: public.tenant_role_labels
-- Risk level: Medium - schema change only, no data mutation/backfill.
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Export schema metadata before applying in production.
-- Notes:
--   - This file does not update tenant/user data.
--   - System role keys remain unchanged: superadmin, superuser, staff, learner, learner_plus.
--   - The application must fallback to built-in defaults when no override row exists.
--   - No broad GRANT is included; access is intended through the backend only.

BEGIN;

CREATE TABLE IF NOT EXISTS public.tenant_role_labels (
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  role public.user_role NOT NULL,
  label varchar(64) NOT NULL,
  updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, role),
  CONSTRAINT tenant_role_labels_label_not_blank CHECK (length(btrim(label)) > 0)
);

COMMENT ON TABLE public.tenant_role_labels IS
  'Per-tenant display labels for fixed system role keys. Missing rows mean use application defaults.';

COMMENT ON COLUMN public.tenant_role_labels.role IS
  'Fixed system role key; do not use display labels for auth or authorization decisions.';

COMMENT ON COLUMN public.tenant_role_labels.label IS
  'Tenant-specific display label, max 64 characters. Empty values are represented by deleting the override row.';

ALTER TABLE public.tenant_role_labels ENABLE ROW LEVEL SECURITY;

COMMIT;

-- Verification queries:
-- SELECT table_schema, table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'public' AND table_name = 'tenant_role_labels';
--
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'tenant_role_labels'
-- ORDER BY ordinal_position;
--
-- SELECT schemaname, tablename, rowsecurity
-- FROM pg_tables
-- WHERE schemaname = 'public' AND tablename = 'tenant_role_labels';

-- Rollback:
-- DROP TABLE IF EXISTS public.tenant_role_labels;
