# Gotchas

Every item below comes from a real failure during skill development. Skipping any of them risks hours of redo.

## 1. `+media-insert` appends to document END — always

`lark-cli docs +media-insert` has NO position / index / anchor flag. The image lands after the last existing block, regardless of what you pass.

**Symptom:** You append all text first, then all images → every image ends up clustered at the tail of the document ("图片位置错乱").

**Fix:** Interleave. For N images, you need `2N+1` operations: `append seg1 → insert img1 → append seg2 → insert img2 → ... → insert imgN → append seg(N+1)`.

## 2. External image URLs don't download server-side

Feeding `<image url="https://miro.medium.com/..."/>` to `docs +update --markdown` results in a 100×100 empty placeholder block with `token: ""`.

**Confirmed blocked/broken CDNs:** Medium (miro.medium.com), GitHub raw/user-content, Substack CDN, most enterprise blog platforms.

**Fix:** Always download images locally with curl into `imgs/`, then upload via `docs +media-insert --file ./imgs/imgNN.png`. If curl returns HTML (protected by UA check), retry with:

```bash
curl -sL -H "User-Agent: Mozilla/5.0" -H "Referer: <article-url>" -o imgs/img01.png "<url>"
```

## 3. file_tokens cannot be reused across blocks

When `+media-insert` uploads an image, the returned `file_token` is permanently bound to the specific block that was created in the same call.

Attempting:
```bash
POST /docx/v1/documents/{doc}/blocks/{parent}/children
{"children":[{"block_type":27,"image":{"token":"<existing-token>",...}}]}
```
→ `1770001 invalid param`

Or creating an empty image block then running `batch_update` with `replace_image` pointing at another block's token:
→ `1770013 relation mismatch`

**Fix:** There is no way to move an image block. If positions are wrong after upload, **delete the document and recreate from scratch** with proper interleaving.

## 4. `docs +create --markdown` is async and unpollable

Returns `{"task_id": "..."}` but:
- No `lark-cli` subcommand accepts `--task-id`
- `drive +task_result --scenario task_check` returns `1061002` for this task type

**Fix:** Create empty doc synchronously via raw API, then fill with append:

```bash
DOC=$(lark-cli api POST /open-apis/docx/v1/documents \
  --data '{"title":"..."}' \
  --jq '.data.document.document_id')

lark-cli docs +update --doc "$DOC" --mode append --markdown @segs/seg01.md
```

## 5. Rate limits

- **Application:** 3 requests/sec → bursts get `99991400`
- **Per document:** 3 concurrent edits/sec → `429 Too Many Requests`

The "edit" operations that count: `Create blocks`, `Create nested blocks`, `Delete blocks`, `Update a block`, `Batch update blocks`.

**Fix:** `sleep 15` between consecutive `+update` / `+media-insert` calls. This has survived every run.

For a 17-image article: 35 ops × 15s ≈ 9 min wall time. Budget accordingly.

## 6. Long scripts die if attached to Claude's shell

`Bash` tool default timeout is 2 min, max 10 min. A 9-minute upload will be SIGTERM'd if run in the foreground (the kill cascades to children).

**Fix:** Detach properly:

```bash
nohup bash upload.sh > upload.log 2>&1 &
disown
```

Do not use `run_in_background: true` for this — you lose log stream control. The detached+nohup pattern is the only one that survives all cases.

Monitor with `tail upload.log` in periodic `Bash` calls, not `tail -f` (blocking).

## 7. Pagination on `docs +fetch` truncates images

Default is 2000 chars — long articles lose trailing images in the listing.

**Fix:** Paginate with `--offset N --limit 5000` and concatenate, OR cross-check with the source fetch (jina reader gives you the full markdown).

## 8. Callout tag splits fail silently

If you split a `<callout>...</callout>` across two `append` calls, the second call will render the closing tag as literal text and the document structure breaks.

**Fix:** Whenever writing segments, ensure every callout is fully contained in one seg file. Same for code fences and `<grid>` tags.

## 9. `docs +create --markdown` with image URLs creates empty placeholders

Even though the initial doc creation is async, if it DID succeed you'd still have the problem from gotcha #2 — all `<image url="...">` tags become empty placeholders.

**Fix:** Always follow the `empty doc + append + media-insert --file` workflow. No exceptions.

## 10. Background script needs CWD

`lark-cli docs +update --markdown @file` is CWD-relative. If your script doesn't `cd` into the scratch directory, the `@segs/seg01.md` handle resolves to the wrong path and silently fails.

**Fix:** First line of the upload script: `cd /tmp/article-<timestamp>` (absolute path).
