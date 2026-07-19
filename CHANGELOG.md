# Changelog

All notable changes to kyufy_core are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
