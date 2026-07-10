-- Title: Add mobile card image URL for tenant badge settings
-- Purpose: Store one optional mobile badge card image path per tenant badge.
-- Affected schema: public
-- Affected tables: public.tenant_badge_settings
-- Risk level: Low
-- Execution owner: User/manual only
-- Direct execution by Codex: Forbidden
-- Backup recommendation: Backup public.tenant_badge_settings before execution in production.
-- Notes: This is a nullable metadata column and does not rewrite existing image values.

BEGIN;

ALTER TABLE public.tenant_badge_settings
  ADD COLUMN IF NOT EXISTS mobile_card_image_url TEXT DEFAULT NULL;

COMMIT;

-- Verification queries:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'tenant_badge_settings'
--   AND column_name = 'mobile_card_image_url';

-- Rollback SQL, if needed:
-- ALTER TABLE public.tenant_badge_settings
--   DROP COLUMN IF EXISTS mobile_card_image_url;
