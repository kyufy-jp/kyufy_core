# Changelog

All notable changes to kyufy_core are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

[Unreleased]: https://github.com/dadachi/kyufy_core/commits/main
