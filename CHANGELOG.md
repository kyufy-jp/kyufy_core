# Changelog

All notable changes to kyufy_core are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Japanese onboarding docs.** The engine assesses Japanese public benefits and quotes Japanese
  要綱, but every word telling you how to use it was in English — a real barrier for the people
  most likely to build on it.
  - **`README.ja.md`** — a five-minute adoption decision. What the engine does and, more usefully,
    what it does not: no UI, no LLM-decided verdicts, and **not a program database** (the packaged
    five are a starting kit). States the stack constraint plainly — Rails + PostgreSQL + pgvector,
    so it cannot run on Cloudflare Workers alone; use the Docker JSON API from another host
    instead. Carries the licensing warning about the bundled 要綱 text (`license: null` means
    *unknown*, not *free*) up front rather than in a footnote.
  - **`docs/ADDING_PROGRAMS.ja.md`** — the guide that makes the seed a starting kit instead of a
    ceiling. Field-by-field YAML reference, `value` shapes per operator, the three `measure`
    special cases, why `raw_text` must be verbatim, and the import/verify loop (including
    `docker compose cp` for the container path, since the image copies the repo at build time).
    Documents two traps found while writing it: `kind: other` with `operator: exists` evaluates to
    **非該当**, not 要確認 (the Profile has no `other` field, and `exists` reads absence as failure)
    — use `eq`; and JIS codes written unquoted in YAML lose their leading zero.
  - Covers extending the JIS municipality table via the new `config.extra_municipalities` below.
- **`config.extra_municipalities` — add municipalities the packaged JIS table doesn't carry.**
  `Geo` ships 東京23区 + さいたま市 only (a national table belongs to ingestion), and the frozen
  constant left hosts monkey-patching it. Adding a program for 三鷹市 or 八王子市 without extending
  the table leaves every local resident's address unnormalizable, so carve-out (a) caps their whole
  assessment at 要確認 — the engine looks broken precisely where a host is most likely to start.
  ```ruby
  KyufyCore.configure { |c| c.extra_municipalities = { "三鷹市" => "13204" } }
  ```
  - **Validated at assignment, not at lookup.** A numeric or wrong-length code raises
    `ArgumentError` immediately, naming the leading-zero trap (`"01100"`, not `01100`, which Ruby
    reads as octal). The alternative is a silent normalization failure — invisible degradation is
    the failure mode this engine exists to prevent.
  - Entries win over the packaged ones, so a stale or wrong code can be corrected without a fork.
    `Geo::MUNICIPALITIES` itself is untouched, so `data/geo.json` and its drift test still describe
    the packaged data, and one host's additions can't leak into the export.
  - `Geo.municipalities` merges lazily and caches on the config hash's object identity, so
    reassignment takes effect at once and steady-state lookups allocate nothing. `geo.rb` still
    loads standalone (`data_export.rb` requires it without Rails or configuration).
