# PDFMathTranslate-next Repair Plan

## Goal

Restore consistency between the desktop Web UI, the FastAPI contract, persisted task state, and the translation engine. The work is deliberately split into independent batches so that security and data correctness land before interface polish.

## Completion Rules

- A submitted task must retain its source file and a complete, immutable option snapshot after restart; retry uses that snapshot.
- Settings shown on the workbench must be the settings that task creation sends to the API.
- UI labels must be derived from real task state. No placeholder page numbers, glossary terms, or watermarked-state claims may be displayed as facts.
- Upload and file-preview routes must reject traversal, non-PDF data, and files over the documented maximum.
- Configuration writes must target the active configuration file and fields explicitly submitted as empty must be clearable.
- Concurrent translation count and request limiting must be application-wide and bounded.

## Batch 1: API Safety and Data Contracts

**Owner: Agent A (exclusive owner of `source/pdf2zh_next/http_api.py`)**

1. Validate `file_id` as an application-generated upload identifier before using it in task creation or preview routes. Resolve paths and require descendants of `UPLOAD_DIR` as defense in depth.
2. Stream uploads with a 100 MiB maximum, remove partial files on failure, and open the completed upload through PyMuPDF before accepting it.
3. Split task serialization into a public API DTO and a persisted DTO. The persisted form retains `file_path`, source file metadata, and a full task-options snapshot; the public form never leaks absolute paths.
4. Update task retry to recreate jobs from the original snapshot, including output modes, automatic glossary extraction, and watermark mode.
5. Add `watermark_output_mode` to validated settings/task schemas and expose its effective value in task outputs.
6. Make task scheduling bounded with a shared worker executor/queue and make configured request rate/concurrency limits shared across tasks.
7. Use `model_fields_set` to distinguish omitted settings from explicitly empty fields, so API Key, base URL, and model can be cleared intentionally.
8. Parse and delete glossary CSV with Python's `csv` module. At the API boundary accept legacy comma/semicolon glossary path strings, but write one canonical convention.

Acceptance checks:

- Traversal-shaped IDs return a client error and cannot reach files outside `UPLOAD_DIR`.
- A 100 MiB+ request returns `413`; invalid PDF content returns `400`; no partial upload remains.
- Serialize, reload, then retry a task fixture successfully, retaining every recorded option.
- Enqueue more tasks than the configured worker limit and verify excess tasks remain `queued` until capacity is available.
- Set then clear each configurable credential field and confirm the API response accurately reflects the clear.
- Two glossary files both reach the engine; quoted commas and newlines in CSV rows round-trip correctly.

## Batch 2: Configuration, Glossaries, and Package Integrity

**Owner: Agent B**

1. Make `ConfigManager` write to the selected `--config-file` / `PDF2ZH_CONFIG_FILE` path rather than the hard-coded default location, including configuration-directory creation and atomic replacement.
2. Make the engine accept both legacy semicolon-separated and canonical comma-separated glossary path values until settings can use a native list end to end.
3. Import `ClaudeCodeSettings` or remove it from the root package export so wildcard import is valid.

Acceptance checks:

- Saving through an explicit config path never changes the default config file.
- `from pdf2zh_next import *` completes successfully.

## Batch 3: Workbench UI and Responsive Behavior

**Owner: Agent C**

Design direction: retain the existing desktop-first, dense translation-workbench visual language. Changes must improve state fidelity and narrow-window ergonomics without introducing decorative redesign or new visual systems.

1. Make `loadSettings()` populate workbench language selectors, page range, output toggles, auto glossary extraction, and watermark mode. Task submission must send the corresponding effective values.
2. Restore polling for the latest active task on page reload and render its current progress before starting the interval.
3. Replace the empty-preview placeholder's fabricated page/mode text with a true empty state; update it only from preview metadata.
4. Render actual glossary entries from `/api/glossary`; use an explicit empty state when there are none.
5. Remove the unimplemented “立即使用” command, or implement its stated shortcut end to end. Do not leave an inactive action.
6. Remove or defer the UI-language selector until localization exists, or implement a complete local dictionary for all shipped Chinese strings. The initial repair should prefer removing/de-emphasizing a false control.
7. Add a narrow-screen breakpoint below 720 px: convert the fixed sidebar into an accessible compact navigation control, make top-bar actions wrap safely, and preserve minimum readable widths for toolbars and workbench controls.
8. Correct RPM presentation so it cannot imply a precision that the backend cannot enforce; coordinate with Batch 1 if a fractional rate limiter is introduced.

Acceptance checks:

- Save non-default settings, reload, submit a task, and inspect its recorded options.
- Reload while a task is running and confirm progress continues without a second submission.
- At 390 px and desktop width, verify no horizontal clipping, illegible single-character wrapping, or overlap.
- Empty preview/glossary states contain no fabricated document data.

## Integration and Release Verification

1. Reconcile API payload names across the three batches and resolve merge overlaps before testing.
2. Run Python compile checks and targeted tests for API paths, task persistence/retry, settings updates, glossary CSV behavior, and queue capacity.
3. Run JavaScript syntax checking and exercise workbench, settings, queue, output, glossary, preview, and responsive states in a real browser.
4. Build the Windows launcher and confirm the packaged entry path uses the same source/runtime code that was fixed. If release runtime comes from `uv-tools/.../site-packages`, synchronize it through the build pipeline rather than making source-only edits.
5. Conduct an independent post-change review for regressions, security checks, and UI state accuracy before declaring the repair complete.

## Non-Goals

- No unrelated visual redesign.
- No migration of translation-engine behavior beyond the configuration and scheduling contract required for correctness.
- No release, installer publication, or deletion of user configuration/data during this repair.
