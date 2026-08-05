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

日本語の README は [**README.ja.md**](README.ja.md)、制度データの追加手順は
[**docs/ADDING_PROGRAMS.ja.md**](docs/ADDING_PROGRAMS.ja.md) にあります。

## What's in this gem (the open core)

- Data models for programs (制度) and requirements (要件), with the exact 要綱 excerpt kept
  alongside each machine-readable condition.
- Chunking, embedding, and pgvector search of 要綱 text — used **for evidence**, never to gate
  which programs get assessed.
- The `Assessor`: applicability filter → rule check → grounded LLM judgement → aggregation,
  with fail-safe defaults (ambiguity → 要確認, never a loose 該当).
- `Geo`: free-text residence → JIS codes, 政令指定都市 ward ↔ parent-city hierarchy, and the
  anti-omission rule — only status / date window / geography may exclude a program, and a
  residence that can't be normalized passes through capped at 要確認 rather than being dropped.
- Swappable **LLM** and **embedding** adapters (Anthropic / OpenAI-compatible / local /
  null-for-test).
- An ingestion port (`Ingestion::ManualYamlAdapter` → `Importer`) plus **five real,
  official-source seed programs** (12 requirements, each quoting its 要綱 verbatim).
- A `Result` value object and an optional mountable JSON API.

