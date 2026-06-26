-- Title: Course uploaded-video orphan reference audit
-- Purpose: Find published video data that points to missing course video assets/objects.
-- Affected schema: public, storage
-- Affected tables: public.course_blocks, public.course_assets, storage.objects
-- Risk level: Low when used as-is, because this file is audit-only by default.
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Export target rows before applying any manual cleanup.
-- Notes:
--   - This file is intentionally SELECT-only by default.
--   - It is safe to run in different environments because it discovers matching rows
--     dynamically from that environment's data.
--   - Do not treat this as a migration. Data cleanup must be reviewed per environment.
--   - If cleanup is needed, use the commented manual template at the bottom after review.

-- 1) Audit orphan published video refs.
-- Expected healthy result: zero rows.
WITH refs AS (
  SELECT cb.id,
         cb.course_id,
         cb.block_type,
         cb.display_name,
         cb.data AS draft_data,
         cb.published_data,
         cb.published_metadata,
         v.location,
         v.storage_path
    FROM public.course_blocks cb
    CROSS JOIN LATERAL (
      VALUES
        ('published_data.url', cb.published_data ->> 'url'),
        ('published_data.video_url', cb.published_data ->> 'video_url'),
        ('published_data.encoded_videos.fallback.url', cb.published_data #>> '{encoded_videos,fallback,url}')
    ) AS v(location, storage_path)
   WHERE cb.deleted_at IS NULL
     AND cb.block_type = 'video'
     AND v.storage_path IS NOT NULL
     AND v.storage_path <> ''
     AND v.storage_path NOT LIKE 'http%'
     AND v.storage_path ~* '^[0-9a-f-]{36}/courses/.+/.+'
)
SELECT refs.id,
       refs.course_id,
       refs.block_type,
       refs.display_name,
       refs.location,
       refs.storage_path,
       refs.draft_data,
       refs.published_data,
       refs.published_metadata
  FROM refs
  LEFT JOIN public.course_assets ca
    ON ca.course_id = refs.course_id
   AND (ca.storage_path = refs.storage_path OR ca.url = refs.storage_path)
  LEFT JOIN storage.objects so
    ON so.bucket_id = 'landa-storage'
   AND so.name = refs.storage_path
 WHERE ca.id IS NULL
   AND so.id IS NULL
 ORDER BY refs.course_id, refs.id, refs.location;

-- 2) Count by course for quick cross-environment review.
WITH refs AS (
  SELECT cb.id,
         cb.course_id,
         v.storage_path
    FROM public.course_blocks cb
    CROSS JOIN LATERAL (
      VALUES
        (cb.published_data ->> 'url'),
        (cb.published_data ->> 'video_url'),
        (cb.published_data #>> '{encoded_videos,fallback,url}')
    ) AS v(storage_path)
   WHERE cb.deleted_at IS NULL
     AND cb.block_type = 'video'
     AND v.storage_path IS NOT NULL
     AND v.storage_path <> ''
     AND v.storage_path NOT LIKE 'http%'
     AND v.storage_path ~* '^[0-9a-f-]{36}/courses/.+/.+'
), orphan_refs AS (
  SELECT refs.*
    FROM refs
    LEFT JOIN public.course_assets ca
      ON ca.course_id = refs.course_id
     AND (ca.storage_path = refs.storage_path OR ca.url = refs.storage_path)
    LEFT JOIN storage.objects so
      ON so.bucket_id = 'landa-storage'
     AND so.name = refs.storage_path
   WHERE ca.id IS NULL
     AND so.id IS NULL
)
SELECT course_id,
       COUNT(DISTINCT id) AS affected_blocks,
       COUNT(*) AS orphan_refs
  FROM orphan_refs
 GROUP BY course_id
 ORDER BY orphan_refs DESC, course_id;

-- 3) Manual cleanup template.
-- Do not run this block blindly. It is commented on purpose.
-- Review the audit rows first, export backups, then adapt the WHERE clause to a
-- specific block/course/storage_path that you intentionally want to repair.
--
-- BEGIN;
--
-- UPDATE public.course_blocks
--    SET published_data = data,
--        updated_at = now()
--  WHERE id = '<reviewed_block_id>'
--    AND course_id = '<reviewed_course_id>'
--    AND deleted_at IS NULL
--    AND block_type = 'video'
--    AND published_data::text LIKE '%<reviewed_missing_storage_path>%'
--    AND COALESCE(data::text, '') NOT LIKE '%<reviewed_missing_storage_path>%';
--
-- -- Verify the specific block is fixed.
-- SELECT id, course_id, data, published_data
--   FROM public.course_blocks
--  WHERE id = '<reviewed_block_id>';
--
-- -- Roll back before commit if verification is wrong:
-- -- ROLLBACK;
-- COMMIT;
