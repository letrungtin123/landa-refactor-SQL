-- Tăng giới hạn dung lượng upload video/file của bucket 'landa-storage' lên 100MB
-- Dung lượng tính bằng bytes: 100 * 1024 * 1024 = 104857600
UPDATE storage.buckets
SET file_size_limit = 104857600
WHERE id = 'landa-storage';
