-- Title: Lesson author AI active bot/KB configuration and chat isolation
-- Purpose: Add one active lesson-author bot and one active lesson-author KB per tenant, isolate lesson-author chat by course, and keep AI-created block audit metadata.
-- Affected schema: public
-- Affected tables: tenant_bot_assignments, tenant_kb_assignments, chat_conversations, lesson_author_jobs, kb_documents
-- Risk level: Medium - check constraints and chat/conversation query paths
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Take a database backup/snapshot before running. Run during low-traffic hours if chat tables are large.
-- Notes:
--   1. This file is intended for manual review/execution in Supabase SQL Editor.
--   2. Existing conversations are backfilled as target='admin' because the old schema did not store target.
--   3. The kb_documents type constraint is expanded to include 'faq' to match backend FAQ upload code.

BEGIN;

-- Allow a dedicated active bot slot for the dashboard lesson-author widget.
ALTER TABLE tenant_bot_assignments
  DROP CONSTRAINT IF EXISTS tenant_bot_assignments_target_check;

ALTER TABLE tenant_bot_assignments
  ADD CONSTRAINT tenant_bot_assignments_target_check
  CHECK (target IN ('admin', 'learner', 'lesson_author'));

-- One active KB per tenant/target. Kept separate from chatbots.kb_id so admins can
-- change the lesson-author KB without editing or recreating the bot.
CREATE TABLE IF NOT EXISTS tenant_kb_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  target VARCHAR(50) NOT NULL,
  kb_id UUID NOT NULL REFERENCES knowledgebases(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT tenant_kb_assignments_target_check
    CHECK (target IN ('lesson_author')),
  CONSTRAINT tenant_kb_assignments_tenant_id_target_key
    UNIQUE (tenant_id, target)
);

-- Isolate chat history by surface and course. This keeps normal admin chat,
-- learner chat, and course lesson-author chat from sharing conversation lists.
ALTER TABLE chat_conversations
  ADD COLUMN IF NOT EXISTS target VARCHAR(50) NOT NULL DEFAULT 'admin',
  ADD COLUMN IF NOT EXISTS course_id VARCHAR(255),
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE chat_conversations
  DROP CONSTRAINT IF EXISTS chat_conversations_target_check;

ALTER TABLE chat_conversations
  ADD CONSTRAINT chat_conversations_target_check
  CHECK (target IN ('admin', 'learner', 'lesson_author'));

-- Audit/idempotency table for lesson-author generation/apply operations.
CREATE TABLE IF NOT EXISTS lesson_author_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id VARCHAR(255) NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES chat_conversations(id) ON DELETE SET NULL,
  bot_id UUID REFERENCES chatbots(id) ON DELETE SET NULL,
  kb_id UUID REFERENCES knowledgebases(id) ON DELETE SET NULL,
  requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
  request_hash TEXT,
  status VARCHAR(30) NOT NULL DEFAULT 'proposed',
  prompt TEXT NOT NULL DEFAULT '',
  proposal JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_block_ids UUID[] NOT NULL DEFAULT '{}'::uuid[],
  error_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT lesson_author_jobs_status_check
    CHECK (status IN ('proposed', 'applying', 'succeeded', 'failed', 'canceled'))
);

-- Match backend FAQ upload code, which inserts kb_documents.type='faq'.
ALTER TABLE kb_documents
  DROP CONSTRAINT IF EXISTS kb_documents_type_check;

ALTER TABLE kb_documents
  ADD CONSTRAINT kb_documents_type_check
  CHECK (type IN ('file', 'url', 'article', 'faq'));

CREATE INDEX IF NOT EXISTS idx_tenant_kb_assignments_tenant
  ON tenant_kb_assignments (tenant_id);

CREATE INDEX IF NOT EXISTS idx_chat_conversations_tenant_user_target_course
  ON chat_conversations (tenant_id, user_id, target, course_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_lesson_author_jobs_tenant_course_status
  ON lesson_author_jobs (tenant_id, course_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_lesson_author_jobs_request_hash
  ON lesson_author_jobs (tenant_id, request_hash)
  WHERE request_hash IS NOT NULL;

COMMIT;

-- Verification queries:
-- SELECT conrelid::regclass::text AS table_name, conname, pg_get_constraintdef(oid) AS definition
-- FROM pg_constraint
-- WHERE connamespace = 'public'::regnamespace
--   AND conname IN (
--     'tenant_bot_assignments_target_check',
--     'tenant_kb_assignments_target_check',
--     'chat_conversations_target_check',
--     'lesson_author_jobs_status_check',
--     'kb_documents_type_check'
--   )
-- ORDER BY table_name, conname;
--
-- SELECT table_name, column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name IN ('tenant_kb_assignments', 'chat_conversations', 'lesson_author_jobs')
-- ORDER BY table_name, ordinal_position;
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND indexname IN (
--     'idx_tenant_kb_assignments_tenant',
--     'idx_chat_conversations_tenant_user_target_course',
--     'idx_lesson_author_jobs_tenant_course_status',
--     'idx_lesson_author_jobs_request_hash'
--   )
-- ORDER BY indexname;

-- Rollback SQL, review carefully before using:
-- DROP INDEX IF EXISTS idx_lesson_author_jobs_request_hash;
-- DROP INDEX IF EXISTS idx_lesson_author_jobs_tenant_course_status;
-- DROP INDEX IF EXISTS idx_chat_conversations_tenant_user_target_course;
-- DROP INDEX IF EXISTS idx_tenant_kb_assignments_tenant;
-- ALTER TABLE kb_documents DROP CONSTRAINT IF EXISTS kb_documents_type_check;
-- ALTER TABLE kb_documents
--   ADD CONSTRAINT kb_documents_type_check
--   CHECK (type IN ('file', 'url', 'article'));
-- DROP TABLE IF EXISTS lesson_author_jobs;
-- ALTER TABLE chat_conversations DROP CONSTRAINT IF EXISTS chat_conversations_target_check;
-- ALTER TABLE chat_conversations
--   DROP COLUMN IF EXISTS target,
--   DROP COLUMN IF EXISTS course_id,
--   DROP COLUMN IF EXISTS metadata;
-- DROP TABLE IF EXISTS tenant_kb_assignments;
-- ALTER TABLE tenant_bot_assignments DROP CONSTRAINT IF EXISTS tenant_bot_assignments_target_check;
-- ALTER TABLE tenant_bot_assignments
--   ADD CONSTRAINT tenant_bot_assignments_target_check
--   CHECK (target IN ('admin', 'learner'));
