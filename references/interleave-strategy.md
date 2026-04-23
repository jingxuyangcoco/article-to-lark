# Interleave strategy

## Principle

Feishu `+media-insert` always appends to the document's END. To place N images inline, split the body into `N + 1` text segments and interleave:

```
append seg01 → +media-insert img01 → append seg02 → +media-insert img02 → ...
                                                              ... → +media-insert imgN → append seg(N+1)
```

Total ops = `2N + 1`.

## Segment boundary rules

For each image in the source article, find its **anchor** — the last block (paragraph, heading, bullet list, callout) that immediately precedes it. The segment for that image ENDS at the anchor.

Example (source):

```
### Pipeline RAG 适用的场景

<image url=".../img04"/>

当你的产品需求符合以下特征时...
- bullet 1
- bullet 2
```

→ `segN.md` contains `### Pipeline RAG 适用的场景\n` (heading alone)
→ `segN+1.md` starts with `当你的产品需求...\n- bullet 1\n- bullet 2`

## Hard constraints

| Constraint | Why | How to honor |
|-----------|-----|--------------|
| Callout self-contained in one seg | `<callout>...</callout>` split across append calls corrupts structure | Keep the entire callout in one file; if image originally sat inside a callout, move it just before or just after |
| Bullet list not split | Feishu treats each append as a new block group; splitting bullets breaks list continuity | Group consecutive bullets into one seg |
| Code fence balanced | Unbalanced fence → subsequent text renders as code | Either whole block in one seg, or move image before/after the block |
| No `<image>` tags in any seg | Images come via `+media-insert` separately | Strip all `<image url=...>` from segments |
| `---` separator as own block | Appending it works, but keep it at a seg boundary for clarity | Put separator at start or end of a seg |
| Last seg ends with 原文链接 callout | Required tail for foreign articles | Append the callout block to `seg(N+1).md` |

## Validation checklist (run before launching upload)

```bash
# 1. Segment count matches images + 1
SEGS=$(ls segs/seg*.md | wc -l)
IMGS=$(ls imgs/img*.png | wc -l)
[ "$SEGS" -eq "$((IMGS + 1))" ] || echo "MISMATCH: $SEGS segs vs $IMGS imgs"

# 2. No <image url=...> leaks into segments
grep -l '<image url=' segs/ && echo "LEAK: image tag in seg" || echo "clean"

# 3. Callout balance
for f in segs/*.md; do
  open=$(grep -c '<callout' "$f")
  close=$(grep -c '</callout>' "$f")
  [ "$open" -eq "$close" ] || echo "UNBALANCED callout in $f"
done

# 4. Code fence balance
for f in segs/*.md; do
  fences=$(grep -c '^```' "$f")
  [ $((fences % 2)) -eq 0 ] || echo "UNBALANCED code fence in $f"
done

# 5. No segment is empty
for f in segs/*.md; do
  [ -s "$f" ] || echo "EMPTY: $f"
done

# 6. Image files non-trivial
for f in imgs/*.png; do
  size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")
  [ "$size" -gt 10240 ] || echo "TINY (<10KB, possibly error page): $f"
done
```

All checks MUST pass before `nohup bash upload.sh & disown`.

## Handling edge cases

**Image is first block of article** (before any text): `seg01.md` should contain a single blank line `\n` or a minimal marker. Feishu accepts empty-ish appends. Or promote the next block (e.g. quote / heading) into seg01.

**Two images adjacent** (no text between): create an empty or minimal `segK.md` (one blank line) so the interleave loop logic doesn't break. Alternatively, collapse adjacent images into one seg boundary and accept them rendering back-to-back.

**Image inside a callout**: Lark callouts don't support nested image blocks. Pull the image out to either before or after the callout, whichever fits the article flow better.

**Image inside a code block**: impossible in source, but if it looks that way strip it — likely a screenshot meant to sit adjacent to the code.

## Recovery if upload fails mid-run

```bash
# count current image blocks
DONE_IMGS=$(lark-cli api GET "/open-apis/docx/v1/documents/$DOC/blocks" \
  --params '{"page_size":500,"document_revision_id":-1}' \
  --jq '[.data.items[] | select(.block_type==27)] | length')

# resume from seg(DONE_IMGS+1) — edit loop's $(seq START N)
```

If image positions are wrong instead of missing (e.g. you appended text all at once then media-inserted later), **delete the doc and start over**. `file_token`s are not reusable (see gotchas.md #3).
