-- Prevent overwriting an assignment submission after feedback has been given once.
-- Backend also enforces this, but this trigger protects production data from bypass paths.

CREATE OR REPLACE FUNCTION public.prevent_assignment_feedback_overwrite()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.feedback_at IS NOT NULL
     AND (
       NEW.status IS DISTINCT FROM OLD.status
       OR NEW.feedback_text IS DISTINCT FROM OLD.feedback_text
       OR NEW.feedback_files IS DISTINCT FROM OLD.feedback_files
       OR NEW.feedback_by IS DISTINCT FROM OLD.feedback_by
       OR NEW.feedback_at IS DISTINCT FROM OLD.feedback_at
     )
  THEN
    RAISE EXCEPTION 'assignment submission feedback can only be written once';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_assignment_feedback_once ON public.assignment_submissions;
CREATE TRIGGER trg_assignment_feedback_once
BEFORE UPDATE OF status, feedback_text, feedback_files, feedback_by, feedback_at
ON public.assignment_submissions
FOR EACH ROW
EXECUTE FUNCTION public.prevent_assignment_feedback_overwrite();
