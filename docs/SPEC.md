# kyufy-core — Assessment Engine Design Spec (for Claude Code)

> Hand this document to Claude Code to start implementation. Maintainer-local details (machine paths, host inventory) are intentionally excluded; they live in `docs/LOCAL.md` (gitignored).
> Scope: **kyufy's open-source core (the assessment engine) only.** Auth, billing, and commercial UI (the private Jumpstart Pro "shell") are out of scope.
>
> **Domain-term convention:** Japanese public-benefit concepts are kept in Japanese on purpose (translating them loses legal nuance). Keep these as Japanese string literals / documented enums: 給付金 (individual benefit), 補助金 / 助成金 (business subsidy/grant), 手当 (allowance), 控除 (deduction), 世帯 (household), 所管 (administering authority), 要綱 (program guidelines/regulations), 所得 (net/taxable income — distinct from 収入 gross income). Everything else is English.
>
> Rev. 2.3 — amended after implementation review (retrieval recall, geographic scoping, income semantics, port contract, aggregation precedence, validity filtering, embedding testability, identifier exposure). Rev 2.1 adds: designated-city ward matching, step-0 normalization carve-out, document_ref pinned to integer index, filter_parameters tradeoff acknowledgment. Rev 2.2 adds: ancestor-residence third clause (coarse residence vs. finer program scope → 要確認, never drop), and a consistent Tokyo demo story (§7 example = 新宿区; さいたま市中央区 stays as the §9 ward fixture). Rev 2.3 adds: the carve-out verdict cap (programs admitted via carve-out are capped at 要確認 with a synthesized `residence_unverified` reason, even with no residence Requirement row).

---

## 0. Context (for the implementer)
- **Product kyufy**: assesses eligibility for Japanese public money (給付金・補助金・助成金・手当・控除) against program regulations, with cited evidence, so users don't miss what they're entitled to.
- **This gem's role**: take a user's situation (profile) + a program's requirements and return **該当 / 非該当 / 要確認 (eligible / ineligible / needs-review)** with **evidence (a short quote from the 要綱 + official source URL)**.
- **Design lineage**: reimplements, in Rails, the structure of Digital Agency "源内" (genai-ai-api: administrative RAG / legal-reference RAG). It follows the "answer grounded in cited source text" pattern.
- **Split architecture**: this gem is **published under MIT (open source)**. It contains **no Jumpstart Pro code** (paid, non-redistributable — license prohibition) and **no Tailwind Plus code** (allowed in public real-app repos like kyufy-web, but this gem is UI-free by design). Host apps (public kyufy-web now, private Jumpstart Pro shell later) depend on this gem.
- **Prime directive (anti-omission)**: for this product, *silently not assessing a program the user is entitled to* is the worst failure mode — worse than a cautious 要確認. Every design rule below that mentions "never drop / degrade instead" flows from this.

