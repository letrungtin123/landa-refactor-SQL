-- Title: Course assignment single relative deadline and attachment
-- Purpose:
--   - Force course assignments to use only no deadline or relative-to-enrollment deadlines.
--   - Keep only one active assignment per course.
--   - Add one admin attachment metadata column for each assignment.
--   - Prevent hard-deleting assignments from cascading learner submissions.
--   - Recalculate affected course_progress rows after cleanup.
-- Affected schema: public
-- Affected tables:
--   - public.course_assignments
--   - public.assignment_submissions
--   - public.assignment_files
--   - public.course_progress
-- Risk level: Medium
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation:
--   - Backup public.course_assignments, public.assignment_submissions,
--     public.assignment_files, and public.course_progress before execution.
-- Notes:
--   - Designed for Supabase SQL Editor. It does not use CREATE INDEX CONCURRENTLY.
--   - Does not use temporary tables; affected courses are derived inside the
--     final recalculation CTE so the script is safe with SQL Editor sessions.
--   - Existing absolute assignments are normalized to relative_to_enrollment with default 7 days.
--   - Existing no-deadline assignments remain no-deadline.
--   - Redundant active assignments are soft-deleted; the kept row is the assignment
--     with the most submissions, then newest created_at/id.
--   - Run during a low-traffic window because the unique index and FK changes take locks.

BEGIN;

ALTER TABLE public.course_assignments
  ADD COLUMN IF NOT EXISTS deadline_mode VARCHAR(32),
  ADD COLUMN IF NOT EXISTS deadline_after_days INTEGER NULL,
  ADD COLUMN IF NOT EXISTS submission_unlock_mode VARCHAR(32) NOT NULL DEFAULT 'after_content_complete',
  ADD COLUMN IF NOT EXISTS attachment_file JSONB NULL;

DROP TRIGGER IF EXISTS trg_prevent_course_assignment_deadline_mode_mutation
  ON public.course_assignments;

ALTER TABLE public.course_assignments
  DROP CONSTRAINT IF EXISTS course_assignments_deadline_mode_chk,
  DROP CONSTRAINT IF EXISTS course_assignments_deadline_shape_chk,
  DROP CONSTRAINT IF EXISTS course_assignments_deadline_after_days_chk,
  DROP CONSTRAINT IF EXISTS course_assignments_attachment_file_chk;

WITH ranked AS (
  SELECT
    ca.id,
    ROW_NUMBER() OVER (
      PARTITION BY ca.tenant_id, ca.course_id
      ORDER BY COUNT(s.id) DESC, ca.created_at DESC, ca.id DESC
    ) AS rn
  FROM public.course_assignments ca
  LEFT JOIN public.assignment_submissions s ON s.assignment_id = ca.id
  WHERE ca.deleted_at IS NULL
  GROUP BY ca.id, ca.tenant_id, ca.course_id, ca.created_at
)
UPDATE public.course_assignments ca
SET
  deleted_at = now(),
  is_published = false,
  updated_at = now()
FROM ranked r
WHERE ca.id = r.id
  AND r.rn > 1;

UPDATE public.course_assignments
SET
  deadline_mode = CASE
    WHEN COALESCE(deadline_mode, CASE WHEN deadline_enabled THEN 'absolute' ELSE 'none' END) = 'none'
      THEN 'none'
    ELSE 'relative_to_enrollment'
  END,
  deadline_enabled = CASE
    WHEN COALESCE(deadline_mode, CASE WHEN deadline_enabled THEN 'absolute' ELSE 'none' END) = 'none'
      THEN false
    ELSE true
  END,
  deadline_at = NULL,
  deadline_after_days = CASE
    WHEN COALESCE(deadline_mode, CASE WHEN deadline_enabled THEN 'absolute' ELSE 'none' END) = 'none'
      THEN NULL
    WHEN deadline_after_days BETWEEN 1 AND 3650
      THEN deadline_after_days
    ELSE 7
  END,
  submission_unlock_mode = COALESCE(submission_unlock_mode, 'after_content_complete'),
  updated_at = now()
WHERE COALESCE(deadline_mode, CASE WHEN deadline_enabled THEN 'absolute' ELSE 'none' END) = 'absolute'
   OR deadline_at IS NOT NULL
   OR deadline_after_days < 1
   OR deadline_after_days > 3650
   OR (COALESCE(deadline_mode, CASE WHEN deadline_enabled THEN 'absolute' ELSE 'none' END) = 'none' AND deadline_enabled IS DISTINCT FROM false)
   OR (COALESCE(deadline_mode, CASE WHEN deadline_enabled THEN 'absolute' ELSE 'none' END) = 'none' AND deadline_after_days IS NOT NULL)
   OR (COALESCE(deadline_mode, CASE WHEN deadline_enabled THEN 'absolute' ELSE 'none' END) = 'relative_to_enrollment' AND deadline_enabled IS DISTINCT FROM true)
   OR (COALESCE(deadline_mode, CASE WHEN deadline_enabled THEN 'absolute' ELSE 'none' END) = 'relative_to_enrollment' AND deadline_after_days IS NULL)
   OR submission_unlock_mode IS NULL;

