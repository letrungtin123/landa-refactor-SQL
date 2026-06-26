-- ═══════════════════════════════════════════════════════════════
-- 006: Thêm revoked_at cho refresh_tokens — Grace period detection
--
-- Mục đích:
--   Phân biệt race condition (revoked < 10s) vs token theft (> 10s)
--   để tránh "nuclear revoke all" khi FE gửi duplicate refresh requests.
--
-- Trước đây: revoked token bị reuse → revoke TẤT CẢ tokens → user bị kick
-- Sau fix:   revoked token bị reuse trong 10s → chỉ reject request đó
--            revoked token bị reuse sau 10s → nuclear revoke (likely theft)
-- ═══════════════════════════════════════════════════════════════

-- Thêm column revoked_at — NULL cho tokens chưa bị revoke
ALTER TABLE refresh_tokens
  ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ DEFAULT NULL;

-- Index hỗ trợ query refresh — chỉ index revoked tokens (partial index, nhẹ)
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_revoked_at
  ON refresh_tokens (revoked_at)
  WHERE revoked = true;

-- Backfill: tokens đã revoked trước migration → set revoked_at = 1h trước
-- Để backend coi đây là "old revokes" → nuclear revoke nếu bị reuse (đúng behavior cũ)
UPDATE refresh_tokens
SET revoked_at = now() - interval '1 hour'
WHERE revoked = true AND revoked_at IS NULL;