## 1. Form factor
- **Mountable Rails Engine**, distributed as a gem. Name: `kyufy_core` (underscore — single top-level module `KyufyCore`; underscore = word separator, hyphen = namespace nesting per RubyGems convention).
- Sibling repo naming: apps use hyphens (`kyufy-web`, `kyufy-shell`); only the gem uses an underscore.
- **Development targets Rails 8.1.3 / Ruby 4.0.6** — pin these in `test/dummy/Gemfile` and `.ruby-version` only. **The gemspec must NOT pin patch versions**: declare `spec.add_dependency "rails", ">= 8.1", "< 9"` (a gem pinning `= 8.1.3` becomes uninstallable the day a host bumps to 8.1.4).
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
- Chunking, embedding, and vector search (pgvector) of 要綱 text — **used for evidence lookup, not candidate filtering** (see §6).
- Logic that takes a profile, determines applicable programs, and assesses eligibility grounded in the requirements.
- LLM **and embedding** abstraction (swappable adapters: OpenCode / OpenAI-compatible / local / null-for-test).
- A result object (verdict + reasons + cited evidence + source URL). *(No `confidence` field — cut for MVP; reintroduce only with a defined computation.)*
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
│       ├── configuration.rb     # llm adapter, embedding adapter, embedding_dim, etc.
│       ├── assessor.rb          # assessment orchestration (the core)
│       ├── retriever.rb         # pgvector search for evidence chunks (NOT candidate filtering)
│       ├── result.rb            # value object for the verdict
│       ├── geo.rb               # residence normalization + jurisdiction hierarchy (see §4/§6)
│       ├── ingestion/
│       │   ├── source.rb        # abstract port (see §5)
│       │   ├── normalized_program.rb
│       │   ├── normalized_requirement.rb
│       │   ├── normalized_document.rb
│       │   └── importer.rb      # normalized → persisted models
│       ├── llm/
│       │   ├── adapter.rb       # abstract adapter
│       │   ├── open_code_adapter.rb
│       │   └── null_adapter.rb  # test adapter (deterministic, no LLM call)
│       └── embedding/
│           ├── adapter.rb       # abstract adapter
│           ├── open_code_adapter.rb
│           └── null_adapter.rb  # deterministic fake vectors (see §8)
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
│   ├── initializers/filter_parameters.rb  # add profile fields to Rails filter_parameters (see §7)
│   └── routes.rb
├── db/
│   └── migrate/                 # models + enable pgvector
└── test/
    ├── dummy/                   # standalone host app (pins Rails 8.1.3 / Ruby 4.0.6 here)
    └── ...                      # minitest
