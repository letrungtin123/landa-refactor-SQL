-- Title: Tenant group hierarchy display labels
-- Purpose: Store per-tenant display-name overrides for fixed group hierarchy keys.
-- Affected schema: public
-- Affected tables: public.tenant_group_labels
-- Risk level: Medium - schema change only, no data mutation/backfill.
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Export schema metadata before applying in production.
-- Notes:
--   - This file does not update tenant/user/group/team data.
--   - System hierarchy keys remain unchanged: group, subgroup, team.
--   - The application must fallback to built-in defaults when no override row exists.
--   - Default display labels are: group = Cong ty, subgroup = Chi nhanh, team = Phong ban.
--   - No broad GRANT is included; access is intended through the backend only.

BEGIN;

CREATE TABLE IF NOT EXISTS public.tenant_group_labels (
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  label_key varchar(32) NOT NULL,
  label varchar(64) NOT NULL,
  updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, label_key),
  CONSTRAINT tenant_group_labels_key_check CHECK (label_key IN ('group', 'subgroup', 'team')),
  CONSTRAINT tenant_group_labels_label_not_blank CHECK (length(btrim(label)) > 0)
);

COMMENT ON TABLE public.tenant_group_labels IS
  'Per-tenant display labels for fixed group hierarchy keys. Missing rows mean use application defaults.';

COMMENT ON COLUMN public.tenant_group_labels.label_key IS
  'Fixed hierarchy key: group, subgroup, team. Do not use display labels for permission or data filtering.';

COMMENT ON COLUMN public.tenant_group_labels.label IS
  'Tenant-specific display label, max 64 characters. Empty values are represented by deleting the override row.';

ALTER TABLE public.tenant_group_labels ENABLE ROW LEVEL SECURITY;

COMMIT;

-- Verification queries:
-- SELECT table_schema, table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'public' AND table_name = 'tenant_group_labels';
--
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'tenant_group_labels'
-- ORDER BY ordinal_position;
--
-- SELECT schemaname, tablename, rowsecurity
-- FROM pg_tables
-- WHERE schemaname = 'public' AND tablename = 'tenant_group_labels';

-- Rollback:
-- DROP TABLE IF EXISTS public.tenant_group_labels;
