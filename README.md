# article-to-lark

A Claude Code **skill** that turns any public web article into a well-formatted Feishu (Lark) document, with images placed **inline at their original positions** — and, for foreign articles, an automatic Chinese translation that keeps English technical terms intact.

> 一键把网页文章转成飞书文档。图片保持原位，外文自动翻译，免去复制粘贴和调格式的苦力活。

---

## What it does

Given only an article URL, the skill will:

1. **Fetch** the article's full markdown (via Jina Reader).
2. **Extract** headings, paragraphs, callouts, code blocks, and an ordered list of images.
3. **Translate** to Chinese if the source is not already Chinese — preserving English technical terms with first-occurrence annotations (e.g. `retrieval-augmented generation（检索增强生成，RAG）`).
4. **Download** every image locally (required — most CDNs block Feishu server-side fetch).
5. **Create** an empty Feishu doc in 「我的空间」root via the raw docx API (synchronous).
6. **Interleave-upload** — appends text segments and inserts images in strict reading order so images land at their correct inline positions.
7. **Verify** block counts and print the final doc URL.

Runtime: roughly `(2N + 1) × 15s` where `N` is the image count. A 17-image article finishes in about 9 minutes, fully detached in the background.

## Example session

```
You:   把 https://medium.com/@some-author/great-article 转成飞书文档

Claude:
  [fetches article, translates, downloads 12 images, creates doc, launches
   background uploader]
  上传中 (~6min)...完成：https://your-tenant.feishu.cn/docx/<doc_id>
```

---

## Prerequisites

This skill is a thin orchestration layer — it depends on several tools being present and configured on your machine.

### 1. Claude Code (required)

The skill runs inside Claude Code. Install from https://claude.com/claude-code.

### 2. `lark-cli` (required)