```

## 4. Data model (key fields)
- **Program (制度)**: `name`, `authority` (所管, free text), `jurisdiction` (enum: national / prefecture / municipality), **`prefecture_code`** (JIS X 0401, nullable — null for national), **`municipality_code`** (JIS X 0402, nullable — null for national/prefecture-level), `category` (enum: 給付金 / 補助金 / 助成金 / 手当 / 控除), `target` (individual / business), `official_url`, `valid_from` (nullable = open start), `valid_until` (nullable = open end), `status` (enum: active / inactive).
  - Geographic applicability semantics (implement in `geo.rb`): a resident of municipality M in prefecture P is covered by (a) all national programs, (b) prefecture programs with `prefecture_code == P`, (c) municipality programs with `municipality_code == M`. **national ⊃ prefecture ⊃ municipality all apply simultaneously.**
  - **政令指定都市 wards**: JIS X 0402 gives wards their own codes (さいたま市中央区 = 11105) distinct from the parent city (さいたま市 = 11100), so strict equality would miss city-wide programs for a ward resident — a silent omission forbidden by §0. `geo.rb` must treat ward codes as children of their designated city: matching succeeds if `municipality_code == M` **or** `municipality_code == parent_city_of(M)`. (Normalize with a ward→city table for the 20 designated cities. Seed programs are Tokyo-sourced per hackathon requirements and the primary demo Profile is a Tokyo 23-ward resident — but this rule is still needed from day one: the maintainer's own residence, さいたま市中央区, is a designated-city ward and is the pinned §9 test fixture; and any future expansion hits the 20 designated cities regardless.)
  - **Coarse residence vs. finer-scoped program (third clause)**: the two rules above handle profile-finer-than-program. The reverse — profile "さいたま市" (11100) vs. a program scoped to 中央区 (11105), or profile "東京都" vs. a 特別区-scoped program — is *undeterminable*, not a mismatch: the user may well live in that ward. Rule: **if the profile's normalized residence is an ancestor of the program's scope** (prefecture vs. a municipality in it; designated city vs. its ward), **the program passes the filter and its residence requirement resolves to 要確認** (surfaced as "this ward's/municipality's program may apply — where exactly do you live?"). Excluding it would be a silent drop of a possibly-entitled program (§0). Since the seeds are Tokyo ward programs, a user typing just "東京都" hits this immediately.
  - **東京23区 (特別区) are NOT designated-city wards**: each special ward is a full municipality in its own right (JIS 13101–13123) with **no parent city** — it sits directly under 東京都. `geo.rb` must NOT attempt parent-city normalization for 特別区; a 新宿区 resident matches 新宿区 programs directly, plus 東京都 prefecture-level programs, plus national. The ward→city table therefore covers only the 20 designated cities' wards and must exclude codes 131xx. (The primary demo Profile (§11) is a 23-ward resident, so getting this wrong breaks the main demo.)
- **Requirement (要件)**: `program_id`, `kind` (income / age / residence / household / employment / other), `operator` (lt / lte / gt / gte / eq / in / exists), `value` (jsonb), `raw_text` (the exact 要綱 excerpt), `source_document_id`. → Holding **both** a machine-readable condition and the original quoted text is the crux.
  - `kind: income` semantics are fixed: the value is **prior-year 所得 (net/taxable income) in JPY** unless the requirement's `value` jsonb explicitly overrides with `{ "measure": "収入" }`. This matches the Profile field definition in §7 — 所得 vs 収入 flips verdicts, so the default must be singular and documented.
- **SourceDocument (要綱)**: `program_id`, `title`, `url`, `fetched_at`, `body`.
- **DocumentChunk**: `source_document_id`, `content`, `embedding vector(EMBEDDING_DIM)`, `position`. pgvector **HNSW** index (pick HNSW, not ivfflat; at MVP scale of 3–5 programs the index is optional — create it anyway in the migration, it costs nothing).
  - **`EMBEDDING_DIM` is set once at install time** via `KyufyCore.configure` + the migration (default: 1536). Different embedding models have different dimensions; changing it later means a migration + re-embedding everything. Say so in the migration comment.
- **Profile is never persisted** (avoid PII storage). It is a value object passed in at assess time.

### Identifiers
- **PKs are bigint** (Rails default). Do not use UUID primary keys: internal models are never enumerable from outside, and bigint keeps pgvector joins and indexes fast.
- **External identifiers use the `prefixed_ids` gem** (MIT). Note: prefixed_ids computes IDs from the PK — **no extra column or migration is needed**; the day-one requirement is (a) the model declarations and (b) the never-serialize-raw-PKs rule:
  - `Program` → `has_prefixed_id :prog`
  - `Requirement` → `has_prefixed_id :req`
  - `SourceDocument` → `has_prefixed_id :doc`
  - `DocumentChunk` → **none** (purely internal, hottest pgvector path, structurally never exposed — what leaves the system is a chunk's quoted text, not its ID).
- Rationale (asymmetry): adding a prefixed ID later costs one line, but by then raw bigint IDs will have leaked into API responses, making the switch a breaking change for external consumers of this public gem. **All JSON/API output and Result objects expose prefixed IDs only, never raw PKs, from day one.**

## 5. Ingestion architecture (ports and adapters / DIP)
Municipal data varies wildly in format (PDF / HTML / CSV / catalog APIs) and wording. The design absorbs that variance at **ingestion time, once**, so the assessment side never sees it.

### Where DIP applies — and where it must not
- **Do NOT abstract the assessment side.** Assessor/Retriever depend only on the normalized Program/Requirement/SourceDocument models. If assessment logic ever branches on a municipality, the design has failed.
- **DO cut an interface at the ingestion boundary.** The engine (high-level) defines the port; per-municipality messiness (low-level) implements it.

### The port (defined in this gem) — full contract
The port contract is the one thing this gem must own precisely. All three structs are fully specified; the Importer maps them 1:1 onto §4 models.
```ruby
module KyufyCore
  module Ingestion
    NormalizedProgram = Struct.new(
      :name, :authority, :jurisdiction,          # enum string per §4
      :prefecture_code, :municipality_code,      # JIS codes, nullable per §4
      :category, :target, :official_url,
      :valid_from, :valid_until, :status,        # dates nullable; status defaults "active"
      :requirements,                             # [NormalizedRequirement]
      :source_documents,                         # [NormalizedDocument]
      :fetched_at,
      keyword_init: true
    )

    NormalizedRequirement = Struct.new(
      :kind, :operator, :value,                  # per §4 semantics (income = 所得 default)
      :raw_text,
      :document_ref,                             # Integer index into source_documents (0-based). Pinned: not a key/string — adapter authors must not guess.
      keyword_init: true
    )

    NormalizedDocument = Struct.new(
      :title, :url, :body, :fetched_at,
      keyword_init: true
    )

    class Source
      # @return [Array<NormalizedProgram>]
      def fetch_programs = raise NotImplementedError
    end

    # Persists NormalizedProgram → Program / Requirement / SourceDocument,
    # then chunks each document body and embeds via the configured embedding adapter.
    class Importer; end
  end
