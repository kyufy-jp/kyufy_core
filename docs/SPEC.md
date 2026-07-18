# kyufy-core — Assessment Engine Design Spec (for Claude Code)

> Hand this document to Claude Code to start implementation. Maintainer-local details (machine paths, host inventory) are intentionally excluded; they live in `docs/LOCAL.md` (gitignored).
> Scope: **kyufy's open-source core (the assessment engine) only.** Auth, billing, and commercial UI (the private Jumpstart Pro "shell") are out of scope.
>
> **Domain-term convention:** Japanese public-benefit concepts are kept in Japanese on purpose (translating them loses legal nuance). Keep these as Japanese string literals / documented enums: 給付金 (individual benefit), 補助金 / 助成金 (business subsidy/grant), 手当 (allowance), 控除 (deduction), 世帯 (household), 所管 (administering authority), 要綱 (program guidelines/regulations), 前年所得 (prior-year income). Everything else is English.

---

## 0. Context (for the implementer)
- **Product kyufy**: assesses eligibility for Japanese public money (給付金・補助金・助成金・手当・控除) against program regulations, with cited evidence, so users don't miss what they're entitled to.
- **This gem's role**: take a user's situation (profile) + a program's requirements and return **該当 / 非該当 / 要確認 (eligible / ineligible / needs-review)** with **evidence (a short quote from the 要綱 + official source URL)**.
- **Design lineage**: reimplements, in Rails, the structure of Digital Agency "源内" (genai-ai-api: administrative RAG / legal-reference RAG). It follows the "answer grounded in cited source text" pattern.
- **Split architecture**: this gem is **published under MIT (open source)**. It contains **no Jumpstart Pro code** (paid, non-redistributable — license prohibition) and **no Tailwind Plus code** (allowed in public real-app repos like kyufy-web, but this gem is UI-free by design, so UI components don't belong here). Host apps (public kyufy-web now, private Jumpstart Pro shell later) depend on this gem.

## 1. Form factor
- **Mountable Rails Engine**, distributed as a gem. Name: `kyufy_core` (underscore — single top-level module `KyufyCore`, per RubyGems convention: underscore = word separator, hyphen = namespace nesting. We deliberately avoid `kyufy-core` / `Kyufy::Core` two-level nesting as overkill for now).
- Sibling repo naming: apps use hyphens (`kyufy-web`, `kyufy-shell`); only the gem uses an underscore.
- **Rails 8.1.3 / Ruby 4.0.6** (pin these; they match the Jumpstart Pro host).
- Ships a `test/dummy` host app so the engine runs standalone (standard engine layout).
- Requires PostgreSQL + **pgvector**.

### Conventions
- Code style follows common Rails-community conventions (as popularized by mainstream Rails SaaS templates): standard engine layout, thin controllers, concerns where they genuinely share behavior, minitest, rubocop with the community default set.
- **License guardrail (hard rule)**: this gem is public MIT. Never copy, port, or adapt code from any paid/non-redistributable codebase (commercial Rails templates, paid UI kits, etc.). Imitate conventions; write all code fresh.
- (Maintainer-local references — paths, host details — live in `docs/LOCAL.md`, which is gitignored.)

### Deployment context (informational)
- This gem needs no deployment config; host applications handle deployment. Keep the gem host-agnostic.

## 2. Scope
### In this gem (the open core)
- Data models & persistence for programs (制度) and their requirements (要件).
- Chunking, embedding, and vector search (pgvector) of 要綱 text.
- Logic that takes a profile, retrieves relevant programs, and assesses eligibility grounded in the requirements.
- LLM abstraction (swappable adapters: OpenCode / OpenAI-compatible / local).
- A result object (verdict + reason + cited evidence + source URL + confidence).
- A Ruby API (`KyufyCore.assess(...)`) and an optional mountable JSON API endpoint.

### Not in this gem (the shell = Jumpstart Pro / separate repo)
- User auth, billing, org management (Accounts & Teams).
- Commercial UI (Tailwind Plus screens).
- Production マイナ integration (Digital Auth App API) / freee integration. This gem only defines adapter interfaces; the real implementations live in the shell and are injected.

## 3. Directory layout (generate this)
```
kyufy_core/
├── kyufy_core.gemspec
├── LICENSE                      # MIT
├── README.md
├── CLAUDE.md                    # working notes for Claude Code (summary + conventions)
├── Rakefile
├── lib/
│   ├── kyufy_core.rb
│   └── kyufy_core/
│       ├── engine.rb
│       ├── version.rb
│       ├── configuration.rb     # llm adapter, embedding model, etc.
│       ├── assessor.rb          # assessment orchestration (the core)
│       ├── retriever.rb         # pgvector search for relevant programs / chunks
│       ├── result.rb            # value object for the verdict
│       ├── ingestion/
│       │   ├── source.rb        # abstract port (see §5)
│       │   ├── normalized_program.rb
│       │   └── importer.rb      # normalized → persisted models
│       └── llm/
│           ├── adapter.rb       # abstract adapter
│           ├── open_code_adapter.rb
│           └── null_adapter.rb  # test adapter (deterministic, no LLM call)
├── app/
│   ├── models/kyufy_core/
│   │   ├── application_record.rb
│   │   ├── program.rb           # 制度
│   │   ├── requirement.rb       # 要件 (machine-readable condition + source text)
│   │   ├── source_document.rb   # 要綱 source text
│   │   └── document_chunk.rb    # chunk + embedding(vector)
│   └── controllers/kyufy_core/
│       └── assessments_controller.rb   # optional JSON API
├── config/
│   └── routes.rb
├── db/
│   └── migrate/                 # models + enable pgvector
└── test/
    ├── dummy/                   # standalone host app
    └── ...                      # minitest
```

## 4. Data model (key fields)
- **Program (制度)**: `name`, `authority` (所管), `jurisdiction` (national / prefecture / municipality), `category` (enum: 給付金 / 補助金 / 助成金 / 手当 / 控除), `target` (individual / business), `official_url`, `valid_from`, `valid_until`, `status`.
- **Requirement (要件)**: `program_id`, `kind` (income / age / residence / household / employment / other), `operator` (lt / lte / gt / gte / eq / in / exists), `value` (jsonb), `raw_text` (the exact 要綱 excerpt), `source_document_id`. → Holding **both** a machine-readable condition and the original quoted text is the crux.
- **SourceDocument (要綱)**: `program_id`, `title`, `url`, `fetched_at`, `body`.
- **DocumentChunk**: `source_document_id`, `content`, `embedding vector(N)`, `position`. pgvector HNSW/ivfflat index.
- **Profile is never persisted** (avoid PII storage). It is a value object passed in at assess time.

## 5. Ingestion architecture (ports and adapters / DIP)
Municipal data varies wildly in format (PDF / HTML / CSV / catalog APIs) and wording. The design absorbs that variance at **ingestion time, once**, so the assessment side never sees it.

### Where DIP applies — and where it must not
- **Do NOT abstract the assessment side.** Assessor/Retriever depend only on the normalized Program/Requirement/SourceDocument models. If assessment logic ever branches on a municipality, the design has failed. 100 municipalities later, Assessor is unchanged.
- **DO cut an interface at the ingestion boundary.** The engine (high-level) defines the port; per-municipality messiness (low-level) implements it. Classic hexagonal / dependency inversion.

### The port (defined in this gem)
```ruby
module KyufyCore
  module Ingestion
    # Abstract source. Implementations return a normalized intermediate representation.
    class Source
      # @return [Array<NormalizedProgram>]
      # NormalizedProgram = Struct(name:, authority:, jurisdiction:, category:,
      #   target:, official_url:, requirements: [NormalizedRequirement],
      #   source_documents: [NormalizedDocument], fetched_at:)
      def fetch_programs = raise NotImplementedError
    end

    # Persists NormalizedProgram → Program / Requirement / SourceDocument (+ chunks/embeddings).
    class Importer; end
  end
end
```

### Adapters live OUTSIDE this gem
```
kyufy_core                  … Source port + Importer + normalized schema (public, MIT)
kyufy-adapters (separate)   … concrete adapters:
  ├── ManualYamlAdapter     … hand-written YAML → NormalizedProgram   ← MVP uses ONLY this
  ├── TokyoCatalogAdapter   … 都オープンデータカタログ CSV → normalized
  ├── SaitamaCityAdapter    … municipality HTML/PDF scrape → normalized
  └── LlmExtractionAdapter  … generic: LLM reads 要綱 text → drafts NormalizedProgram,
                              human reviews & confirms (源内-style doc×LLM, applied to ingestion)
```
Why outside the gem:
1. **Matches the business model**: "engine = free public good; writing/maintaining YOUR municipality's adapter = the paid service" (municipal SaaS). The Open Core split is enforced by the code structure itself — the moat (data upkeep) is architectural.
2. **MVP stays 2-day-sized**: implement only `ManualYamlAdapter` (3–5 programs as YAML). No scrapers. The port being right means later municipalities are additive.
3. **LLM belongs in adapters too**: 要綱 PDF → structured Requirement is an LLM-shaped task; one generic `LlmExtractionAdapter` (draft + human review) collapses the cost of onboarding new municipalities.

### Requirement expressiveness — leave room to grow
Real programs contain composite conditions ("A かつ B、ただし C を除く"). MVP keeps Requirement flat (`kind + operator + value`), which is sufficient for the seeded programs. **But reserve extension room now**: either a self-referencing `parent_id` + `logic` (and/or/not) column pair, or a nested jsonb structure inside `value`, so the schema can become a condition tree later without a rewrite. Note this in the migration comments; do not implement tree evaluation for MVP.

## 6. Assessment flow (the Assessor core)
Input: a `Profile` (e.g. `{ age:, residence:, household_size:, income:, employment:, target: }`), optionally filtered by category / jurisdiction.

1. **Retrieve**: narrow candidate Programs by residence & target; semantic-search 要綱 chunks via pgvector (query = a summary sentence of the Profile).
2. **Rule check (machine-readable)**: match each Program's Requirements against the Profile → first-pass met / not-met / undeterminable.
3. **LLM judge (grounding)**: for each requirement, have the LLM produce 該当/非該当/要確認 + reasoning **grounded in `raw_text`**, always attaching the quoted excerpt and `official_url`. Where a rule already decided it, LLM writes only the explanation; **the rule's verdict wins** (reduces hallucinated verdicts).
4. **Aggregate**: per-Program verdict. Any non-met requirement → 非該当; any undeterminable → **要確認 (fail safe toward needs-review)**.
5. **Return** the Result below.

### Fail-safe principles (important)
- Ambiguity or missing info → always 要確認 (needs_review). Never assert 該当 loosely.
- Every verdict must carry **a short quoted excerpt (~15 words) + `official_url`**. If no citation can be produced, do not emit the verdict.
- Output must always include a fixed disclaimer: "これは参考判定です。最終確認は各制度の公式窓口で行ってください。"

## 7. Public interface
### Ruby API
```ruby
result = KyufyCore.assess(
  profile: { age: 52, residence: "さいたま市中央区", household_size: 3,
             income: 864_000, employment: "self_employed", target: "individual" },
  categories: %w[給付金 手当 控除],   # optional
)
result.each do |program_result|
  program_result.program_name
  program_result.verdict        # :eligible / :ineligible / :needs_review
  program_result.reasons        # [{ requirement:, verdict:, explanation:, citation:, source_url: }]
  program_result.disclaimer
end
```
### JSON API (optional mount)
- `POST /kyufy_core/assessments` with a profile returns the equivalent JSON.
- This gem holds no auth (the shell handles it). The dummy app may be unauthenticated for MVP.

## 8. LLM / embedding abstraction
- `KyufyCore.configure` allows swapping `llm_adapter` and `embedding_model`.
- MVP uses the **OpenCode adapter** (hackathon perk). Tests use **NullAdapter** (no LLM call, deterministic text) → fast, free, reproducible.
- Model-agnostic by design (mirrors 源内): adapters also allow OpenAI-compatible / local models.

## 9. Testing (minitest)
- **Unit-test with NullAdapter**: verify rule evaluation, aggregation, fail-safe fallback, and the citation-required behavior without any LLM.
- Table tests for the assessment logic (each operator, boundary values, missing-info → needs_review).
- pgvector search: integration test with a small fixed dataset.
- Guarantee by test that **a verdict without a citation is never produced** (prevents unfounded answers).
- Contract-test the LLM adapter layer with a mock (no real API calls).

## 10. License / publishing
- Include **MIT LICENSE**. README states the concept and that this is a Rails reimplementation of 源内's administrative RAG, with reference links.
- Repo is public (GitHub). Two separate exclusions, for different reasons:
  - **Jumpstart Pro code: NEVER, license reason.** Paid and non-redistributable; even one copied line in this public repo is a violation. Absolute.
  - **Tailwind Plus code: not here, architecture reason.** Its license does allow public real-app repos (kyufy-web uses it publicly, with a README note). But this gem has no UI by design, so Tailwind Plus components simply don't belong in it — keeping the engine UI-free is what keeps it reusable by any shell.
- README carries the "参考判定 / confirm with the official window" disclaimer.

## 11. MVP (2-day hackathon) — minimum to run
1. Seed 3–5 programs as Program / Requirement / SourceDocument / DocumentChunk.
2. `KyufyCore.assess` takes a profile → pgvector retrieve → rule check → (OpenCode or Null) grounding → returns Result.
3. Output always contains verdict + reason + citation + official_url + disclaimer.
4. Mount the JSON API in test/dummy so it demos standalone (no Jumpstart Pro needed).
- Stretch: plain-language toggle (要綱 wording → やさしい日本語); batch assessment of multiple programs.
- Not now: billing, auth, production マイナ/freee, full program coverage, exact benefit-amount calculation.

## 12. First instruction to Claude Code (sample)
> "Following this spec, scaffold a mountable Rails Engine named `kyufy_core` on **Rails 8.1.3 / Ruby 4.0.6** (equivalent to `rails plugin new kyufy_core --mountable --full -d postgresql`). Follow mainstream Rails SaaS-template conventions for style and structure **without copying code from any paid template (this gem is public MIT)**; see docs/LOCAL.md (gitignored) for maintainer-local reference paths. Add a migration enabling pgvector, the models in §4, the ingestion port in §5, the Assessor in §6 (working with NullAdapter), the Ruby API in §7, a minimal seed (1 program + 2 requirements + 1 source document), and the unit tests in §9. Defer real LLM calls; the goal is a green assessment pipeline on NullAdapter first."

## Appendix: future extensions (same gem grows into these)
- Same Engine → standalone API service → the assessment backend for the municipal SaaS.
- MCP server → external AIs (Claude etc.) can call the assessor; a public good. Authorize via WorkOS MCP Auth in the shell.
- マイナ integration (address / identity) and freee integration (income / business data) fill the Profile via adapters injected from the shell (this gem only defines the interfaces).
- Agentic-internet readiness: source_document / fetched_at / official_url already model attribution & freshness, so the data can later be monetized via Pay-Per-Use standards — no schema change needed.
