-- ═══════════════════════════════════════════════════════════════
-- Migration 005: Badge Images (Per-Tenant)
-- Thêm cột lưu URL ảnh badge vào bảng tenant_badge_settings
-- ═══════════════════════════════════════════════════════════════

-- 1. Xóa các cột đã lỡ tạo bên bảng badge_definitions (nếu có)
ALTER TABLE badge_definitions
  DROP COLUMN IF EXISTS card_image_url,
  DROP COLUMN IF EXISTS icon_image_url;

-- 2. Thêm cột vào bảng tenant_badge_settings
ALTER TABLE tenant_badge_settings
  ADD COLUMN IF NOT EXISTS card_image_url TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS icon_image_url TEXT DEFAULT NULL;
