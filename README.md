# kyufy_core

**kyufy-core is the open-source assessment engine** behind kyufy: it takes a user's situation
(a *profile*) and a program's requirements and returns **該当 / 非該当 / 要確認**
(*eligible / ineligible / needs-review*) with **cited evidence** — a short quoted excerpt from
the 要綱 plus the official source URL — so people don't miss the Japanese public money
(給付金・補助金・助成金・手当・控除) they're entitled to.

It is a Rails reimplementation of the structure of Digital Agency's **源内** (genai-ai-api)
administrative / legal-reference RAG, following the "answer grounded in cited source text"
pattern.

> **これは参考判定です。最終確認は各制度の公式窓口で行ってください。**
> This is a reference assessment only. Always confirm at each program's official window.

## What's in this gem (the open core)

- Data models for programs (制度) and requirements (要件), with the exact 要綱 excerpt kept
  alongside each machine-readable condition.
- Chunking, embedding, and pgvector search of 要綱 text — used **for evidence**, never to gate
  which programs get assessed.
- The `Assessor`: applicability filter → rule check → grounded LLM judgement → aggregation,
  with fail-safe defaults (ambiguity → 要確認, never a loose 該当).
- Swappable **LLM** and **embedding** adapters (OpenCode / OpenAI-compatible / local /
  null-for-test).
- A `Result` value object and an optional mountable JSON API.

Auth, billing, and commercial UI live in a separate host ("shell") app — not here.

## Usage

```ruby
result = KyufyCore.assess(
  profile: {
    age: 52,
    residence: "新宿区",              # free text; normalized to JIS codes internally
    household_size: 3,
    prior_year_income_jpy: 864_000,   # 所得 (net/taxable), prior year — NOT 収入 (gross)
    employment: "self_employed",
    target: "individual",
    resident_tax_exempt: nil       # 住民税非課税世帯? true/false/nil — answered directly, not computed
  },
  categories: %w[給付金 手当 控除],     # optional
  plain_language: false                 # true → explanations in やさしい日本語 (easy Japanese)
)

result.each do |program_result|
  program_result.program_id     # "prog_…" — a prefixed id, never a raw PK
  program_result.verdict        # :eligible / :ineligible / :needs_review
  program_result.reasons        # [{ requirement_id:, kind:, verdict:, explanation:, citation:,
                                #    source_url:, license:, follow_up: }]
                                # follow_up = a 逆質問 to resolve a 要確認 when a directly-answerable
                                # Profile field (e.g. resident_tax_exempt) is unset; else nil
  program_result.disclaimer
end
```

### 世帯 (household) assessment

Many Japanese benefits are assessed at the household level — income is summed across members
(世帯合算所得). Members share one residence (a mixed-residence household is rejected):

```ruby
result = KyufyCore.assess_household(
  household: { members: [ you, mother, father ] },  # or a bare array of members
  categories: %w[給付金 手当],
  plain_language: false
)
# => a single KyufyCore::Result; income summed, household_size = member count.
# Per-member attributes (age, employment) resolve to 要確認 — use assess_batch for those.
```

### Batch assessment (per-member / bulk)

```ruby
results = KyufyCore.assess_batch(
  profiles: [ member_a, member_b, member_c ],   # each assessed individually
  categories: %w[給付金 手当],
  plain_language: false
)
# => one KyufyCore::Result per profile, in input order
```

### JSON API (optional mount)

```
POST /kyufy_core/assessments            # single profile
POST /kyufy_core/assessments/batch      # { profiles: [ {...}, {...} ] } -> { results: [...] }
POST /kyufy_core/assessments/household  # { members: [ {...}, {...} ] } -> { assessments: [...] }
```
with a `profile` (and optional `categories`, and `plain_language: true` for やさしい日本語
explanations) returns the JSON mirror of the Ruby result — prefixed IDs only. This gem holds no
auth; the host shell provides it.

## Configuration

```ruby
KyufyCore.configure do |c|
  c.llm_adapter       = MyLLMAdapter.new         # default: KyufyCore::LLM::NullAdapter
  c.embedding_adapter = MyEmbeddingAdapter.new   # default: KyufyCore::Embedding::NullAdapter
  c.embedding_dim     = 1536                      # must match the migration
end
```

Tests run entirely on the two Null adapters — deterministic, free, and zero network calls.

### LLM adapters

The LLM only writes grounded explanations; verdicts always come from the rules, and any API
failure degrades to a generic explanation rather than breaking an assessment. Two real adapters
ship:

```ruby
# Anthropic (Claude). Reads ENV["KYUFY_ANTHROPIC_API_KEY"] — a DEDICATED key, separate from
# ANTHROPIC_API_KEY. `model:` is configurable (default claude-opus-4-8; e.g. claude-haiku-4-5
# for lower cost). Requires the `anthropic` gem (loaded lazily).
c.llm_adapter = KyufyCore::LLM::AnthropicAdapter.new

# OpenAI-compatible (OpenCode / OpenAI / local). Config via ENV: KYUFY_OPENAI_API_KEY,
# KYUFY_OPENAI_BASE_URL, KYUFY_OPENAI_MODEL. For OpenCode, point base_url + model at its
# endpoint — no code change. No SDK dependency (Net::HTTP).
c.llm_adapter = KyufyCore::LLM::OpenAICompatibleAdapter.new
```

