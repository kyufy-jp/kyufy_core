# Changelog

All notable changes to kyufy_core are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-21

First tagged release. The assessment engine, JSON API, pgvector retrieval, swappable LLM/embedding
adapters, and five verbatim-cited real seed programs.

### Added
- **住民税非課税世帯 status (Phase 1: ask, don't compute)**: a `resident_tax_exempt` Profile field
  (true/false/nil) that the user answers directly. A `kind: income` requirement with
  `value: { measure: "住民税非課税" }` now returns a real verdict — `true` → 該当; `false`/`nil` →
  要確認 (never 非該当, since such requirements usually carry OR alternatives like 児童扶養手当受給).
  When unset, the reason surfaces a **逆質問** (`follow_up`): "住民税は非課税ですか?（お住まいの通知書で
  確認できます）", from `KyufyCore::FOLLOW_UP_QUESTIONS`. This takes 杉並区's income requirement from
  要確認 to a real verdict. Computing 非課税 from 世帯合算所得 vs. the 限度額 table is deliberately
  deferred (級地/composition variance would risk a loose 該当 on a means-tested benefit).
- **License threading (attribution travels with the data)**: `SourceDocument` gains a nullable
  `license` column; it flows `NormalizedDocument.license` → Importer → `SourceDocument` → each
  Result reason (`{…, source_url, license}`) and the JSON API. The reason's license is read from
  the *cited* `requirement.source_document`, so synthesized/carve-out reasons carry `license: nil`.
  Seed licenses were captured per official page (教育訓練 = PDL1.0; the 東京都/杉並区 pages reserve
  rights → nil).
- **Real program seed data** (`db/seeds/programs/*.yml`, loaded via `KyufyCore.import_dir`): five
  programs sourced verbatim from official pages — 018サポート, 子育て応援＋, 杉並区エアコン購入費助成,
  一般教育訓練給付金, and 東京ゼロエミポイント (家庭のゼロエミッション行動推進事業; a 都民-scoped 省エネ家電
  買替え subsidy whose 購入店舗/買替え/設置場所 conditions can't be checked from a Profile → honest
  要確認). Every `raw_text` is a quote from the official source (see the PR for the verification
  checklist). The fictional `tokyo_programs.yml` remains the test fixture.
- **Fully-local model support (privacy)**: the OpenAI-compatible adapters run against a local
  server (Ollama / vLLM / LM Studio) with no code change, keeping PII (所得 / 世帯 / residence)
  on-premises — the same approach as [open-genai](https://github.com/hirokawaguchi/open-genai).
  The embedding adapter's `dimensions` request param is now optional (`request_dimensions: false`)
  for local-server portability.
- **Evidence relevance gate**: `config.evidence_max_distance` drops pgvector fallback chunks whose
  cosine distance exceeds the threshold, so a weak match degrades to `citation_unavailable` rather
  than a misleading citation — the relevance-rating step from 源内's `kb_retrieve_and_rating`.
- **世帯 (household) assessment**: a `Household` value object (members sharing one residence) and
  `KyufyCore.assess_household(household: {...})` / `POST /assessments/household` assess a household
  as a unit — income is summed across members (世帯合算所得) and `household_size` is the member
  count, which is how most Japanese 給付金 gate eligibility. Members must share a residence (the
  "different residence" mistake is now an explicit error). Per-member attributes (age, employment)
  aren't household facts, so they resolve to 要確認; per-member eligibility stays with `assess_batch`.
- **Batch assessment**: `KyufyCore.assess_batch(profiles: [...])` and a `POST /assessments/batch`
  endpoint assess several profiles (e.g. each household member for individual benefits, or a bulk
  backend job) in one call, returning one result set per profile in input order.
- **やさしい日本語 (easy-Japanese) toggle**: `KyufyCore.assess(..., plain_language: true)` (and a
  `plain_language` JSON API param) writes explanations in plain Japanese for users who find 要綱
  wording hard to read. Threaded through the LLM adapter contract; verdicts are unaffected.
- Mountable Rails Engine scaffold (`KyufyCore`) targeting Rails 8.1 / Ruby 4.0, with a
  `test/dummy` host app that demos the engine standalone.
- pgvector migration: `Program` / `Requirement` / `SourceDocument` / `DocumentChunk` tables,
  a `vector(EMBEDDING_DIM)` column (default 1536) with an HNSW index, and reserved
  `parent_id` / `logic` columns for a future condition tree.
- Prefixed external identifiers (`prog_` / `req_` / `doc_`) via `prefixed_ids`; `DocumentChunk`
  is internal and has none. JSON/API output and `Result` objects expose prefixed IDs only.
- `Geo`: residence → JIS X 0401/0402 normalization, designated-city ward → parent-city
  matching (東京23区 correctly parentless), and match / ancestor / none applicability.
- Ingestion port (`Source`, `NormalizedProgram` / `NormalizedRequirement` / `NormalizedDocument`,
  `Importer`) plus a `ManualYamlAdapter` for seeding.
- `Assessor` (§6): step-0 applicability filter (status / date window / geography with the
  normalization-failure and ancestor-residence carve-outs), rule-check of all applicable
  programs, evidence retrieval, batched-per-program LLM grounding, aggregation precedence
  (非該当 > 要確認 > 該当), the carve-out verdict cap, and citation-unavailable degradation.
- `Profile` and `Result` value objects, `KyufyCore.assess`, an optional mountable JSON API
  (`POST /assessments`), and a `filter_parameters` initializer for log hygiene.
- Deterministic, no-network Null adapters for both LLM and embeddings (the test default).
- `LLM::AnthropicAdapter` (Claude Messages API) and `LLM::OpenAICompatibleAdapter`
  (`/chat/completions`, the OpenCode config-swap path) — grounded explanations only; verdicts
  stay rule-driven and any API failure degrades to a generic explanation. Credentials come from
  the environment only.
- `Embedding::OpenAICompatibleAdapter` (`/embeddings`) — real vector embeddings for pgvector
  retrieval, batched per request, with the returned dimension validated against `embedding_dim`.
  Completes the swappable-adapter layer: the OpenCode swap covers both LLM and embeddings.
- Seed data: five Tokyo-sourced / national / Saitama programs spanning
  給付金・助成金・控除, producing the full 該当 / 非該当 / 要確認 spread for the demo profile.
- minitest suite covering geo, rule evaluation, aggregation precedence, the carve-out cap
  (including the no-residence-row case), citation degradation, the no-raw-PK guarantee,
  pgvector retrieval, ingestion, the JSON API, and mocked LLM-adapter contracts. The Anthropic
  live smoke test is gated on `KYUFY_ANTHROPIC_API_KEY` and skips cleanly without it.
- **Live retrieval + grounding smoke test**: a single end-to-end test that runs BOTH real adapters
  through `assess()` (real embeddings + real Claude), proving a `raw_text`-less requirement is cited
  from a real pgvector-retrieved chunk. Gated on both `KYUFY_OPENAI_API_KEY` and
  `KYUFY_ANTHROPIC_API_KEY`; skips cleanly when either is absent.

### Changed
- **Residence requirements are decided by the geographic admission, not RuleCheck.** A residence
  requirement on a program the step-0 filter admitted by a full `:match` now resolves to 該当 (the
  profile's residence is confirmed in the program's scope), keeping its citation — instead of
  degrading to 要確認 because the flat Profile can't re-verify it. `:ancestor` / normalization-failure
  admissions stay 要確認 (the carve-out cap). The synthesized `residence_unverified` reason is now
  added only when a carve-out program has no residence requirement of its own (no duplicate). This
  fixes clearly-eligible residents (e.g. a Tokyo child on 018サポート) showing 要確認.
- **Default LLM model is now `claude-haiku-4-5`** (was `claude-opus-4-8`). `AnthropicAdapter` grounds
  explanation prose only — verdicts and verbatim citations come from the rules and retrieved 要綱
  text — so Haiku's lower cost is the right default. The model is tunable without code changes via
  a new `KYUFY_ANTHROPIC_MODEL` env var (mirroring the OpenAI adapter's `KYUFY_OPENAI_MODEL`); an
  explicit `model:` kwarg still wins.
- **pgvector citation back-fill queries a meaningful Japanese phrase per requirement kind**, not the
  bare English kind label (`"income"`, `"age"`). The old query embedded poorly against Japanese 要綱
  chunks; under a real `evidence_max_distance` an off-topic nearest chunk would be dropped and a
  citable requirement would silently degrade to 要確認. Unknown kinds fall back to the label.

### Fixed
- **Invalid `POST /assessments/household` input returns 422 JSON, not a 500 HTML page.** An empty
  `members` list, or members that resolve to different municipalities, raised `KyufyCore::Error` out
  of the controller. It's now rescued at the API base controller and rendered as a
  `:unprocessable_content` JSON body `{ "error": … }`, covering every engine endpoint.
- **一般教育訓練給付金 no longer over-claims 該当 for an employee.** The 要綱 requires 雇用保険被保険者
  status AND 被保険者期間3年以上（初回1年以上）; the insured period isn't a Profile field, so an employee
  now caps at 要確認 (with a 逆質問, `KyufyCore::FOLLOW_UP_QUESTIONS[:employment_insured_period]`) and
  only the clearly-not-被保険者 `self_employed` is 非該当 — never a loose 該当 (fail-safe).
- **Gemspec URLs point at the real repo.** `homepage`, `source_code_uri`, and `changelog_uri` now
  resolve to `github.com/kyufy-jp/kyufy_core` — the org the project actually lives in (`kyufy` was
  taken) — so a published gem's links land somewhere real.

[Unreleased]: https://github.com/kyufy-jp/kyufy_core/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kyufy-jp/kyufy_core/releases/tag/v0.1.0
