-- Assignment feedback notification metadata
-- Apply this before deploying the backend change that writes notification metadata.

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS type varchar(64),
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_notifications_type_created
  ON notifications (type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_metadata_gin
  ON notifications USING gin (metadata);