ALTER TABLE public.course_assignments
  ALTER COLUMN deadline_mode SET DEFAULT 'none',
  ALTER COLUMN deadline_mode SET NOT NULL,
  ALTER COLUMN submission_unlock_mode SET DEFAULT 'after_content_complete',
  ALTER COLUMN submission_unlock_mode SET NOT NULL;

ALTER TABLE public.course_assignments
  ADD CONSTRAINT course_assignments_deadline_mode_chk
  CHECK (deadline_mode IN ('none', 'relative_to_enrollment')),
  ADD CONSTRAINT course_assignments_deadline_after_days_chk
  CHECK (deadline_after_days IS NULL OR deadline_after_days BETWEEN 1 AND 3650),
  ADD CONSTRAINT course_assignments_deadline_shape_chk
  CHECK (
    (
      deadline_enabled = false
      AND deadline_mode = 'none'
      AND deadline_at IS NULL
      AND deadline_after_days IS NULL
    )
    OR (
      deadline_enabled = true
      AND deadline_mode = 'relative_to_enrollment'
      AND deadline_at IS NULL
      AND deadline_after_days IS NOT NULL
    )
  ),
  ADD CONSTRAINT course_assignments_attachment_file_chk
  CHECK (attachment_file IS NULL OR jsonb_typeof(attachment_file) = 'object');

CREATE UNIQUE INDEX IF NOT EXISTS ux_course_assignments_one_active_per_course
  ON public.course_assignments (tenant_id, course_id)
  WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.prevent_course_assignment_deadline_mode_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.deadline_mode IS DISTINCT FROM OLD.deadline_mode THEN
      RAISE EXCEPTION 'course assignment deadline_mode cannot be changed after creation';
    END IF;

    IF NEW.deadline_after_days IS DISTINCT FROM OLD.deadline_after_days THEN
      RAISE EXCEPTION 'relative assignment deadline_after_days cannot be changed after creation';
    END IF;

    IF NEW.deadline_enabled IS DISTINCT FROM OLD.deadline_enabled
       OR NEW.deadline_at IS DISTINCT FROM OLD.deadline_at
    THEN
      RAISE EXCEPTION 'course assignment deadline shape cannot be changed after creation';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_prevent_course_assignment_deadline_mode_mutation
BEFORE UPDATE OF deadline_mode, deadline_after_days, deadline_enabled, deadline_at
ON public.course_assignments
FOR EACH ROW
EXECUTE FUNCTION public.prevent_course_assignment_deadline_mode_mutation();

ALTER TABLE public.assignment_files
  DROP CONSTRAINT IF EXISTS assignment_files_assignment_id_fkey;

ALTER TABLE public.assignment_files
  ADD CONSTRAINT assignment_files_assignment_id_fkey
  FOREIGN KEY (assignment_id)
  REFERENCES public.course_assignments(id)
  ON DELETE RESTRICT;

ALTER TABLE public.assignment_submissions
  DROP CONSTRAINT IF EXISTS assignment_submissions_assignment_id_fkey;

ALTER TABLE public.assignment_submissions
  ADD CONSTRAINT assignment_submissions_assignment_id_fkey
  FOREIGN KEY (assignment_id)
  REFERENCES public.course_assignments(id)
  ON DELETE RESTRICT;

