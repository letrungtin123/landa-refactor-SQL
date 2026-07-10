-- Title: Tenant email templates module
-- Purpose:
--   - Add the "Mau email" dashboard module.
--   - Store tenant-scoped overrides for learner-facing email templates.
-- Affected schema: public
-- Affected tables:
--   - public.modules
--   - public.tenant_modules
--   - public.tenant_email_templates (new)
-- Risk level: Medium - schema and module registry change, no email/outbox data is changed.
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Export schema metadata before applying in production.
-- Notes:
--   - The application falls back to built-in templates when no row exists.
--   - Template body is stored as text with {{system_variable}} placeholders; no file attachment is supported.
--   - No broad GRANT is included; access is intended through the backend permission layer only.

BEGIN;

CREATE TABLE IF NOT EXISTS public.tenant_email_templates (
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  template_key varchar(64) NOT NULL,
  subject_template varchar(255) NOT NULL,
  preheader_template varchar(320) NOT NULL,
  body_template text NOT NULL,
  is_enabled boolean NOT NULL DEFAULT true,
  updated_by uuid NULL REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, template_key),
  CONSTRAINT tenant_email_templates_key_check CHECK (
    template_key IN (
      'course_notification',
      'assignment_created',
      'assignment_feedback',
      'team_member_added'
    )
  ),
  CONSTRAINT tenant_email_templates_subject_not_blank CHECK (length(btrim(subject_template)) > 0),
  CONSTRAINT tenant_email_templates_preheader_not_blank CHECK (length(btrim(preheader_template)) > 0),
  CONSTRAINT tenant_email_templates_body_not_blank CHECK (length(btrim(body_template)) > 0),
  CONSTRAINT tenant_email_templates_body_length_check CHECK (length(body_template) <= 12000)
);

COMMENT ON TABLE public.tenant_email_templates IS
  'Tenant-scoped overrides for learner-facing email templates. Missing rows mean use application defaults.';

COMMENT ON COLUMN public.tenant_email_templates.template_key IS
  'Fixed email template key controlled by the application.';

COMMENT ON COLUMN public.tenant_email_templates.body_template IS
  'Plain text template with {{system_variable}} placeholders. Backend escapes values and renders safe system blocks.';

ALTER TABLE public.tenant_email_templates ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_tenant_email_templates_updated_at
  ON public.tenant_email_templates (tenant_id, updated_at DESC);

CREATE OR REPLACE FUNCTION public.set_tenant_email_templates_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tenant_email_templates_updated_at ON public.tenant_email_templates;
CREATE TRIGGER trg_tenant_email_templates_updated_at
BEFORE UPDATE ON public.tenant_email_templates
FOR EACH ROW
EXECUTE FUNCTION public.set_tenant_email_templates_updated_at();

WITH email_module AS (
  INSERT INTO public.modules (code, name, description, icon, sort_order, is_active)
  VALUES (
    'email_templates',
    'Mẫu email',
    'Quản lý mẫu email gửi về cho học viên',
    'MailCheck',
    78,
    true
  )
  ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    is_active = true
  RETURNING id
)
INSERT INTO public.tenant_modules (tenant_id, module_id, is_enabled)
SELECT t.id, email_module.id, true
FROM public.tenants t
CROSS JOIN email_module
ON CONFLICT (tenant_id, module_id) DO UPDATE SET
  is_enabled = true;

COMMIT;

-- Verification queries:
-- SELECT code, name, icon, is_active
-- FROM public.modules
-- WHERE code = 'email_templates';
--
-- SELECT table_schema, table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'public' AND table_name = 'tenant_email_templates';
--
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'tenant_email_templates'
-- ORDER BY ordinal_position;
--
-- SELECT COUNT(*) AS enabled_tenants
-- FROM public.tenant_modules tm
-- JOIN public.modules m ON m.id = tm.module_id
-- WHERE m.code = 'email_templates' AND tm.is_enabled = true;
--
-- SELECT schemaname, tablename, rowsecurity
-- FROM pg_tables
-- WHERE schemaname = 'public' AND tablename = 'tenant_email_templates';

-- Rollback:
-- BEGIN;
-- DELETE FROM public.tenant_modules
-- USING public.modules
-- WHERE tenant_modules.module_id = modules.id
--   AND modules.code = 'email_templates';
-- DELETE FROM public.modules WHERE code = 'email_templates';
-- DROP TRIGGER IF EXISTS trg_tenant_email_templates_updated_at ON public.tenant_email_templates;
-- DROP FUNCTION IF EXISTS public.set_tenant_email_templates_updated_at();
-- DROP TABLE IF EXISTS public.tenant_email_templates;
-- COMMIT;
