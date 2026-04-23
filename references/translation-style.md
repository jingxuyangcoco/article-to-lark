# Translation style

Default style when source article is not Chinese: **中文正文 + 保留英文技术术语 + 首次中文注释 + 末尾原文链接 callout**.

## Terminology rules

### 首次出现：英文 + 中文注释

```
retrieval-augmented generation（检索增强生成，RAG）
embedding model（嵌入模型）
cross-encoder（交叉编码器）
knowledge graph（知识图谱）
```

Pattern: `English term（中文翻译，可选简写）` or when already has widely-known abbreviation: `English term（中文翻译，ABBR）`.

### 后续出现：用简写或英文

If the term has an abbreviation (RAG, LLM, KG, API), prefer that from the 2nd occurrence.  
If no abbreviation exists, keep using the English term without re-annotating.

### 保留不译的内容

| Category | Examples |
|----------|----------|
| Proper nouns | Anthropic, LangChain, Microsoft Research, Meta AI, Google DeepMind |
| Product / library names | GraphRAG, LangGraph, LangChain, Pinecone, Weaviate, FAISS |
| Technical terms w/o standard Chinese | embedding, reranker, top-k, cosine similarity, tokenizer |
| Metric / framework names | RAGAS, BLEU, ROUGE, ReAct, CRITIC, Self-RAG |
| Code identifiers, CLI flags, config keys | `--chunk-size`, `top_k`, `temperature` |

### 一定翻译的内容

- Section headings (`## Decision Framework` → `## 决策框架`)
- Body prose
- Bullet list item prefixes when they set context (`**Pro tip:**` → `**实用建议：**`)
- Callout emoji + body

## Structure preservation

| Source element | Preserve as |
|---------------|-------------|
| `##` heading | `##` heading (translated text) |
| `###` heading | `###` heading |
| `>` blockquote | `>` blockquote |
| `---` separator | `---` separator |
| Code fences ` ``` ` | Keep verbatim, DO NOT translate code |
| Inline code `` `foo` `` | Keep verbatim |
| Lists (`-`, `1.`) | Same list structure |
| Bold `**x**` | Bold translated text `**译文**` |
| Italic `*x*` | Italic (use sparingly, Chinese italic looks ugly) |

## Lark-flavored tags

Convert any HTML-ish quote/info boxes in the source to Feishu callouts:

```markdown
<callout emoji="💡" background-color="light-blue">

**学习要点：**

- 要点 1
- 要点 2

</callout>
```

Common emoji / color pairings:
- 💡 + `light-blue` — insight / learning point
- ⚠️ + `light-yellow` — warning / pitfall
- ⚡ + `light-yellow` — quick tip / heuristic
- ⚙️ + `pale-gray` — technical detail / process
- 🔗 + `pale-gray` — reference / link
- ✅ + `light-green` — recommended approach
- ❌ + `light-red` — anti-pattern

## Required tail callout

The LAST segment (`seg(N+1).md`) must end with:

```markdown
---

<callout emoji="🔗" background-color="pale-gray">

**原文链接：** [Original Article Title](https://original-url)

**作者：** Author Name · 发表于 YYYY-MM-DD · 约 N 分钟阅读
</callout>
```

Fill in title, URL, author, publish date, and read time from the source.

## Title translation

- Keep punchy — Chinese title should be readable in < 2 seconds
- Preserve key English terms: `Pipeline RAG vs Agentic RAG vs Knowledge Graph RAG：到底哪种真正有效，什么时候用`
- Colon separator `：` (full-width) not `:` (half-width)
- No emoji in title

## Tone

- Default register: technical blog post, second person singular («你»)
- Avoid 您 (too formal) unless source is clearly corporate / formal
- Keep the author's voice — if source uses contractions and humor, translate that energy
- Acronyms and bracketed asides translate naturally: `(aka Agent)` → `（即 Agent）`

## Alternative styles — when user overrides

| User says | Behavior |
|----------|----------|
| "直译" | Literal, word-for-word; do NOT preserve English terms inline |
| "意译" | Loose, may reorder sentences and merge / split paragraphs for flow |
| "保留双语" | Each paragraph in English then Chinese (double length) |
| "不加原文链接" | Skip the 原文链接 tail callout |
| "标题直译" | Translate title literally instead of punchy rephrase |

## Validation

Before handing segments to upload:
- [ ] All headings translated
- [ ] All proper nouns preserved in English
- [ ] First occurrence of technical term has `（中文）` annotation
- [ ] Code blocks unchanged
- [ ] Tail 原文链接 callout present in last seg
- [ ] Callouts fully translated (no mixed English/Chinese body)
