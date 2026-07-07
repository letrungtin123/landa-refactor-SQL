-- Course-level assignments, private submission files, tenant SMTP config, and email outbox.
-- Apply manually in Supabase SQL editor.
-- This feature intentionally keeps assignments outside course_blocks so learner progress stays unchanged.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'assignment_submission_status') THEN
    CREATE TYPE public.assignment_submission_status AS ENUM ('submitted', 'feedback_given');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'email_outbox_status') THEN
    CREATE TYPE public.email_outbox_status AS ENUM ('pending', 'sending', 'sent', 'failed');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.course_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  course_id VARCHAR(255) NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  title VARCHAR(255) NOT NULL,
  question TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_published BOOLEAN NOT NULL DEFAULT true,
  allow_resubmission BOOLEAN NOT NULL DEFAULT false,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_course_assignments_active_order
  ON public.course_assignments (tenant_id, course_id, sort_order, id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_course_assignments_course_published
  ON public.course_assignments (course_id, sort_order, id)
  WHERE deleted_at IS NULL AND is_published = true;

CREATE TABLE IF NOT EXISTS public.assignment_submissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  course_id VARCHAR(255) NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  assignment_id UUID NOT NULL REFERENCES public.course_assignments(id) ON DELETE CASCADE,
  learner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  enrollment_id UUID NOT NULL REFERENCES public.enrollments(id) ON DELETE CASCADE,
  answer_text TEXT NOT NULL DEFAULT '',
  files JSONB NOT NULL DEFAULT '[]'::jsonb,
  status public.assignment_submission_status NOT NULL DEFAULT 'submitted',
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  submission_version INTEGER NOT NULL DEFAULT 1,
  feedback_text TEXT,
  feedback_files JSONB NOT NULL DEFAULT '[]'::jsonb,
  feedback_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  feedback_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT assignment_submissions_feedback_status_chk CHECK (
    (status = 'submitted' AND feedback_at IS NULL)
    OR
    (status = 'feedback_given' AND feedback_at IS NOT NULL AND feedback_by IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_assignment_submissions_assignment_learner
  ON public.assignment_submissions (assignment_id, learner_id);

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_course_submitted
  ON public.assignment_submissions (tenant_id, course_id, submitted_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_assignment_status
  ON public.assignment_submissions (assignment_id, status, submitted_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_learner_course
  ON public.assignment_submissions (learner_id, course_id, assignment_id);

CREATE TABLE IF NOT EXISTS public.assignment_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  course_id VARCHAR(255) NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
  assignment_id UUID NOT NULL REFERENCES public.course_assignments(id) ON DELETE CASCADE,
  submission_id UUID NOT NULL REFERENCES public.assignment_submissions(id) ON DELETE CASCADE,
  uploaded_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  kind VARCHAR(20) NOT NULL CHECK (kind IN ('submission', 'feedback')),
  storage_path TEXT NOT NULL,
  original_name VARCHAR(255) NOT NULL,
  mime_type VARCHAR(255) NOT NULL,
  size_bytes BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assignment_files_submission_kind
  ON public.assignment_files (submission_id, kind, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_assignment_files_tenant_course
  ON public.assignment_files (tenant_id, course_id, assignment_id, kind);

CREATE TABLE IF NOT EXISTS public.tenant_smtp_configs (
  tenant_id UUID PRIMARY KEY REFERENCES public.tenants(id) ON DELETE CASCADE,
  is_enabled BOOLEAN NOT NULL DEFAULT false,
  host VARCHAR(255) NOT NULL DEFAULT 'smtp.gmail.com',
  port INTEGER NOT NULL DEFAULT 587,
  secure BOOLEAN NOT NULL DEFAULT false,
  username VARCHAR(255) NOT NULL DEFAULT '',
  from_email VARCHAR(255) NOT NULL DEFAULT '',
  from_name VARCHAR(255) NOT NULL DEFAULT '',
  reply_to_email VARCHAR(255),
  copy_to_sender BOOLEAN NOT NULL DEFAULT true,
  copy_to_email VARCHAR(255),
  password_ciphertext TEXT,
  password_iv TEXT,
  password_auth_tag TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT tenant_smtp_configs_port_chk CHECK (port BETWEEN 1 AND 65535),
  CONSTRAINT tenant_smtp_configs_secret_chk CHECK (
    password_ciphertext IS NULL
    OR (password_iv IS NOT NULL AND password_auth_tag IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_tenant_smtp_configs_enabled
  ON public.tenant_smtp_configs (tenant_id)
  WHERE is_enabled = true;

CREATE TABLE IF NOT EXISTS public.email_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  related_submission_id UUID REFERENCES public.assignment_submissions(id) ON DELETE SET NULL,
  recipient_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  recipient_email VARCHAR(255) NOT NULL,
  recipient_name VARCHAR(255),
  subject VARCHAR(255) NOT NULL,
  html_body TEXT NOT NULL,
  text_body TEXT NOT NULL,
  status public.email_outbox_status NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_error TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_outbox_pending
  ON public.email_outbox (next_attempt_at, created_at, id)
  WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_email_outbox_tenant_submission
  ON public.email_outbox (tenant_id, related_submission_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.set_course_assignments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_course_assignments_updated_at ON public.course_assignments;
CREATE TRIGGER trg_course_assignments_updated_at
BEFORE UPDATE ON public.course_assignments
FOR EACH ROW
EXECUTE FUNCTION public.set_course_assignments_updated_at();

DROP TRIGGER IF EXISTS trg_assignment_submissions_updated_at ON public.assignment_submissions;
CREATE TRIGGER trg_assignment_submissions_updated_at
BEFORE UPDATE ON public.assignment_submissions
FOR EACH ROW
EXECUTE FUNCTION public.set_course_assignments_updated_at();

DROP TRIGGER IF EXISTS trg_tenant_smtp_configs_updated_at ON public.tenant_smtp_configs;
CREATE TRIGGER trg_tenant_smtp_configs_updated_at
BEFORE UPDATE ON public.tenant_smtp_configs
FOR EACH ROW
EXECUTE FUNCTION public.set_course_assignments_updated_at();

DROP TRIGGER IF EXISTS trg_email_outbox_updated_at ON public.email_outbox;
CREATE TRIGGER trg_email_outbox_updated_at
BEFORE UPDATE ON public.email_outbox
FOR EACH ROW
EXECUTE FUNCTION public.set_course_assignments_updated_at();

COMMENT ON TABLE public.course_assignments IS 'Course-level homework assignments rendered after course sections, outside course_blocks.';
COMMENT ON TABLE public.assignment_submissions IS 'Learner assignment submissions. Missing row means not_submitted.';
COMMENT ON TABLE public.assignment_files IS 'Indexed private assignment file registry used by authenticated download endpoints.';
COMMENT ON TABLE public.tenant_smtp_configs IS 'Encrypted tenant SMTP settings, editable by superadmin only through backend APIs.';
COMMENT ON TABLE public.email_outbox IS 'Retryable email delivery queue for assignment feedback emails.';
