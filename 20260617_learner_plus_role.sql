-- ═══════════════════════════════════════════════════════════════
-- Migration: Thêm role learner_plus vào enum user_role
-- learner_plus = learner + có thể truy cập Dashboard nếu có permission group
-- ═══════════════════════════════════════════════════════════════

ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'learner_plus' AFTER 'learner';
