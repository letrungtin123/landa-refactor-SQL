-- Title: Assignment progress and deadline modes
-- Purpose:
--   - Add assignment submission unlock mode for learner access control.
--   - Add immutable assignment deadline modes: none, absolute, relative to enrollment.
--   - Add indexes used by assignment-aware course progress recalculation.
-- Affected schema: public
-- Affected tables: public.course_assignments, public.assignment_submissions
-- Risk level: Medium
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation:
--   - Backup public.course_assignments and public.assignment_submissions before execution.
-- Notes:
--   - This file is idempotent for columns, constraints, indexes, function, and trigger.
--   - Existing absolute deadlines are backfilled from deadline_enabled + deadline_at.
--   - The trigger prevents changing deadline_mode after creation and prevents editing
--     deadline_after_days for relative-to-enrollment assignments.
--   - Run 20260708_1119_assignment_progress_deadline_indexes_concurrently.sql separately
--     after this file. It contains CREATE INDEX CONCURRENTLY statements that must run
--     outside any transaction block.

BEGIN;

ALTER TABLE public.course_assignments
  ADD COLUMN IF NOT EXISTS deadline_mode VARCHAR(32),
  ADD COLUMN IF NOT EXISTS deadline_after_days INTEGER NULL,
  ADD COLUMN IF NOT EXISTS submission_unlock_mode VARCHAR(32) NOT NULL DEFAULT 'after_content_complete';

UPDATE public.course_assignments
SET deadline_mode = CASE
  WHEN deadline_enabled = true AND deadline_at IS NOT NULL THEN 'absolute'
  ELSE 'none'
END
WHERE deadline_mode IS NULL;

UPDATE public.course_assignments
SET
  deadline_enabled = (deadline_mode <> 'none'),
  deadline_at = CASE WHEN deadline_mode = 'absolute' THEN deadline_at ELSE NULL END,
  deadline_after_days = CASE WHEN deadline_mode = 'relative_to_enrollment' THEN deadline_after_days ELSE NULL END,
  submission_unlock_mode = COALESCE(submission_unlock_mode, 'after_content_complete');

ALTER TABLE public.course_assignments
  ALTER COLUMN deadline_mode SET DEFAULT 'none',
  ALTER COLUMN deadline_mode SET NOT NULL,
  ALTER COLUMN submission_unlock_mode SET DEFAULT 'after_content_complete',
  ALTER COLUMN submission_unlock_mode SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'course_assignments_deadline_mode_chk'
      AND conrelid = 'public.course_assignments'::regclass
  ) THEN
    ALTER TABLE public.course_assignments
      ADD CONSTRAINT course_assignments_deadline_mode_chk
      CHECK (deadline_mode IN ('none', 'absolute', 'relative_to_enrollment'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'course_assignments_deadline_after_days_chk'
      AND conrelid = 'public.course_assignments'::regclass
  ) THEN
    ALTER TABLE public.course_assignments
      ADD CONSTRAINT course_assignments_deadline_after_days_chk
      CHECK (deadline_after_days IS NULL OR (deadline_after_days >= 1 AND deadline_after_days <= 3650));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'course_assignments_deadline_shape_chk'
      AND conrelid = 'public.course_assignments'::regclass
  ) THEN
    ALTER TABLE public.course_assignments
      ADD CONSTRAINT course_assignments_deadline_shape_chk
      CHECK (
        (
          deadline_mode = 'none'
          AND deadline_enabled = false
          AND deadline_at IS NULL
          AND deadline_after_days IS NULL
        )
        OR (
          deadline_mode = 'absolute'
          AND deadline_enabled = true
          AND deadline_at IS NOT NULL
          AND deadline_after_days IS NULL
        )
        OR (
          deadline_mode = 'relative_to_enrollment'
          AND deadline_enabled = true
          AND deadline_at IS NULL
          AND deadline_after_days IS NOT NULL
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'course_assignments_submission_unlock_mode_chk'
      AND conrelid = 'public.course_assignments'::regclass
  ) THEN
    ALTER TABLE public.course_assignments
      ADD CONSTRAINT course_assignments_submission_unlock_mode_chk
      CHECK (submission_unlock_mode IN ('after_content_complete', 'anytime'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.prevent_course_assignment_deadline_mode_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.deadline_mode IS DISTINCT FROM OLD.deadline_mode THEN
      RAISE EXCEPTION 'course assignment deadline_mode cannot be changed after creation';
    END IF;

    IF OLD.deadline_mode = 'relative_to_enrollment'
       AND NEW.deadline_after_days IS DISTINCT FROM OLD.deadline_after_days
    THEN
      RAISE EXCEPTION 'relative assignment deadline_after_days cannot be changed after creation';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_prevent_course_assignment_deadline_mode_mutation
  ON public.course_assignments;

CREATE TRIGGER trg_prevent_course_assignment_deadline_mode_mutation
BEFORE UPDATE OF deadline_mode, deadline_after_days
ON public.course_assignments
FOR EACH ROW
EXECUTE FUNCTION public.prevent_course_assignment_deadline_mode_mutation();

COMMENT ON COLUMN public.course_assignments.deadline_mode IS
  'Assignment deadline mode: none, absolute, or relative_to_enrollment. Immutable after creation.';

COMMENT ON COLUMN public.course_assignments.deadline_after_days IS
  'Number of days after enrollment when deadline_mode is relative_to_enrollment. Immutable after creation for relative assignments.';

COMMENT ON COLUMN public.course_assignments.submission_unlock_mode IS
  'Controls when learners can submit: after_content_complete or anytime.';

COMMIT;

-- Verification queries:
-- SELECT deadline_mode, COUNT(*) FROM public.course_assignments GROUP BY deadline_mode ORDER BY deadline_mode;
-- SELECT submission_unlock_mode, COUNT(*) FROM public.course_assignments GROUP BY submission_unlock_mode ORDER BY submission_unlock_mode;
-- Run the separate concurrent index SQL file, then verify indexes with:
-- SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND tablename IN ('course_assignments', 'assignment_submissions') AND indexname IN ('idx_course_assignments_progress_published', 'idx_assignment_submissions_progress_completed');
-- SELECT tgname FROM pg_trigger WHERE tgname = 'trg_prevent_course_assignment_deadline_mode_mutation';

-- Rollback SQL, manual only:
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_prevent_course_assignment_deadline_mode_mutation ON public.course_assignments;
-- DROP FUNCTION IF EXISTS public.prevent_course_assignment_deadline_mode_mutation();
-- DROP INDEX IF EXISTS public.idx_assignment_submissions_progress_completed;
-- DROP INDEX IF EXISTS public.idx_course_assignments_progress_published;
-- ALTER TABLE public.course_assignments DROP CONSTRAINT IF EXISTS course_assignments_submission_unlock_mode_chk;
-- ALTER TABLE public.course_assignments DROP CONSTRAINT IF EXISTS course_assignments_deadline_shape_chk;
-- ALTER TABLE public.course_assignments DROP CONSTRAINT IF EXISTS course_assignments_deadline_after_days_chk;
-- ALTER TABLE public.course_assignments DROP CONSTRAINT IF EXISTS course_assignments_deadline_mode_chk;
-- ALTER TABLE public.course_assignments DROP COLUMN IF EXISTS submission_unlock_mode;
-- ALTER TABLE public.course_assignments DROP COLUMN IF EXISTS deadline_after_days;
-- ALTER TABLE public.course_assignments DROP COLUMN IF EXISTS deadline_mode;
-- COMMIT;