end
```

### Adapters live OUTSIDE this gem
```
kyufy_core                  … Source port + Importer + normalized schema (public, MIT)
kyufy-adapters (separate)   … concrete adapters:
  ├── ManualYamlAdapter     … hand-written YAML → NormalizedProgram   ← MVP uses ONLY this
  ├── TokyoCatalogAdapter   … Tokyo Open Data catalog → normalized. **Concretized**: the catalog is CKAN;
  │                           enter via the CKAN API (`package_search`, then `package_show` for resource
  │                           CSV URLs) — the HTML UI is CAPTCHA-gated even for humans, the API is the
  │                           official programmatic route. Discover by SCHEMA, not keyword: filter
  │                           `fq=tags:自治体標準オープンデータセット` + `res_format=CSV` for the "支援制度"
  │                           dataset (Digital Agency's nationwide common format; Nakano/Koganei/
  │                           Higashimurayama publish it, CC BY) — one adapter reaches every municipality
  │                           on the standard. `q=給付金` alone is noisy (322 hits mixing ad-hoc HTML
  │                           resources); the adapter must skip non-conforming resources. The CSV's 対象
  │                           column is prose → structure it via LlmExtractionAdapter used as a decorator
  │                           (below).
  ├── SaitamaCityAdapter    … municipality HTML/PDF scrape → normalized
  └── LlmExtractionAdapter  … generic: LLM reads 要綱 text → drafts NormalizedProgram, human reviews &
                              confirms (源内-style doc×LLM, applied to ingestion). Composes as a DECORATOR
                              over any Source: `LlmExtractionAdapter.new(inner_source)` reads the inner
                              adapter's NormalizedPrograms (対象 prose sitting in a NormalizedDocument
                              body) and returns them with `requirements` filled. Both are Sources, so the
                              port and the Importer stay unchanged — no new pipeline stage in kyufy_core.