Keys live in the environment only — never in the repo. The Anthropic live smoke test
(`test/kyufy_core/llm/anthropic_live_smoke_test.rb`) is gated on `KYUFY_ANTHROPIC_API_KEY` and
skips cleanly when it's absent.

### Embedding adapters

Semantic retrieval of 要綱 chunks (§6 evidence lookup) needs real vector embeddings:

```ruby
# OpenAI-compatible (OpenCode / OpenAI / local). Config via ENV: KYUFY_OPENAI_API_KEY,
# KYUFY_OPENAI_BASE_URL, KYUFY_OPENAI_EMBEDDING_MODEL. The returned dimension is validated
# against `embedding_dim` (and the vector() column width), so a model/column mismatch fails
# loudly. No SDK dependency (Net::HTTP).
c.embedding_adapter = KyufyCore::Embedding::OpenAICompatibleAdapter.new
```

Note: Anthropic has no embeddings API, so embeddings run through an OpenAI-compatible endpoint.
When the OpenCode key arrives it's a single config swap for **both** the LLM and embedding
adapters (base URL + key + model). The live smoke test
(`test/kyufy_core/embedding/open_ai_compatible_live_smoke_test.rb`) is gated on
`KYUFY_OPENAI_API_KEY` and skips cleanly without it.

### Fully local models (privacy)

kyufy assesses PII — 所得, 世帯, residence. Pointing the OpenAI-compatible adapters at a **local**
server (Ollama / vLLM / LM Studio) keeps that data on-premises: nothing leaves the machine. This
is the same fully-local approach as [open-genai](https://github.com/hirokawaguchi/open-genai) (a
local build of 源内), and it's a config change, not a code change:

```ruby
KyufyCore.configure do |c|
  c.llm_adapter       = KyufyCore::LLM::OpenAICompatibleAdapter.new
  c.embedding_adapter = KyufyCore::Embedding::OpenAICompatibleAdapter.new(request_dimensions: false)
  c.embedding_dim     = 1024   # e.g. mxbai-embed-large is 1024-dim, not OpenAI's 1536
end
# ENV: KYUFY_OPENAI_BASE_URL=http://localhost:11434/v1  KYUFY_OPENAI_API_KEY=ollama
#      KYUFY_OPENAI_MODEL=qwen2.5:7b   KYUFY_OPENAI_EMBEDDING_MODEL=mxbai-embed-large
```

Local embedding models have their own dimension — set `embedding_dim` (and the migration's
`vector(N)`) to match. The embedding adapter validates the returned length, so a mismatch fails
loudly. `request_dimensions: false` omits OpenAI's `dimensions` param, which local servers ignore
or reject.

### Evidence relevance gate

`config.evidence_max_distance` (default `nil` = off) drops pgvector fallback chunks whose cosine
distance to the query exceeds the threshold, so a weak match becomes `citation_unavailable`
(→ 要確認) rather than a misleading citation — the relevance-rating step from 源内's
`kb_retrieve_and_rating`. Set e.g. `0.5` with a real embedding model.

## Requirements

- Ruby ≥ 3.2 (developed on 4.0.6), Rails ≥ 8.1 (developed on 8.1.3)
- PostgreSQL with the [pgvector](https://github.com/pgvector/pgvector) extension

## Development

```bash
bin/rails db:prepare      # in test/dummy, via RAILS_ENV
bin/rails test            # full suite on the Null adapters
```

## Log hygiene note for host apps

The engine ships `config/initializers/filter_parameters.rb`, which appends the Profile fields
(`residence`, `prior_year_income_jpy`, `age`, `household_size`, `employment`) to the host app's
`config.filter_parameters` so a profile POST never lands verbatim in request logs. This mutates
the host's **global** filter list, so generic keys like `age` / `employment` will also mask the
host's unrelated params of the same name. Over-filtering is the safe direction for this domain,
so it's intentional — but hosts should be aware.

## References

- [源内 / genai-ai-api](https://github.com/digital-go-jp/genai-ai-api) — Digital Agency's
  administrative RAG (MIT), the design lineage. kyufy follows its "answer grounded in cited source
  text" pattern (query → retrieve-and-rate → answer → reference), diverging deliberately: citations
  are authoritative 要綱 excerpts curated at ingestion (not query-time retrieval), and verdicts come
  from rules, not the LLM.
- [open-genai](https://github.com/hirokawaguchi/open-genai) — a fully-local build of 源内
  (Ollama / OpenAI-compatible, MIT); the local-model deploy above mirrors its approach.
- [pgvector](https://github.com/pgvector/pgvector), [neighbor](https://github.com/ankane/neighbor),
  [prefixed_ids](https://github.com/excid3/prefixed_ids).

## License

MIT. This gem contains no Jumpstart Pro code (paid, non-redistributable) and no Tailwind Plus
code (this gem is UI-free by design).