Auth, billing, and commercial UI live in a separate host ("shell") app — not here.
[**kyufy-web**](https://github.com/kyufy-jp/kyufy-web) is the open reference host: the smallest
complete example of mounting this engine (intake → assess → cited verdict cards, one controller
and one screen).

## Installation

The gem is not on RubyGems yet — install from git:

```ruby
# Gemfile
gem "kyufy_core", github: "kyufy-jp/kyufy_core"
```

```bash
bin/rails kyufy_core:install:migrations
bin/rails db:migrate
```

Mount the (optional) JSON API in the host app's routes:

```ruby
# config/routes.rb
mount KyufyCore::Engine => "/kyufy_core"
```

Then load the packaged real-program seed (see [Seed data](#seed-data)):

```ruby
KyufyCore.import_dir   # db/seeds/programs/*.yml -> Program / Requirement / SourceDocument
```

Requires PostgreSQL with the [pgvector](https://github.com/pgvector/pgvector) extension; the
migration creates a `vector(1536)` column, so change it together with `config.embedding_dim` if
your embedding model has a different dimension.

## Try it with no Ruby installed (Docker)

If your app isn't Ruby — or you just want to see what an assessment looks like — talk to the
engine over HTTP instead of mounting it. `docker compose up` brings up PostgreSQL + pgvector and
the [JSON API](#json-api-optional-mount), migrated and seeded with the five real programs. Nothing
is installed on your machine.

```bash
docker compose up --build   # first run builds the image and imports the seed (~1 min)
```

```bash
curl -s localhost:3100/kyufy_core/assessments \
  -H 'content-type: application/json' \
  -d '{"profile":{"age":42,"residence":"杉並区","household_size":3,
       "prior_year_income_jpy":900000,"target":"individual"}}'
```

All five programs come back assessed — national, 東京都, and 杉並区 alike — because only status /
date window / geography may exclude one (§0). For the profile above, three are 要確認: the engine
declines to guess rather than returning a loose 該当.

- **Port 3100, not 3000.** `rails server` binds `127.0.0.1:3000` while Docker binds `0.0.0.0:3000`,
  so both can hold port 3000 at once and `localhost:3000` would silently reach your other app.
  Override with `KYUFY_PORT` (and `KYUFY_DB_PORT`, default 5433, to reach the database directly).
- **No API keys, no network.** The demo runs the Null adapters, so embeddings are deterministic and
  explanations are template prose. Verdicts, citations, and source URLs are rule-derived and are
  identical with or without a model (§6) — the LLM only writes the explanation sentence.
  For real prose: `KYUFY_LLM=anthropic KYUFY_ANTHROPIC_API_KEY=sk-… docker compose up`.
- **Reset:** `docker compose down -v`. Re-importing into a warm database would duplicate programs,
  so the entrypoint seeds only when the database is empty.
- This is a **development** configuration — it boots the in-repo dummy host app (`test/dummy`) with
  no auth and no TLS. Don't expose it publicly; see
  [kyufy-web](https://github.com/kyufy-jp/kyufy-web) for a real host app.

## Reusing this without adopting the gem

Two parts of this repo are useful on their own, and neither requires Ruby:

- **[`data/`](data/README.md)** — the JIS geography tables and the five seed programs as plain
  JSON, with the schema documented. Generated from `KyufyCore::Geo` and `db/seeds/programs/*.yml`,
  with a test that fails if they drift, so the export matches what the engine assesses with.
  Regenerate with `bundle exec rake data:export`.
- **[`docs/INVARIANTS.md`](docs/INVARIANTS.md)** — the eleven rules this engine holds (anti-omission,
  retrieval-is-evidence-only, no-citation-no-該当, deterministic verdicts, …), each with why it
  exists and where it's enforced. If you're building an eligibility assessor in another language,
  this is the part worth copying; the code isn't.

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
  categories: %w[給付金 手当 控除],     # optional; 給付金 補助金 助成金 手当 控除
  plain_language: false                 # true → explanations in やさしい日本語 (easy Japanese)
)

result.each do |program_result|
  program_result.program_id     # "prog_…" — a prefixed id, never a raw PK
  program_result.program_name   # 制度名
  program_result.verdict        # :eligible / :ineligible / :needs_review
  program_result.reasons        # [{ requirement_id:, kind:, verdict:, explanation:, citation:,
                                #    citation_status:, source_url:, license:, follow_up: }]
                                # citation_status = :present / :unavailable — no citation degrades
                                #   the requirement to 要確認 (fail-safe), source_url still carries
                                #   the official URL
                                # kind = income / age / residence / household / employment / other
                                #   (Requirement.kind_label gives the Japanese 所得 / 年齢 / …)
                                # follow_up = a 逆質問 to resolve a 要確認 when a directly-answerable
                                #   Profile field (e.g. resident_tax_exempt) is unset; else nil
  program_result.disclaimer
end

result.as_json   # array of per-program hashes with string keys; the JSON API wraps it in
                 # { "assessments" => [...] }
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
# => a single KyufyCore::Result; income summed, household_size = member count,
#    resident_tax_exempt taken from the household (it is a 世帯-level status).
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
POST /kyufy_core/assessments            # { profile: {...} }  -> { assessments: [...] }
POST /kyufy_core/assessments/batch      # { profiles: [...] } -> { results: [{ assessments: [...] }, …] }
POST /kyufy_core/assessments/household  # { members: [...] }  -> { assessments: [...] }
```

Each accepts optional `categories` and `plain_language: true` (やさしい日本語 explanations), and
returns the JSON mirror of the Ruby result — prefixed IDs only. Only the seven Profile fields are
permitted; anything else is dropped. This gem holds no auth; the host app provides it — see
[kyufy-web](https://github.com/kyufy-jp/kyufy-web) for a working mount.

## Seed data

`db/seeds/programs/*.yml` holds **five real programs / 12 requirements** — one 国 (厚生労働省),
three 東京都, one 杉並区, enough to exercise national / prefecture / municipality scoping in a
single assessment. Every requirement quotes its 要綱 verbatim and links a live official page, and
the source's license (e.g. `PDL1.0`) travels through to each reason.

```ruby
KyufyCore.import_dir                       # every *.yml in db/seeds/programs (the real set)
KyufyCore.import_yaml(path)                # one YAML file
KyufyCore.import_yaml(KyufyCore.seed_path) # db/seeds/tokyo_programs.yml — ILLUSTRATIVE fixture
                                           # for the engine's own tests, not real 要綱 text
```

Importing always `create!`s, so re-running duplicates programs — clear the tables first (or import
into a fresh database).

Five programs is a starting kit, not a dataset — the engine is designed to have programs added.
[**docs/ADDING_PROGRAMS.ja.md**](docs/ADDING_PROGRAMS.ja.md) (Japanese) walks through the YAML
format field by field, the `value` shapes per operator, the verbatim-citation rule, and how to
extend the JIS municipality table for a city the packaged `Geo` table doesn't carry.

The same five programs are exported to [`data/programs.json`](data/README.md#programsjson) for
readers outside Ruby, along with the field-by-field schema, the `value` shapes per operator, and
the provenance conventions — why `raw_text` must stay verbatim and why `license: null` means
*unknown*, not *free*.

## Configuration

```ruby
KyufyCore.configure do |c|
  c.llm_adapter       = MyLLMAdapter.new         # default: KyufyCore::LLM::NullAdapter
  c.embedding_adapter = MyEmbeddingAdapter.new   # default: KyufyCore::Embedding::NullAdapter
  c.embedding_dim     = 1536                      # must match the migration
  c.extra_municipalities = { "三鷹市" => "13204" } # JIS codes the packaged Geo table lacks
end
```

`extra_municipalities` matters as soon as you add a program outside the packaged table (東京23区 +
さいたま市): without it, every resident of that municipality fails to normalize and the
anti-omission rule caps their whole assessment at 要確認. Codes are Strings — leading zeros are
significant, so a numeric or wrong-length code raises `ArgumentError` at assignment rather than
degrading silently. Entries win over the packaged ones, and the packaged constant (and
`data/geo.json`) is left untouched.

Tests run entirely on the two Null adapters — deterministic, free, and zero network calls.

### LLM adapters

The LLM only writes grounded explanations; verdicts always come from the rules, and any API
failure degrades to a generic explanation rather than breaking an assessment. Two real adapters
ship:

```ruby
# Anthropic (Claude). Reads ENV["KYUFY_ANTHROPIC_API_KEY"] — a DEDICATED key, separate from
# ANTHROPIC_API_KEY. Model is configurable via `model:` or ENV["KYUFY_ANTHROPIC_MODEL"]
# (default claude-haiku-4-5; e.g. claude-opus-4-8 for higher-quality explanations).
# Requires the `anthropic` gem (loaded lazily).
c.llm_adapter = KyufyCore::LLM::AnthropicAdapter.new

# OpenAI-compatible (OpenCode / OpenAI / local). Config via ENV: KYUFY_OPENAI_API_KEY,
# KYUFY_OPENAI_BASE_URL (default https://api.openai.com/v1), KYUFY_OPENAI_MODEL (default
# gpt-4o-mini). Any /chat/completions endpoint works — point base_url + model at it, no code
# change. No SDK dependency (Net::HTTP).
c.llm_adapter = KyufyCore::LLM::OpenAICompatibleAdapter.new
```

Keys live in the environment only — never in the repo. The Anthropic live smoke test
(`test/kyufy_core/llm/anthropic_live_smoke_test.rb`) is gated on `KYUFY_ANTHROPIC_API_KEY` and
skips cleanly when it's absent.

### Embedding adapters

Semantic retrieval of 要綱 chunks (§6 evidence lookup) needs real vector embeddings:

```ruby
# OpenAI-compatible (OpenCode / OpenAI / local). Config via ENV: KYUFY_OPENAI_API_KEY,
# KYUFY_OPENAI_BASE_URL, KYUFY_OPENAI_EMBEDDING_MODEL (default text-embedding-3-small). The
# returned dimension is validated against `embedding_dim` (and the vector() column width), so a
# model/column mismatch fails loudly. No SDK dependency (Net::HTTP).
c.embedding_adapter = KyufyCore::Embedding::OpenAICompatibleAdapter.new
```

Note: Anthropic has no embeddings API, so embeddings run through an OpenAI-compatible endpoint.
Moving to a different provider or gateway is one config swap for **both** the LLM and embedding
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
distance to the query exceeds the threshold, so a weak match becomes `citation_status: :unavailable`
(→ 要確認) rather than a misleading citation — the relevance-rating step from 源内's
`kb_retrieve_and_rating`. Set e.g. `0.5` with a real embedding model.

## Requirements

- Ruby ≥ 3.2 (developed on 4.0.6), Rails ≥ 8.1 (developed on 8.1.3)
- PostgreSQL with the [pgvector](https://github.com/pgvector/pgvector) extension

## Development

```bash
bundle install                        # installs into ./vendor/bundle
RAILS_ENV=test bin/rails db:migrate   # engine migrations run against the bundled test/dummy app
bin/rails test                        # full suite on the two Null adapters (no network, no keys)
bundle exec rubocop -a                # rails-omakase style
```

The dummy app's schema format is `:sql` (`test/dummy/db/structure.sql`) because pgvector's
`vector()` column and its HNSW index don't round-trip through Ruby `schema.rb`. Three live smoke
tests skip unless the matching key is in the environment — real Claude
(`KYUFY_ANTHROPIC_API_KEY`), real embeddings (`KYUFY_OPENAI_API_KEY`), and
`retrieval_grounding_live_smoke_test.rb`, which needs both and is the one path that runs real
retrieval and real grounding together.

## Log hygiene note for host apps

The engine ships `config/initializers/filter_parameters.rb`, which appends five Profile fields
(`residence`, `prior_year_income_jpy`, `age`, `household_size`, `employment`) to the host app's
`config.filter_parameters` so a profile POST never lands verbatim in request logs. This mutates
the host's **global** filter list, so generic keys like `age` / `employment` will also mask the
host's unrelated params of the same name. Over-filtering is the safe direction for this domain,
so it's intentional — but hosts should be aware.

`target` and `resident_tax_exempt` are not on that list; a host that logs params and cares about
住民税非課税 status should add `resident_tax_exempt` to its own `filter_parameters`.

## References

- [kyufy-web](https://github.com/kyufy-jp/kyufy-web) — the open reference host app (Rails 8.1,
  Hotwire): a single 壁打ち chat screen that mounts this engine and renders cited verdict cards.
  The smallest complete example of using `kyufy_core`.
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

[MIT](MIT-LICENSE) — Copyright (c) 2026 Daisuke Adachi. This gem contains no Jumpstart Pro code
(paid, non-redistributable) and no Tailwind Plus code (this gem is UI-free by design).
