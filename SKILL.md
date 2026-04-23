---
name: article-to-lark
description: Scrape an article from a public URL (English or Chinese) and publish it as a Feishu docx with images placed inline at their original positions. For foreign articles, translate to Chinese with the 保留英文+首次中文注释 style and append an 原文链接 callout. Use when the user provides an article URL and asks to convert / publish / 转成飞书文档.
---

# article-to-lark

## When to invoke

User provides an article URL and asks for a Feishu doc. Typical phrasings:

- "把 https://... 转成飞书文档"
- "爬一下这篇文章做成飞书文档"
- "https://... 翻译成中文发到飞书"
- "这篇 Medium 发一份到飞书"

Do NOT use this skill for editing an existing Feishu doc — use `lark-doc` directly.

## Prerequisites — MUST read first

1. `../lark-doc/SKILL.md` — `lark-cli docs +update` / `+media-insert` semantics
2. `../lark-shared/SKILL.md` — auth & permission handling

## Defaults (apply silently unless user overrides)

| Item | Default |
|------|---------|
| Storage | 「我的空间」root (vanilla `POST /docx/v1/documents`) |
| Title | Translated article title (if source is foreign), else original title |
| Translation style | 保留英文 + 首次中文注释, 末尾加原文链接 callout |
| Images | Download locally via curl, then upload via `+media-insert` |
| Rate-limit sleep | 15s between ops |
| Execution | Background detached script (`nohup ... & disown`) |

Only ask the user when something is genuinely ambiguous (e.g. article language is Chinese — skip translation? or target folder is not root).

## Workflow

Work in a throwaway scratch dir: `SCRATCH=/tmp/article-$(date +%s) && mkdir -p $SCRATCH/{segs,imgs} && cd $SCRATCH`

### 1. Fetch article

Use `mcp__webfetch__web_fetch` with `format: markdown`. Ask for the full article body — if the response is truncated, paginate via `offset`/`limit` on the saved tool-result file.

Extract:
- Article title
- Author
- Publish date
- Full body markdown
- Ordered list of image URLs with their position (the paragraph / heading they appear right after)

### 2. Plan image positions

Number images `img01` .. `imgN` in reading order. For each, record the anchor — the last block (paragraph / heading / bullet group / callout) that precedes it in the source.

Output a mental map with `N+1` text segments and `N` images interleaved:

```
[seg01] → img01 → [seg02] → img02 → ... → imgN → [segN+1]
```

### 3. Download images

```bash
curl -sL -o imgs/img01.png "<url1>"
curl -sL -o imgs/img02.png "<url2>"
# ...
# verify every file is > 10KB (tiny files are error pages)
ls -la imgs/
```

Some CDNs require `User-Agent` / `Referer`. If `curl` returns HTML, add `-H "User-Agent: Mozilla/5.0"` and `-H "Referer: <article-url>"`.

### 4. Translate + write segments

If source language ≠ Chinese: translate following `references/translation-style.md`. Default is 保留英文 + 首次中文注释.

Write `segs/seg01.md` .. `segs/seg(N+1).md`. Each segment contains the text that appears BEFORE the next image (the last segment is everything AFTER the final image).

**Rules:**
- Use Lark-flavored Markdown (`<callout>`, `<grid>`, headings, bullets, code fences, `---`)
- **Never put `<image url="...">` in any segment** — images come via `+media-insert`
- A callout's `<callout>...</callout>` MUST be self-contained within ONE segment
- A bullet list SHOULD be kept in one segment (don't split between items)
- Code fences MUST be balanced within one segment
- The last segment should end with the 原文链接 callout (see translation-style)

### 5. Create empty Feishu doc

```bash
lark-cli api POST /open-apis/docx/v1/documents \
  --data "{\"title\":\"<translated title>\"}" \
  --jq '.data.document.document_id'
```

Capture the returned `document_id` into `$DOC`. **Do NOT** use `docs +create --markdown` — that path is async and not pollable via lark-cli.

### 6. Write interleave script

```bash
cat > upload.sh <<'EOF'
#!/bin/bash
DOC="<document_id>"
cd <scratch-dir>

log() { echo "[$(date +%H:%M:%S)] $1"; }

N=17  # number of images
for i in $(seq 1 $N); do
  NN=$(printf "%02d" $i)
  log "append seg${NN}"
  lark-cli docs +update --doc "$DOC" --mode append --markdown @segs/seg${NN}.md > /dev/null 2>&1
  sleep 15
  log "media-insert img${NN}"
  lark-cli docs +media-insert --doc "$DOC" --file "./imgs/img${NN}.png" --align center > /dev/null 2>&1
  sleep 13
done

LAST=$(printf "%02d" $((N + 1)))
log "append seg${LAST}"
lark-cli docs +update --doc "$DOC" --mode append --markdown @segs/seg${LAST}.md > /dev/null 2>&1
log "DONE"
EOF
chmod +x upload.sh
```

### 7. Launch detached

```bash
nohup bash upload.sh > upload.log 2>&1 &
disown
```

Expected runtime ≈ `(2N + 1) × 15s`. For a 17-image article that's ~9 minutes.

Monitor with `tail -f upload.log`. Do NOT `wait` for it — exit the shell session returns immediately; the detached process keeps running.

### 8. Verify after DONE

```bash
# image count should equal N
lark-cli api GET "/open-apis/docx/v1/documents/$DOC/blocks" \
  --params '{"page_size":500,"document_revision_id":-1}' \
  --jq '[.data.items[] | select(.block_type==27)] | length'

# quick structure sanity check — block types in order
lark-cli api GET "/open-apis/docx/v1/documents/$DOC/blocks" \
  --params '{"page_size":500,"document_revision_id":-1}' \
  --jq '[.data.items[] | .block_type] | join(" ")'
```

Print final URL to user: `https://<tenant>.feishu.cn/docx/$DOC`

## Critical gotchas — see `references/gotchas.md` for detail

1. **`+media-insert` appends to doc END only.** No position flag exists. Interleave is the only way to place images inline.
2. **External image URLs in markdown do NOT download server-side.** Medium, GitHub raw, Substack CDN all block Feishu fetch. Always download + `+media-insert --file`.
3. **file_tokens are not reusable across blocks.** If image positions are wrong after upload, you CANNOT fix by creating new blocks with existing tokens (error `1770013 relation mismatch`). Delete the doc and restart.
4. **`docs +create --markdown` is async and unpollable** — use raw `POST /docx/v1/documents` for sync empty-doc creation.
5. **Rate limits: 3 req/sec per app, 3 concurrent edits/sec per doc.** Use 13-15s sleep between ops.
6. **Long scripts must be detached** (`nohup ... & disown`) or they die when Claude's shell timeout fires.

## References

- [gotchas.md](references/gotchas.md) — full pitfall catalog with error codes
- [interleave-strategy.md](references/interleave-strategy.md) — segment boundary rules, validation checklist
- [translation-style.md](references/translation-style.md) — 保留英文+首次中文注释 rules, required tail callout
