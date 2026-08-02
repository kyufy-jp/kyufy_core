# Invariants — the rules an eligibility assessor has to hold

This is the transferable part of kyufy_core. The Rails engine, the pgvector search, the adapters
— none of that has to be copied. These eleven rules do, in whatever language you're building in,
because each one is a mistake we'd otherwise have shipped, and most of them fail *silently*.

The reference implementation is this repo (file pointers below); the design spec is
[`docs/SPEC.md`](SPEC.md). Reuse freely — MIT.

## The premise

For a public-benefit assessor, the failure modes are not symmetric.

**Silently not assessing a program someone was entitled to is the worst outcome.** It is worse
than a cautious 要確認, and worse than an obviously wrong 該当 — because the user never learns
there was anything to check. Nobody files a complaint about a benefit they never heard of. Every
rule below is downstream of that asymmetry, so if you disagree with the premise, the rules won't
make sense.

The verdicts: **該当** (eligible) / **非該当** (ineligible) / **要確認** (needs review).

---

### 1. Only status, date window, and geography may exclude a program

Nothing else gets to remove a program from consideration. Not a low relevance score, not a
confidence threshold, not "the user probably isn't eligible anyway." An expired or out-of-area
program is a *correct* omission; everything else must produce a verdict the user can see.

*Why:* every other filter is a guess about eligibility made before the eligibility check runs.
*Where:* `Assessor#admissible_programs` — one filter, in one place, and no other code path
removes a program.

### 2. Semantic retrieval is for evidence, never for candidacy

Vector search finds the passage to quote. It never decides which programs get assessed.

*Why:* embedding similarity is lossy in a way that's invisible — a program drops off the list and
no one can tell it happened. This is rule 1's most tempting violation, because "retrieve the top-k
relevant programs" is the obvious RAG shape and it's wrong here.
*Where:* `Retriever#evidence_chunks` takes a `program:` argument and searches only inside it. The
signature makes the violation impossible to write by accident.

### 3. A residence that can't be resolved passes through, capped at 要確認

Normalization failure is not exclusion. Neither is a residence that's *coarser* than the program's
scope (a 東京都 resident against a 杉並区 program). Both are admitted and capped at 要確認.

*Why:* "we couldn't parse your address" is our problem, not grounds to hide a benefit.
*Corollary:* never resolve an ambiguous place name to a plausible guess. `中央区` exists in several
cities, so it resolves to *nothing* and degrades to 要確認. A wrong match is worse than a miss —
it produces a confident verdict about the wrong jurisdiction.
*Where:* `Geo.normalize`, `Geo.applies` (`:match` / `:ancestor` / `:none`), `Assessor#geo_admission`.

### 4. Ambiguity, missing information, and missing citations all resolve to 要確認

There is no fourth verdict and no "probably eligible." If the rule can't be decided from what the
user actually told you, it's 要確認.

*Why:* a loose 該当 sends someone to a counter with paperwork for a benefit they can't get. A
cautious 要確認 sends them to the same counter with a question. Only one of those wastes their day.
*Where:* `RuleCheck` returns `:undeterminable` rather than guessing; `Assessor::RULE_TO_VERDICT`.

### 5. No citation, no 該当

A requirement with no quotable source text degrades to 要確認 no matter what the rule computed.

*Why:* an uncited verdict can't be checked by the user, and an assessor whose reasoning can't be
checked is just an opinion. The verdict and the evidence are one unit.
*Where:* `Assessor#build_reason` — the citation check overrides the rule verdict, not the reverse.

### 6. The citation is verbatim, never paraphrased

Quote the 要綱 exactly, and store the exact excerpt next to the machine-readable condition.
Paraphrasing turns a citation into a claim.

*Why:* the user's next step is taking this to an official window. A quote survives that; a summary
of a quote does not.
*Where:* `Requirement#raw_text` sits beside `kind`/`operator`/`value` — that pairing is the whole
design. See [`data/README.md`](../data/README.md) for how the seed records it.

### 7. Verdicts are deterministic; the model writes prose only

The LLM never decides 該当 / 非該当 / 要確認. It receives the rule's verdict and writes the
explanation sentence. An API error, refusal, or unparseable response falls back to template prose
— the assessment does not change and does not break.

*Why:* a verdict you can't reproduce is a verdict you can't defend, debug, or regression-test. You
also want the option of running with no model at all.
*Where:* `LLM::GroundedAdapter#assess_program` returns `item[:rule_verdict]` and ignores whatever
the model said about it; the `rescue` degrades to `fallback_explanation`.

### 8. Aggregation precedence: 非該当 > 要確認 > 該当

Requirements combine with AND. One 非該当 makes the program 非該当; otherwise one 要確認 makes it
要確認; only all-該当 is 該当.

*Why:* stated once, applied everywhere, it's the difference between an auditable rule and
per-program improvisation. Note the ordering is *not* "worst wins" — a definitive 非該当 outranks
a 要確認, which is what lets rule 9's cap work without hiding real ineligibility.
*Where:* `Assessor::PRECEDENCE` and `#aggregate`.

### 9. A cap is a synthesized reason, not a special case

When a program is admitted despite unverified residence, don't add a flag and a branch. Append a
`needs_review` reason carrying the explanation. Aggregation then caps the program at 要確認 on its
own — and still reports 非該当 if a requirement genuinely failed.

*Why:* branch-based caps multiply. The reason list is already the output contract; expressing the
cap as data means it displays, aggregates, and explains itself for free.
*Where:* `Assessor#residence_unverified_reason`, appended only when the program has no residence
requirement of its own to carry the 要確認.

### 10. When a 要確認 hinges on one answerable question, ask it

If the only reason something is unresolved is an unset profile field the user *knows the answer
to* — 住民税は非課税ですか — return the question with the verdict instead of stopping at "unclear".

*Why:* 要確認 is a fail-safe, not a destination. A 逆質問 converts one into a real answer at
almost no cost.
*Where:* `Assessor#follow_up_for`, `KyufyCore::FOLLOW_UP_QUESTIONS`.

### 11. Every result carries the disclaimer, and identifiers are opaque

The assessment is a reference, not a decision: **これは参考判定です。最終確認は各制度の公式窓口で
行ってください。** It ships attached to the result, not left to the caller to remember. Separately,
external identifiers are prefixed and opaque (`prog_…`, `req_…`) — never raw database keys.

*Why:* a disclaimer a caller can forget is a disclaimer that will be forgotten. And raw sequential
IDs leak row counts and invite enumeration once the API is public.
*Where:* `KyufyCore::DISCLAIMER` on every `Result::ProgramResult`; `has_prefix_id`.

---

## The two that are hardest to keep

Rules 1 and 2 are the ones that erode, because violating them always looks like an improvement.
Filtering by relevance makes the output shorter and cleaner. Letting the model overrule an
awkward rule verdict makes a bad answer look better. Both trade an invisible failure for a visible
polish, and the invisible failure is the one that costs someone their benefit.

If you keep one thing from this document, keep the asymmetry in the premise. The rest is
bookkeeping.
