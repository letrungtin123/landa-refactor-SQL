-- Manual SQL: Add deadline and grading controls for course assignments
-- Created: 2026-07-06
-- Purpose:
--   - Allow admins to optionally set assignment submission deadlines.
--   - Allow admins to optionally grade submissions with a score from 0 to 100.
--   - Keep the existing one-feedback-only rule immutable, including score.
-- Safety:
--   - Idempotent ADD COLUMN / ADD CONSTRAINT blocks.
--   - Does not mutate existing assignment visibility or submission status.

ALTER TABLE public.course_assignments
  ADD COLUMN IF NOT EXISTS deadline_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deadline_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS grading_enabled BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.assignment_submissions
  ADD COLUMN IF NOT EXISTS score INTEGER NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'assignment_submissions_score_range_chk'
      AND conrelid = 'public.assignment_submissions'::regclass
  ) THEN
    ALTER TABLE public.assignment_submissions
      ADD CONSTRAINT assignment_submissions_score_range_chk
      CHECK (score IS NULL OR (score >= 0 AND score <= 100));
  END IF;
END $$;

COMMENT ON COLUMN public.course_assignments.deadline_enabled IS
  'When true, learner submissions are blocked after deadline_at while the assignment remains visible if published.';

COMMENT ON COLUMN public.course_assignments.deadline_at IS
  'Optional assignment submission deadline. Only enforced when deadline_enabled is true.';

COMMENT ON COLUMN public.course_assignments.grading_enabled IS
  'When true, admin feedback requires a score between 0 and 100.';

COMMENT ON COLUMN public.assignment_submissions.score IS
  'Optional admin score for graded assignments. Valid range: 0-100.';

CREATE OR REPLACE FUNCTION public.prevent_assignment_feedback_overwrite()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF OLD.feedback_at IS NOT NULL
     AND (
       NEW.status IS DISTINCT FROM OLD.status
       OR NEW.feedback_text IS DISTINCT FROM OLD.feedback_text
       OR NEW.feedback_files IS DISTINCT FROM OLD.feedback_files
       OR NEW.feedback_by IS DISTINCT FROM OLD.feedback_by
       OR NEW.feedback_at IS DISTINCT FROM OLD.feedback_at
       OR NEW.score IS DISTINCT FROM OLD.score
     )
  THEN
    RAISE EXCEPTION 'assignment submission feedback can only be written once';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_assignment_feedback_once ON public.assignment_submissions;

CREATE TRIGGER trg_assignment_feedback_once
BEFORE UPDATE OF status, feedback_text, feedback_files, feedback_by, feedback_at, score
ON public.assignment_submissions
FOR EACH ROW
EXECUTE FUNCTION public.prevent_assignment_feedback_overwrite();