```
(Exception: a minimal `ManualYamlAdapter` ships inside this gem's test/seed support, since the seed needs it.)
(Licensing: catalog data is CC BY. Runtime ingestion preserves attribution via `source_document.url` /
`official_url`; if an adapter or seed ever **bundles** the CSV-derived data, add an explicit source + CC BY
credit.)

Why outside the gem:
1. **Matches the business model**: "engine = free public good; writing/maintaining YOUR municipality's adapter = the paid service." The Open Core split is enforced by the code structure itself.
2. **MVP stays 2-day-sized**: only `ManualYamlAdapter` (3–5 programs as YAML). No scrapers.
3. **LLM belongs in adapters too**: 要綱 PDF → structured Requirement is an LLM-shaped task.

### Requirement expressiveness — leave room to grow
Real programs contain composite conditions ("A かつ B、ただし C を除く"). **MVP requirements combine with AND — this is now explicit** (see §6 step 4). Reserve extension room: a self-referencing `parent_id` + `logic` (and/or/not) column pair on Requirement, noted in the migration comment. Do not implement tree evaluation for MVP.

## 6. Assessment flow (the Assessor core)
Input: a `Profile` (see §7 for the exact field definitions), optionally filtered by category.

0. **Applicability filter (deterministic, never semantic)**: select Programs where
   - `status == active`, AND
   - the date window covers today (`valid_from <= today` or null, `valid_until >= today` or null), AND
   - geography applies per §4 hierarchy (national ⊃ prefecture ⊃ municipality vs. the Profile's normalized residence) — **with two carve-outs: (a) if residence normalization failed, the geographic clause must NOT exclude anything; (b) if the profile's residence is an ancestor of the program's scope (§4 third clause), the program passes through**; in both cases the residence-dependent requirements resolve to 要確認 downstream (this is where §7's promise is actually enforced), AND
   - `target` matches, AND category filter if given.
   Excluding an expired/inactive/out-of-area program here is *correct* omission. Nothing else may exclude a program.
1. **Rule check ALL applicable programs (machine-readable)**: match each Program's Requirements against the Profile → met / not-met / undeterminable. **Semantic retrieval must never gate which programs get assessed** — vector similarity is lossy, and a recall miss here silently violates the prime directive (§0). At MVP scale (3–5 programs) rule-checking everything is trivially cheap; if program counts ever require pre-filtering, that becomes a spec change with an explicit threshold and a 要確認 bucket for filtered-out programs — not a silent drop.
2. **Evidence retrieval**: for each requirement being explained, pgvector-search the program's own chunks to locate supporting 要綱 passages (retrieval FOR evidence, not FOR candidacy). `raw_text` on the Requirement is the primary citation; chunks supplement it.
3. **LLM judge (grounding)**: per **program** (batch the program's requirements into one LLM call — N×M sequential calls don't scale and the adapter contract should reflect batching from day one), produce per-requirement 該当/非該当/要確認 + reasoning **grounded in `raw_text`**, attaching the quoted excerpt and `official_url`. Where the rule already decided, the LLM writes only the explanation; **the rule's verdict wins**.
4. **Aggregate (explicit precedence, AND semantics)**: requirements combine with **AND** (MVP). Program verdict precedence: **any 非該当 → 非該当** (one definitively failed requirement disqualifies, even if others are undeterminable) **> any 要確認 → 要確認 > all 該当 → 該当**.
   - **Carve-out cap (structural guarantee)**: any program that passed step 0 via carve-out (a) or (b) has its verdict **capped at 要確認**, with a synthesized residence reason (`residence_unverified`, "居住地の確認が必要") — **regardless of whether a `kind: residence` Requirement row exists**. Geographic scoping lives at the Program level, so a ward-scoped program may carry no residence Requirement at all (its 要綱 simply assumes residency); without the cap, an ancestor-residence profile whose other requirements all pass would aggregate to 該当 for a user who may not live there — asserting 該当 loosely, which the fail-safe forbids. The requirement-level mechanism handles the row-exists case; the cap is what closes the lid.
5. **Return** the Result (§7).

### Fail-safe principles (important)
- Ambiguity or missing info → always 要確認 (needs_review). Never assert 該当 loosely.
- Every verdict must carry **a short quoted excerpt (~40字, Japanese character count — not words) + `official_url`**.
- **Citation failure degrades, never drops**: if no citation can be produced for a requirement, the requirement's verdict becomes 要確認 with reason `citation_unavailable`, and the program **remains in the result**. Silent omission is forbidden (§0); "do not emit" was the old rule and is superseded.
- Output must always include a fixed disclaimer: "これは参考判定です。最終確認は各制度の公式窓口で行ってください。"

## 7. Public interface
### Profile (value object, never persisted)
```ruby
{
  age: 52,
  residence: "新宿区",                 # free text accepted; geo.rb normalizes to JIS codes
                                       # (新宿区 → 13104, a 特別区: no parent-city normalization).
                                       # If normalization fails, or the residence is coarser than
                                       # a program's scope → those programs get 要確認,
                                       # never silently skipped.
                                       # (さいたま市中央区 remains the ward-normalization
                                       #  test fixture in §9.)
  household_size: 3,
  prior_year_income_jpy: 864_000,      # 所得 (net/taxable), prior year. NOT 収入 (gross).
                                       # The field name forces the choice; see §4 income semantics.
  employment: "self_employed",
  target: "individual"
}
```
### Ruby API
```ruby
result = KyufyCore.assess(profile: profile, categories: %w[給付金 手当 控除])
result.each do |program_result|
  program_result.program_id     # prefixed id ("prog_…") — per §4, never the raw PK
  program_result.program_name
  program_result.verdict        # :eligible / :ineligible / :needs_review
  program_result.reasons        # [{ requirement_id: "req_…", kind:, verdict:, explanation:,
                                #    citation:, source_url: }]
  program_result.disclaimer
