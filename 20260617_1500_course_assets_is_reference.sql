-- Migration: Add is_reference flag to course_assets
-- Date: 2026-06-17

ALTER TABLE course_assets ADD COLUMN IF NOT EXISTS is_reference BOOLEAN DEFAULT false;
