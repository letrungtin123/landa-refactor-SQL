-- Add required course description storage.
-- Run manually in Supabase SQL Editor.
-- Existing courses receive an empty string so the migration does not require
-- inventing description text for historical data. New create/update flows are
-- enforced by backend and dashboard validation.

ALTER TABLE public.courses
  ADD COLUMN IF NOT EXISTS description text NOT NULL DEFAULT '';

COMMENT ON COLUMN public.courses.description IS
  'Course description required by dashboard/backend validation for new course CRUD flows.';