end
```
### JSON API (optional mount)
- `POST /kyufy_core/assessments` with a profile returns the JSON mirror of the Ruby result above (same keys; prefixed IDs only).
- This gem holds no auth (the shell handles it). The dummy app may be unauthenticated for MVP.
### Log hygiene (mandatory)
- The engine ships `config/initializers/filter_parameters.rb` adding the Profile fields (`residence`, `prior_year_income_jpy`, `age`, `household_size`, `employment`) to `Rails.application.config.filter_parameters` — Profile is unpersisted, but a POST would otherwise land verbatim in request logs.
- **Acknowledged tradeoff**: this mutates the host app's global filter list, and generic keys like `age`/`employment` will also mask the host's unrelated params with those names. Over-filtering is the safe direction for this domain, so this is intentional — but it is engine-reaches-into-host behavior; document it in the README so hosts aren't surprised.

## 8. LLM / embedding abstraction
- `KyufyCore.configure` allows swapping `llm_adapter`, `embedding_adapter`, and setting `embedding_dim` (see §4).
- MVP uses the **OpenCode adapters** (hackathon perk) for both LLM and embeddings.
- **Tests use NullAdapter (LLM) AND Embedding::NullAdapter** — the latter returns deterministic fake vectors (e.g., seeded hash of the content, fixed dim), so seeding + pgvector integration tests are fast, free, reproducible, and make **zero** network calls. Without a null embedding adapter the "reproducible test suite" claim is false.
- Model-agnostic by design (mirrors 源内): adapters also allow OpenAI-compatible / local models. **An Anthropic (Claude) adapter is a planned early addition** — it costs one thin class and buys three things: (1) insurance if OpenCode's output quality proves insufficient (swap = one config line, even the day before the demo), (2) a live demonstration of the model-agnostic claim (switching adapters on stage), (3) the post-hackathon migration target once the free OpenCode perk ends. Verdicts come from rules, not the LLM (§6), so raw model strength is not the deciding factor — pick the runtime adapter by comparing explanation quality on the seed programs, not by benchmark reputation.
- **Credentials (pinned)**: the Anthropic adapter reads `ENV["KYUFY_ANTHROPIC_API_KEY"]` — a dedicated key, deliberately separate from any tooling key (e.g. `ANTHROPIC_API_KEY` used by Claude Code itself). Live smoke tests are **gated on its presence and skip cleanly without it**; the suite stays green with zero network on machines lacking the key. Keys live in the maintainer's shell environment only — never in any file in this repo.

## 9. Testing (minitest)
- **Unit-test with the two Null adapters**: rule evaluation, aggregation precedence (非該当 > 要確認 > 該当), AND semantics, fail-safe fallback, citation-required behavior — no network.
- Table tests for the assessment logic (each operator, boundary values, missing-info → needs_review).
- **Applicability tests**: expired program (valid_until past) excluded; inactive excluded; geo hierarchy (national + matching prefecture + matching municipality all apply; non-matching municipality does not); **ward resident matches parent-city program (中央区 11105 → さいたま市 11100)**; **特別区 resident (新宿区 13104) matches 新宿区 + 東京都 + national, and is NOT normalized to any parent city**; **ancestor residence passes through to 要確認 (profile "東京都" vs. a 新宿区-scoped program; profile "さいたま市" vs. a 中央区-scoped program — present in result, not dropped)**; **carve-out cap: ancestor-residence profile vs. a program with NO residence Requirement row whose other requirements all pass → 要確認 with `residence_unverified`, never 該当**; residence normalization failure → 要確認 not skip.
- **Citation-unavailable test**: requirement degrades to 要確認 with `citation_unavailable`, program still present in result.
- pgvector search: integration test with a small fixed dataset (null embedding adapter).
- Guarantee by test that **no result ever exposes a raw PK** and **no verdict lacks a citation or a citation_unavailable degradation**.
- Contract-test the LLM adapter layer with a mock (no real API calls); the contract is **batched per program** (§6 step 3).

## 10. License / publishing
- Include **MIT LICENSE**. README states the concept and that this is a Rails reimplementation of 源内's administrative RAG, with reference links.
- Repo is public (GitHub). Two separate exclusions, for different reasons:
  - **Jumpstart Pro code: NEVER, license reason.** Paid and non-redistributable; even one copied line in this public repo is a violation. Absolute.
  - **Tailwind Plus code: not here, architecture reason.** Its license does allow public real-app repos (kyufy-web uses it publicly, with a README note). But this gem has no UI by design.
- README carries the "参考判定 / confirm with the official window" disclaimer.

## 11. MVP (2-day hackathon) — minimum to run
1. Seed 3–5 programs (via ManualYamlAdapter) as Program / Requirement / SourceDocument / DocumentChunk. **Programs are Tokyo-sourced (東京都の給付金・助成金＋国の制度) — the hackathon requires Tokyo open data.** **The primary demo Profile is a Tokyo 23-ward resident (新宿区), so the Tokyo seeds light up.** Optionally include one Saitama program and switch the Profile's residence to さいたま市中央区 mid-demo — cross-municipality generality (the public-good pitch) in one interaction.
2. `KyufyCore.assess`: applicability filter → rule-check all → evidence retrieval → (OpenCode or Null) grounding → Result.
3. Output always contains prefixed IDs + verdict + reasons + citation (or citation_unavailable + 要確認) + official_url + disclaimer.
4. Mount the JSON API in test/dummy so it demos standalone (no Jumpstart Pro needed).
- Stretch: plain-language toggle (要綱 wording → やさしい日本語); batch assessment of multiple programs.
- Not now: billing, auth, production マイナ/freee, full program coverage, exact benefit-amount calculation, condition trees.

## 12. First instruction to Claude Code (sample)
> "Following this spec, scaffold a mountable Rails Engine named `kyufy_core` on **Rails 8.1.3 / Ruby 4.0.6** (`rails plugin new kyufy_core --mountable -d postgresql`; pin versions in test/dummy and .ruby-version, gemspec uses `>= 8.1, < 9`). Follow mainstream Rails SaaS-template conventions **without copying code from any paid template (this gem is public MIT)**; see docs/LOCAL.md (gitignored) for maintainer-local reference paths. Add a migration enabling pgvector (EMBEDDING_DIM default 1536, HNSW index, condition-tree reservation comment on requirements), the models in §4 (with geo fields + prefixed_ids declarations), the full ingestion port in §5 (three structs + Importer + minimal ManualYamlAdapter for the seed), the Assessor in §6 (applicability filter, rule-check-all, batched-per-program LLM contract, aggregation precedence, citation-degradation), the Profile/Result/JSON API in §7 (prefixed IDs only, filter_parameters initializer), both Null adapters in §8, a minimal seed (1 program + 2 requirements + 1 source document), and the tests in §9. Defer real OpenCode calls; the goal is a green pipeline on the two Null adapters first."

## Appendix: future extensions (same gem grows into these)
- Same Engine → standalone API service → the assessment backend for the municipal SaaS.
- MCP server → external AIs (Claude etc.) can call the assessor; a public good. Authorize via WorkOS MCP Auth in the shell.
- マイナ integration (address / identity) and freee integration (income / business data) fill the Profile via adapters injected from the shell (this gem only defines the interfaces).
- Agentic-internet readiness: source_document / fetched_at / official_url already model attribution & freshness, so the data can later be monetized via Pay-Per-Use standards — no schema change needed.
- Pre-filter threshold: if program counts ever make rule-checking-all expensive, introduce retrieval-based pre-filtering as an explicit spec change (threshold + 要確認 bucket for filtered programs — never silent).