All Feishu operations go through **[lark-cli](https://github.com/larksuite/cli)** — the official command-line tool for Feishu/Lark open platform. This skill was developed against `lark-cli 1.0.13` or newer; earlier versions do not support `docs +media-insert` used by the interleave uploader.

**Official repository:** https://github.com/larksuite/cli

#### Install

**macOS (Homebrew, recommended):**

```bash
brew tap larksuite/cli https://github.com/larksuite/cli
brew install lark-cli
```

**From source (any platform with Go 1.21+):**

```bash
git clone https://github.com/larksuite/cli.git
cd cli
make install       # installs to $GOPATH/bin/lark-cli
```

**Pre-built binary:**

Grab the latest release from https://github.com/larksuite/cli/releases, unzip, and put the binary somewhere on your `$PATH`.

#### Verify

```bash
lark-cli --version   # expect 1.0.13 or newer
lark-cli --help      # sanity check — lists docs/auth/drive/... subcommands
```

If `lark-cli: command not found`, check your `$PATH` — Homebrew installs to `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel); `go install` puts it under `$(go env GOPATH)/bin`.

### 3. `lark-cli` authentication (required)

`lark-cli` must be logged in as a user with permission to create Feishu docs in their personal space. First-time setup (see [lark-cli README](https://github.com/larksuite/cli#getting-started) for the full flow):

```bash
# 1. Configure app credentials (app_id + app_secret from Feishu Open Platform)
lark-cli config init

# 2. User OAuth login — opens browser, asks you to authorize the app
lark-cli auth login

# 3. Verify token works — should return your user_info JSON
lark-cli api GET /open-apis/authen/v1/user_info
```

> If your organization distributes a pre-configured `lark-cli` build, follow the internal setup doc instead — the steps above are the upstream defaults.

### 4. Companion skills (required)

The skill's `SKILL.md` cross-references two sibling skills for CLI basics and auth:

- `lark-doc`    — `lark-cli docs +update` / `+media-insert` semantics
- `lark-shared` — authentication and permission handling

These are usually distributed alongside `lark-cli`. If you already use `lark-cli` for other tasks in Claude Code, you almost certainly have them installed. Check:

```bash
ls ~/.claude/skills/lark-doc/SKILL.md
ls ~/.claude/skills/lark-shared/SKILL.md
```

If either is missing, install them before using `article-to-lark`.

### 5. `curl` and `bash` (standard)

Used for image downloads and the orchestration script. Available by default on macOS and every Linux distro.

### 6. Network access

- Article source (Medium, Substack, GitHub, etc.) must be reachable without auth for Jina Reader to fetch it.
- Feishu open API (`open.feishu.cn` or `open.larksuite.com`) must be reachable.

---

## Installation

### Option A — `git clone` into Claude's skills directory

```bash
git clone https://github.com/<your-username>/article-to-lark.git \
  ~/.claude/skills/article-to-lark
```

Claude Code auto-discovers skills under `~/.claude/skills/` at session start. Open a new Claude Code session — the skill appears as `article-to-lark` in the skill list.

### Option B — clone elsewhere and symlink

If you prefer to keep the repo somewhere else (e.g. under `~/projects/`):

```bash
git clone https://github.com/<your-username>/article-to-lark.git ~/projects/article-to-lark
ln -s ~/projects/article-to-lark ~/.claude/skills/article-to-lark
```

### Option C — one-liner installer

```bash
curl -sL https://raw.githubusercontent.com/<your-username>/article-to-lark/main/install.sh | bash
```

(See [`install.sh`](install.sh) for the script body — it's a few lines of `git clone`.)

### Verify

Start a fresh Claude Code session and ask:

> 列出所有已加载的 skills

`article-to-lark` should appear.

---

## Usage

Just tell Claude the URL and what you want. Any of these phrasings work:

| Trigger | Behavior |
|---------|----------|
| `把 <URL> 转成飞书文档` | Default workflow with auto-translate if foreign |
| `爬一下 <URL> 做成飞书文档` | Same as above |
| `<URL> 翻译成中文发到飞书` | Forces translation even if source is Chinese |
| `<URL> 原样转成飞书文档，不要翻译` | Skips translation, source-language body |

### Defaults applied silently

| Item | Default |
|------|---------|
| Storage | 「我的空间」root |
| Translation | Chinese with 保留英文 + 首次中文注释 |
| Title | Translated article title |
| Images | Download locally, upload via `+media-insert` |
| Rate-limit sleep | 15 seconds between operations |
| Tail | Adds 原文链接 callout with author and publish date |

### Overriding defaults

Tell Claude explicitly:

- `放到 <folder-name> 文件夹下`
- `直译` / `意译` / `保留双语`
- `标题就用：<your title>`
- `不要加原文链接`

See [`references/translation-style.md`](references/translation-style.md) for the full list of style overrides.

---

## Limitations

- **Feishu-only.** There is no generic equivalent for Notion, Quip, Google Docs, or Confluence in this skill.
- **No whiteboards / mind-maps / diagrams.** Images in the source article are treated as static bitmaps. If you want them redrawn as editable Feishu whiteboards, that's a separate workflow (see the `lark-whiteboard` skill).
- **No video / audio embedding.** Only images are uploaded. Video links in the source become text links.
- **Tables in markdown.** If the source article uses markdown tables (`| a | b |`), they'll render in the Feishu doc via Lark-flavored markdown support. Complex or merged-cell tables may lose fidelity.
- **Long articles.** A 50-image article takes ~25 minutes to upload. The skill handles this by detaching the upload script, but the user needs to wait.
- **Articles behind auth.** If Medium / Substack paywalls the content, Jina Reader usually returns the preview only. Not fixable without logged-in scraping (out of scope).

---

## Troubleshooting

### "图片位置错乱" — images cluster at section end

You (or an earlier run) appended all text first, then media-inserted all images. Because `+media-insert` always appends to the document END, that produces clustered-at-tail output.

**Fix:** Delete the doc and re-run. The skill's interleave strategy is the only way to place images correctly — and once image blocks exist, their `file_token` cannot be moved (Feishu API limitation, error `1770013`).

### "invalid param" on block create (`1770001`)

You tried to create an image block with a `file_token` from a previously-uploaded image. `file_token`s are bound to their original block. **Fix:** rebuild with `+media-insert --file <local-path>`.

### Upload script dies partway

Confirm you used `nohup bash upload.sh > upload.log 2>&1 & disown`. If you used `&` alone, the SIGHUP from the parent shell can propagate and kill children. The skill's template uses `nohup` — don't edit that line out.

### 429 Too Many Requests

Rate limit hit. The skill uses `sleep 15` between calls, which has been stable in practice, but if your tenant has stricter limits, bump the sleep to 20 or 25.

### Images download as HTML error pages

The CDN blocked your User-Agent. The skill's `curl` step can be retried with:

```bash
curl -sL -H "User-Agent: Mozilla/5.0" -H "Referer: <article-url>" -o imgs/imgXX.png "<url>"
```

### `lark-cli: command not found`

`lark-cli` isn't installed or not on PATH. See [Prerequisites #2](#2-lark-cli-required).

### `docs +create --markdown` returning task_id stuck

Don't use that path. This skill uses the synchronous raw API (`POST /open-apis/docx/v1/documents`) specifically because the async `docs +create --markdown` cannot be polled via `lark-cli`.

---

## How it works internally

```
┌──────────────┐   fetch (Jina)    ┌──────────────┐
│  Article URL │ ───────────────▶ │   Markdown   │
└──────────────┘                  └──────┬───────┘
                                         │ analyze
                                         ▼
                       ┌─────────────────────────────────┐
                       │  N image URLs + N+1 text segs   │
                       └─────────┬───────────────┬───────┘
                                 │ curl          │ translate
                                 ▼               ▼
                     ┌──────────────┐   ┌─────────────────┐
                     │ imgs/*.png   │   │ segs/seg*.md    │
                     └──────┬───────┘   └────────┬────────┘
                            │                    │
                            │   create empty doc │
                            │   (raw API)        │
                            ▼                    ▼
                       ┌────────────────────────────────┐
                       │ upload.sh (detached, nohup)    │
                       │                                │
                       │ for i=1..N:                    │
                       │   append seg_i.md              │
                       │   sleep 15                     │
                       │   +media-insert imgs/img_i.png │
                       │   sleep 13                     │
                       │ append seg_{N+1}.md            │
                       └──────────────┬─────────────────┘
                                      │
                                      ▼
                              ┌─────────────────┐
                              │ Feishu docx URL │
                              └─────────────────┘
```

The **interleave is not optional** — it exists because:

- `+media-insert` appends to doc END (no position flag)
- External image URLs in markdown don't download server-side
- Once uploaded, image `file_token`s cannot be re-associated with new blocks

These three constraints force the exact shape of the workflow. See [`references/gotchas.md`](references/gotchas.md) for the detailed evidence.

---

## Repository layout

```
article-to-lark/
├── README.md                         ← you are here
├── LICENSE
├── SKILL.md                          ← skill entry point (loaded by Claude)
├── install.sh                        ← one-liner installer
└── references/
    ├── gotchas.md                    ← 10 pitfalls with error codes
    ├── interleave-strategy.md        ← segment boundary rules + validation
    └── translation-style.md          ← Chinese translation conventions
```

---

## Contributing

Issues and PRs welcome. Especially:

- Support for non-English/non-Chinese source articles
- Alternate CDN User-Agent handling for common blocked sources
- Table fidelity improvements
- Test fixture articles with tricky structures (nested callouts, code-heavy pages)

When filing an issue, include:

- Source article URL
- Number of images detected
- Error code if the upload failed
- Last 30 lines of `upload.log`

---

## License

MIT — see [LICENSE](LICENSE).

---

## Acknowledgements

- Built on top of [`lark-cli`](https://github.com/larksuite/cli) and Feishu Open Platform docx API.
- Article fetching powered by [Jina Reader](https://jina.ai/reader).
- Developed as a [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills).
