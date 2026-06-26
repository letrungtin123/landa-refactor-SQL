-- Title: Align lesson author system prompt JSON schema with backend
-- Purpose: Replace the `changes`-based proposal schema in system prompt
--          with the `chapters`-based schema that code expects.
-- Affected table: system_prompt_templates
-- Risk level: Medium - changes AI output format
-- Execution owner: Manual only
-- Direct execution by Codex: Forbidden
-- Backup: Take note of current prompt before running.
-- Notes:
--   Old schema: {changes: [{action, block_type, path, display_name, content}]}
--   New schema: {summary, chapters: [{title, lessons: [{title, units: [{title, components}]}]}]}
--   convertChangesToChapters() in chat.service.ts handles backward compat.
--   The section being replaced starts at "Cấu trúc đề xuất:" and ends at
--   "...tóm tắt trước rồi đến JSON."

BEGIN;

-- Use substring concatenation approach for reliable replacement
-- Section to replace: position 11743 to 13212 (inclusive)
UPDATE system_prompt_templates
SET prompt = 
  SUBSTRING(prompt FROM 1 FOR 11742)  -- everything before the section
  || E'Cấu trúc proposal bắt buộc — chỉ return JSON theo schema này:

{"summary": "Tóm tắt ngắn gọn proposal, chưa apply vào DB", "chapters": [{"title": "Exact chapter title", "lessons": [{"title": "Exact lesson/sequential title", "units": [{"title": "Exact unit/vertical title", "components": [{"type": "html", "title": "Tên component", "html": "<h3>Nội dung</h3><p>HTML sạch</p>"}, {"type": "problem", "title": "Tên quiz", "problem_type": "multiple_choice", "question": "Câu hỏi", "choices": [{"text": "Đáp án", "correct": true}], "explanation": "Giải thích"}, {"type": "la_faq", "title": "Tên FAQ", "items": [{"question": "Q", "answer": "A"}]}, {"type": "la_sortable", "title": "Tên bài sắp xếp", "question_text": "Sắp xếp đúng thứ tự", "items": ["Bước 1", "Bước 2", "Bước 3"]}, {"type": "la_crossword", "title": "Tên ô chữ", "words": [{"answer": "TERM", "clue": "Gợi ý", "hint": "Gợi ý thêm"}]}, {"type": "la_diagram", "title": "Tên sơ đồ", "name": "Diagram", "nodes": [{"label": "Node", "shape": "rectangle"}], "edges": [{"source": 0, "target": 1, "label": "liên kết"}]}]}]}]}]}

Quy tắc schema bắt buộc:

* LUÔN return JSON theo schema trên khi ở Draft lesson mode. KHÔNG dùng format changes/action/block_type.
* Chỉ dùng format: summary + chapters → lessons → units → components.
* html component: field "html" chứa HTML sạch, 500-1200 từ tiếng Việt, dùng h3/p/ul/ol/strong/em.
* problem: dùng fields question, choices (array with correct boolean), explanation, problem_type.
* la_faq: field items là array of {question, answer}, tối thiểu 2 items.
* la_sortable: fields question_text và items là array of strings, tối thiểu 3 items.
* la_crossword: field words là array of {answer, clue, hint}, tối thiểu 3 terms.
* la_diagram: fields nodes và edges, tối đa 12 nodes.
* summary mô tả proposal chưa apply, không nói đã tạo/cập nhật/xóa DB.'
  || SUBSTRING(prompt FROM 13213)  -- everything after the section
, updated_at = now()
WHERE id = '34fe8e8a-3390-46bf-8a28-8d9b0164f5d4';

COMMIT;

-- Verification queries:
-- 1. Check schema keyword presence:
-- SELECT prompt LIKE '%chapters%' as has_chapters, prompt LIKE '%changes%' as still_has_changes, LENGTH(prompt) as new_length
-- FROM system_prompt_templates WHERE id = '34fe8e8a-3390-46bf-8a28-8d9b0164f5d4';
-- Expected: has_chapters = true, still_has_changes = false (in schema section)

-- 2. Check section was replaced correctly:
-- SELECT SUBSTRING(prompt FROM 11743 FOR 200) as new_section_start
-- FROM system_prompt_templates WHERE id = '34fe8e8a-3390-46bf-8a28-8d9b0164f5d4';
-- Expected: starts with "Cấu trúc proposal bắt buộc"

-- Rollback: save original prompt before running, restore with:
-- UPDATE system_prompt_templates SET prompt = '<original>', updated_at = now()
-- WHERE id = '34fe8e8a-3390-46bf-8a28-8d9b0164f5d4';