WITH RECURSIVE assignment_affected_courses AS (
  SELECT DISTINCT course_id
  FROM public.course_assignments
),
active_tree AS (
  SELECT b.id, b.parent_id, b.block_type, b.course_id
  FROM public.course_blocks b
  JOIN public.courses c ON c.id = b.course_id
  JOIN assignment_affected_courses ac ON ac.course_id = b.course_id
  WHERE b.parent_id IS NULL
    AND b.is_published = true
    AND b.deleted_at IS NULL
    AND c.deleted_at IS NULL
  UNION ALL
  SELECT child.id, child.parent_id, child.block_type, child.course_id
  FROM public.course_blocks child
  JOIN active_tree parent ON parent.id = child.parent_id
  WHERE child.is_published = true
    AND child.deleted_at IS NULL
),
leaf_blocks AS (
  SELECT id, course_id
  FROM active_tree
  WHERE block_type NOT IN ('course','chapter','sequential','vertical')
),
active_enrollments AS (
  SELECT e.id, e.course_id
  FROM public.enrollments e
  JOIN assignment_affected_courses ac ON ac.course_id = e.course_id
  WHERE e.is_active = true
),
totals AS (
  SELECT
    ac.course_id,
    COALESCE(lb.total, 0) + COALESCE(ca.total, 0) AS total
  FROM assignment_affected_courses ac
  LEFT JOIN (
    SELECT course_id, COUNT(*)::int AS total
    FROM leaf_blocks
    GROUP BY course_id
  ) lb ON lb.course_id = ac.course_id
  LEFT JOIN (
    SELECT course_id, COUNT(*)::int AS total
    FROM public.course_assignments
    WHERE deleted_at IS NULL
      AND is_published = true
    GROUP BY course_id
  ) ca ON ca.course_id = ac.course_id
),
completed_blocks AS (
  SELECT bc.enrollment_id, COUNT(*)::int AS completed
  FROM public.block_completions bc
  JOIN leaf_blocks lb ON lb.id = bc.block_id
  JOIN active_enrollments ae ON ae.id = bc.enrollment_id
  GROUP BY bc.enrollment_id
),
completed_assignments AS (
  SELECT s.enrollment_id, COUNT(DISTINCT ca.id)::int AS completed
  FROM public.assignment_submissions s
  JOIN active_enrollments ae ON ae.id = s.enrollment_id
  JOIN public.course_assignments ca
    ON ca.id = s.assignment_id
   AND ca.course_id = ae.course_id
   AND ca.deleted_at IS NULL
   AND ca.is_published = true
  WHERE s.status IN ('submitted', 'feedback_given')
  GROUP BY s.enrollment_id
)
UPDATE public.course_progress cp
SET
  progress = CASE
    WHEN totals.total > 0 THEN ROUND((((COALESCE(cb.completed, 0) + COALESCE(ca.completed, 0))::numeric / totals.total::numeric) * 10000)) / 100
    ELSE 0
  END,
  is_completed = totals.total > 0 AND (COALESCE(cb.completed, 0) + COALESCE(ca.completed, 0)) >= totals.total,
  completed_at = CASE
    WHEN totals.total > 0 AND (COALESCE(cb.completed, 0) + COALESCE(ca.completed, 0)) >= totals.total THEN COALESCE(cp.completed_at, now())
    ELSE NULL
  END,
  last_activity_at = now(),
  updated_at = now()
FROM active_enrollments ae
CROSS JOIN totals
LEFT JOIN completed_blocks cb ON cb.enrollment_id = ae.id
LEFT JOIN completed_assignments ca ON ca.enrollment_id = ae.id
WHERE cp.enrollment_id = ae.id
  AND totals.course_id = ae.course_id;

COMMENT ON COLUMN public.course_assignments.deadline_mode IS
  'Assignment deadline mode. Only none and relative_to_enrollment are supported for course assignments.';

COMMENT ON COLUMN public.course_assignments.deadline_after_days IS
  'Number of days after learner enrollment when the assignment becomes due. Immutable after creation.';

COMMENT ON COLUMN public.course_assignments.attachment_file IS
  'Single admin-provided assignment attachment metadata. Private file content is stored in the configured storage bucket.';

COMMIT;

-- Verification queries:
-- SELECT deadline_mode, COUNT(*) FROM public.course_assignments GROUP BY deadline_mode ORDER BY deadline_mode;
-- SELECT tenant_id, course_id, COUNT(*) AS active_count
-- FROM public.course_assignments
-- WHERE deleted_at IS NULL
-- GROUP BY tenant_id, course_id
-- HAVING COUNT(*) > 1;
-- SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'ux_course_assignments_one_active_per_course';
-- SELECT conname, confdeltype FROM pg_constraint WHERE conname IN ('assignment_submissions_assignment_id_fkey', 'assignment_files_assignment_id_fkey');
-- SELECT COUNT(*) FROM public.course_assignments WHERE attachment_file IS NOT NULL AND jsonb_typeof(attachment_file) <> 'object';

-- Rollback SQL, manual only:
-- BEGIN;
-- DROP INDEX IF EXISTS public.ux_course_assignments_one_active_per_course;
-- DROP TRIGGER IF EXISTS trg_prevent_course_assignment_deadline_mode_mutation ON public.course_assignments;
-- DROP FUNCTION IF EXISTS public.prevent_course_assignment_deadline_mode_mutation();
-- ALTER TABLE public.course_assignments DROP CONSTRAINT IF EXISTS course_assignments_attachment_file_chk;
-- ALTER TABLE public.course_assignments DROP CONSTRAINT IF EXISTS course_assignments_deadline_shape_chk;
-- ALTER TABLE public.course_assignments DROP CONSTRAINT IF EXISTS course_assignments_deadline_after_days_chk;
-- ALTER TABLE public.course_assignments DROP CONSTRAINT IF EXISTS course_assignments_deadline_mode_chk;
-- ALTER TABLE public.course_assignments DROP COLUMN IF EXISTS attachment_file;
-- ALTER TABLE public.assignment_files DROP CONSTRAINT IF EXISTS assignment_files_assignment_id_fkey;
-- ALTER TABLE public.assignment_files ADD CONSTRAINT assignment_files_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.course_assignments(id) ON DELETE CASCADE;
-- ALTER TABLE public.assignment_submissions DROP CONSTRAINT IF EXISTS assignment_submissions_assignment_id_fkey;
-- ALTER TABLE public.assignment_submissions ADD CONSTRAINT assignment_submissions_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.course_assignments(id) ON DELETE CASCADE;
-- COMMIT;
