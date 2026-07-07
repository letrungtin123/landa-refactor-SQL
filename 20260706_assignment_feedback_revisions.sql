-- Manual SQL: Allow admins to revise assignment feedback
-- Created: 2026-07-06
-- Purpose:
--   - Remove the old database-level one-feedback-only guard.
--   - Keep a single current feedback record per submission; revisions overwrite feedback fields.
--   - Append every feedback write to assignment_feedback_history for admin audit/review.
--   - Backend still sends a fresh learner notification and SMTP email on every feedback revision.
-- Safety:
--   - Idempotent CREATE/DROP statements.
--   - Backfills existing current feedback into history once.
--   - Does not change existing current feedback data.

CREATE TABLE IF NOT EXISTS public.assignment_feedback_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL,
  course_id VARCHAR(255) NOT NULL,
  assignment_id UUID NOT NULL,
  submission_id UUID NOT NULL,
  learner_id UUID NOT NULL,
  feedback_text TEXT NOT NULL,
  feedback_files JSONB NOT NULL DEFAULT '[]'::jsonb,
  score INTEGER NULL,
  feedback_by UUID NULL,
  feedback_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT assignment_feedback_history_score_range_chk
    CHECK (score IS NULL OR (score >= 0 AND score <= 100))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'assignment_feedback_history_submission_fk'
      AND conrelid = 'public.assignment_feedback_history'::regclass
  ) THEN
    ALTER TABLE public.assignment_feedback_history
      ADD CONSTRAINT assignment_feedback_history_submission_fk
      FOREIGN KEY (submission_id)
      REFERENCES public.assignment_submissions(id)
      ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_assignment_feedback_history_submission
  ON public.assignment_feedback_history (tenant_id, submission_id, feedback_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_assignment_feedback_history_course
  ON public.assignment_feedback_history (tenant_id, course_id, assignment_id, learner_id, feedback_at DESC, id DESC);

INSERT INTO public.assignment_feedback_history (
  tenant_id, course_id, assignment_id, submission_id, learner_id,
  feedback_text, feedback_files, score, feedback_by, feedback_at
)
SELECT
  s.tenant_id,
  s.course_id,
  s.assignment_id,
  s.id,
  s.learner_id,
  COALESCE(s.feedback_text, ''),
  COALESCE(s.feedback_files, '[]'::jsonb),
  s.score,
  s.feedback_by,
  COALESCE(s.feedback_at, s.updated_at, now())
FROM public.assignment_submissions s
WHERE s.feedback_at IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.assignment_feedback_history h
    WHERE h.submission_id = s.id
      AND h.feedback_at = s.feedback_at
      AND h.feedback_by IS NOT DISTINCT FROM s.feedback_by
  );

DROP TRIGGER IF EXISTS trg_assignment_feedback_once ON public.assignment_submissions;

DROP FUNCTION IF EXISTS public.prevent_assignment_feedback_overwrite();
