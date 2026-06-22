-- Title: Lesson author persona assignment
-- Purpose: Store one active lesson-author persona per tenant so the course outline widget can auto-select the correct mascot/personality.
-- Affected schema: public
-- Affected tables: tenant_persona_assignments
-- Risk level: Low - additive table and indexes only
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup/snapshot before running, especially if deploying to production.
-- Notes:
--   1. This file is intended for manual review/execution in Supabase SQL Editor.
--   2. Codex must not execute this SQL directly.
--   3. The unique tenant_id + target constraint enforces one active lesson-author persona per tenant.

BEGIN;

CREATE TABLE IF NOT EXISTS tenant_persona_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  target VARCHAR(50) NOT NULL,
  bot_id UUID NOT NULL REFERENCES chatbots(id) ON DELETE CASCADE,
  persona_id UUID NOT NULL REFERENCES bot_personas(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT tenant_persona_assignments_target_check
    CHECK (target IN ('lesson_author')),
  CONSTRAINT tenant_persona_assignments_tenant_id_target_key
    UNIQUE (tenant_id, target)
);

CREATE INDEX IF NOT EXISTS idx_tenant_persona_assignments_tenant
  ON tenant_persona_assignments (tenant_id);

CREATE INDEX IF NOT EXISTS idx_tenant_persona_assignments_persona
  ON tenant_persona_assignments (persona_id);

CREATE INDEX IF NOT EXISTS idx_tenant_persona_assignments_bot
  ON tenant_persona_assignments (bot_id);

COMMIT;

-- Verification queries:
-- SELECT table_name, column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'tenant_persona_assignments'
-- ORDER BY ordinal_position;
--
-- SELECT conname, contype, pg_get_constraintdef(oid) AS definition
-- FROM pg_constraint
-- WHERE conrelid = 'tenant_persona_assignments'::regclass
-- ORDER BY conname;
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename = 'tenant_persona_assignments'
-- ORDER BY indexname;

-- Rollback SQL, review carefully before using:
-- DROP INDEX IF EXISTS idx_tenant_persona_assignments_bot;
-- DROP INDEX IF EXISTS idx_tenant_persona_assignments_persona;
-- DROP INDEX IF EXISTS idx_tenant_persona_assignments_tenant;
-- DROP TABLE IF EXISTS tenant_persona_assignments;
