# CLAUDE.md — working notes for kyufy_core

Mountable Rails Engine (gem) — the open-source **assessment engine** for Japanese
public-benefit eligibility. Full design is in `docs/SPEC.md` (Rev 2.3). Maintainer-local paths
are in `docs/LOCAL.md` (gitignored). This gem is **public MIT**: never copy code from any
paid/non-redistributable source (Jumpstart Pro, Tailwind Plus) — imitate conventions, write
fresh.

## Commands

```bash
bundle install
RAILS_ENV=test bin/rails db:migrate     # engine migrations are appended to the dummy app
bin/rails test                          # full suite, green on the two Null adapters
bundle exec rubocop -a                  # omakase style
```

Bundle installs into `./vendor/bundle`. Requires PostgreSQL + pgvector (extension built for the
running server). Test DB: `kyufy_core_dummy_test`. Schema format is `:sql`
(`test/dummy/db/structure.sql`) because pgvector's `vector()` column and HNSW index don't
round-trip through Ruby `schema.rb`.

## Architecture

- **AR models** (`app/models/kyufy_core/`): Program / Requirement / SourceDocument /
  DocumentChunk. Autoloaded by the engine.
- **Collaborators** (`lib/kyufy_core/`, POROs): required explicitly from `lib/kyufy_core.rb`.
  - `Geo` — residence → JIS codes, designated-city ward↔parent logic, `applies` (match /
    ancestor / none).
  - `Assessor` — the core flow (§6). `Retriever` — pgvector evidence search (never candidacy).
    `RuleCheck` — machine-readable first pass. `Profile` / `Result` — value objects.
  - `Ingestion::*` — the port: NormalizedProgram/Requirement/Document structs, `Importer`,
    `ManualYamlAdapter`. `LLM::*` / `Embedding::*` — adapters incl. deterministic Null adapters.

## Invariants (don't regress these)

- **Anti-omission**: only step 0 (status / date window / geography) may exclude a program.
  Semantic retrieval is evidence-only. Residence normalization failure and ancestor residence
  **pass through** (capped at 要確認), never drop.
- **Carve-out cap**: programs admitted via carve-out get a synthesized `residence_unverified`
  reason and are capped at 要確認 — even with no residence Requirement row.
- **Fail-safe**: ambiguity / missing info / missing citation → 要確認, never a loose 該当.
- **Rule-derived verdicts**: the LLM writes explanations, never verdicts. `Assessor#ground`
  discards every field the adapter returns except `explanation`, and `build_reason` takes the
  verdict from `RuleCheck`. This is the invariant the README's one-line summary blurred until
  2026-08-09: prose is evidence, never an input to the verdict.
- **Evidence degrades, never promotes**: `build_reason` yields either `RuleCheck`'s verdict or
  `:needs_review`, so a citation can cost a 該当 and can never produce one. `citation_for` reads
  `requirement.raw_text` first and only falls back to retrieval when it is blank — `raw_text` is
  nullable and unvalidated, so that path is reachable, and it is the ONE place where the embedding
  adapter can change a verdict (always downward). Do not let anything read retrieval before
  `raw_text`, and do not let a missing citation resolve upward.
- **Identifiers**: expose prefixed IDs only (`prog_`/`req_`/`doc_`), never raw PKs. DocumentChunk
  has none.
- **Aggregation precedence**: 非該当 > 要確認 > 該当 (AND semantics).

## Gotchas

- The `prefixed_ids` gem's DSL is `has_prefix_id :prog` (SPEC §4 says `has_prefixed_id` — that's
  the only spec/reality mismatch; the instance method is `#prefix_id`).
- Geo `parent_city_of` is data-light: keyed only on the 20 designated-city codes, so 東京23区
  (特別区) correctly resolve to no parent.
- `category` is a validated string column (Japanese literals), not an AR enum, so category
  filtering queries the Japanese values directly.
- Requirement `parent_id` + `logic` columns are **reserved** for a future condition tree — not
  evaluated in MVP.