- **`data/` — the reusable datasets, without Ruby.** The two things here worth having even if you
  never run the engine were locked in Ruby: `Geo`'s JIS tables (constants) and the five seed
  programs (YAML the engine's own adapter parses). Both now export to plain JSON — `data/geo.json`,
  `data/programs.json` — with `data/README.md` documenting the schema field by field, the `value`
  shapes per operator, the three `measure` special cases, and the provenance conventions (`raw_text`
  is verbatim because it's the citation; `license: null` means *unknown*, not *free*).
  - **Generated, with drift enforced.** `bundle exec rake data:export` regenerates from the
    sources, which stay authoritative; `test/kyufy_core/data_export_test.rb` fails when the
    committed files no longer match. A stale export would hand outside consumers a different
    geography or a different 要綱 excerpt than the engine uses — silently.
  - The exporter (`lib/kyufy_core/data_export.rb`) is deliberately **not** required from
    `lib/kyufy_core.rb`: nothing at runtime needs it, and the exports aren't packaged in the gem.
  - The export carries its own caveats in a `_meta` block, so they travel with a downloaded file:
    the municipality table is partial (not national), codes are strings because leading zeros are
    significant, and ambiguous bare ward names (`中央区`, `北区`) are absent on purpose.
- **`docs/INVARIANTS.md` — the eleven rules, extracted.** The transferable part of this engine
  isn't the Rails code; it's the design discipline, and it was scattered across source comments
  and `docs/SPEC.md`. Now stated once, each rule with why it exists, what it prevents, and where
  it's enforced: anti-omission, retrieval-is-evidence-only, unresolvable residence passes through,
  ambiguity → 要確認, no-citation-no-該当, verbatim citations, deterministic verdicts (the model
  writes prose only), aggregation precedence, caps as synthesized reasons, 逆質問 over "unclear",
  and the always-attached disclaimer. Written for someone reimplementing this in another language.
- **`docker compose up` runs the assessment API with nothing installed.** PostgreSQL + pgvector and
  the JSON API, migrated and seeded with the five real programs, so a team on any stack can POST a
  profile and get 該当 / 非該当 / 要確認 with cited 要綱 evidence without a Ruby toolchain — the
  practical barrier that kept this engine Ruby-only in effect. `compose.yaml`, `docker/Dockerfile`,
  `docker/entrypoint.sh`, `docker/seed.rb`, `.dockerignore`, plus a README section. Development
  configuration only: it boots the in-repo dummy host app with no auth and no TLS.
  - Defaults to the Null adapters — no credentials, no network, deterministic embeddings.
    `KYUFY_LLM=anthropic` + `KYUFY_ANTHROPIC_API_KEY` opts into real explanation prose; verdicts and
    citations are rule-derived and identical either way (§6).
  - Publishes **3100**, not 3000: `rails server` binds `127.0.0.1:3000` while Docker binds
    `0.0.0.0:3000`, so both hold the port at once and `localhost:3000` silently reaches whatever
    other Rails app is running. Override with `KYUFY_PORT` / `KYUFY_DB_PORT`.
  - Seeds only into an empty database (`KyufyCore.import_dir` always `create!`s, so a warm volume
    would duplicate every program). `docker compose down -v` to start over.
  - Two guarded hooks in the dummy app's `development.rb`, both inert unless the container sets the
    env var: skip the post-migration `structure.sql` dump (the image's `pg_dump` need not match the
    server major version) and log to stdout (`docker compose logs`). `RAILS_ENV=test` — the
    maintainer migrate/test path — never loads that file.

### Security
- **Rails 8.1.3 → 8.1.3.1**, closing GHSA-xr9x-r78c-5hrm (critical): arbitrary file read and remote
  code execution in Active Storage variant processing. This gem does not use Active Storage, but
  `rails` is a runtime dependency, so the vulnerable code was in every resolved bundle. The bump
  went unnoticed because **Dependabot alerts were disabled on the repository** — now enabled,
  together with Dependabot security updates, so the next one opens a PR instead of sitting silent.
  Lockfile bump only (`bundle update rails --conservative`); the gemspec's `>= 8.1, < 9` is
  unchanged.

### Changed
- **README matches the code, and links the reference host app.** `kyufy-web` is public now, so the
  README points at [it](https://github.com/kyufy-jp/kyufy-web) — the only app that mounts this
  engine, and the answer to "what does using this look like?". The rest is drift repair against the
  real source: an **Installation** section (git Gemfile line — the gem isn't on RubyGems —
  `kyufy_core:install:migrations`, the engine mount, `KyufyCore.import_dir`) and a **Seed data**
  section, both of which were entirely undocumented; `citation_status` and `program_name` added to
  the documented result shape (they ship, they were missing); the real JSON response shapes per
  endpoint; adapter ENV defaults (`gpt-4o-mini`, `text-embedding-3-small`); the third live smoke
  test (`retrieval_grounding_live_smoke_test.rb`); and dev commands that work
  (`RAILS_ENV=test bin/rails db:migrate`, not `bin/rails db:prepare`). Also notes that
  `resident_tax_exempt` is *not* in the engine's `filter_parameters` list, so a host that logs
  params can add it.

## [0.1.1] - 2026-07-22

### Fixed
- **Requirement kinds now read as Japanese in user-facing explanations.** `kind` is an English
  enum (`income`, `age`, …) and it was interpolated raw into otherwise-Japanese prose, so a verdict
  card rendered "要綱「…」に基づき、**income**の要件を該当と判定しました。" — visibly broken Japanese
  for the target users (§4). Both the `NullAdapter` (the offline/demo path, `KYUFY_LLM=null`) and
  `GroundedAdapter#fallback_explanation` (the degradation path when a real LLM call fails) now use
  the Japanese label: "…**所得**の要件を該当と判定しました。"

### Added
- `KyufyCore::Requirement::KIND_LABELS` and `Requirement.kind_label(kind)` — the canonical
  English-enum → Japanese-label mapping (所得 / 年齢 / 居住地 / 世帯 / 就労 / その他), declared next to
  `KINDS` so hosts and adapters share one vocabulary instead of each inventing its own.
  Unrecognized kinds fall back to the raw value rather than nil. A test asserts `KIND_LABELS`
  covers exactly `KINDS`, so adding a kind without a label fails loudly.

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
- **`MIT-LICENSE` carries a real copyright line.** The file shipped since the first commit with the
  Rails generator's placeholder, `Copyright TODO: Write your name` — a defective notice in a file
  the gemspec packages, on a repo whose whole positioning is public-good reuse. It now reads
  `Copyright (c) 2026 Daisuke Adachi`, and the README's License section links the file (SPEC §10).
  `spec.authors` follows: it read `"kyufy"` (the project name, not a person) while the license names
  a human — RubyGems would have credited an author who doesn't match the copyright holder.
- **Gemspec URLs point at the real repo.** `homepage`, `source_code_uri`, and `changelog_uri` now
  resolve to `github.com/kyufy-jp/kyufy_core` — the org the project actually lives in (`kyufy` was
  taken) — so a published gem's links land somewhere real.

[Unreleased]: https://github.com/kyufy-jp/kyufy_core/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kyufy-jp/kyufy_core/releases/tag/v0.1.0
