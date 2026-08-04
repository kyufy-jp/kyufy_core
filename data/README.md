# data/ — the reusable datasets, without Ruby

Two things in this gem are worth having even if you never run it: the **JIS geography tables**
(fiddly, boring, and everyone building this kind of service needs them) and the **five real seed
programs**, each requirement quoting its 要綱 verbatim with a live official URL. Both were locked
inside Ruby — constants in `lib/kyufy_core/geo.rb`, YAML the engine's own adapter parses. Here they
are as plain JSON.

MIT-licensed, like the rest of the gem. See [Provenance and licensing](#provenance-and-licensing)
before redistributing the 要綱 text itself — that part isn't ours to license.

## These files are generated

`KyufyCore::Geo` and `db/seeds/programs/*.yml` remain the single source of truth. Regenerate with:

```bash
bundle exec rake data:export
```

`test/kyufy_core/data_export_test.rb` fails if the committed files drift from their sources, so
what you download here is what the engine actually assesses with — not a snapshot someone forgot
to refresh.

They are **not packaged into the gem** (the gemspec ships only `app/`, `config/`, `db/`, `lib/`);
they're here to be browsed and downloaded from GitHub. Nothing at runtime reads them.

---

## geo.json

```jsonc
{
  "prefectures":       { "北海道": "01", … },     // all 47, JIS X 0401 (2-digit)
  "designated_cities": [ "01100", … ],            // the 20 政令指定都市, JIS X 0402
  "municipalities":    { "千代田区": "13101", … }  // JIS X 0402 (5-digit)
}
```

**Codes are strings and must stay strings.** Leading zeros are significant — 札幌市 is `"01100"`,
and parsing it as an integer gives you `1100`, which is nothing.

Three things about this data are decisions, not omissions:

- **`municipalities` is partial, not national.** It covers the 東京都特別区 and さいたま市 + its 10
  wards — what the seed and tests need. A full national table belongs to ingestion, not here. So a
  lookup miss means *"not in this table"*, never *"no such city"*; treat it as unknown, not absent.
  Ruby hosts extend it with `config.extra_municipalities` (which does not change this export).
- **Ambiguous bare ward names are deliberately excluded.** `中央区` and `北区` are missing because
  several cities have one, so a bare name can't be resolved. The engine treats the miss as a
  normalization failure and degrades to 要確認 rather than silently matching the wrong
  municipality — [`docs/INVARIANTS.md`](../docs/INVARIANTS.md), rule 3. Disambiguated keys
  (`中央区（東京都）`, `さいたま市中央区`) are present. If you build your own table, keep this
  property: a wrong match is far worse than a miss.
- **東京23区 are not in `designated_cities`.** Each 特別区 is a full municipality with no parent
  city, so ward→parent-city resolution correctly finds nothing for them. Wards of さいたま市,
  横浜市, 大阪市 etc. do have a parent. The hierarchy rule the engine applies: a resident of a ward
  matches a program scoped to the parent city, but a resident of the parent city facing a
  ward-scoped program is *coarser than the program* → 要確認, never excluded.

## programs.json

```jsonc
{
  "programs": [
    {
      "source_file": "018_support.yml",
      "name": "018サポート",
      "authority": "東京都福祉局",
      "jurisdiction": "prefecture",      // national | prefecture | municipality
      "prefecture_code": "13",           // required unless national
      "municipality_code": null,         // required when municipality
      "category": "給付金",               // 給付金 | 補助金 | 助成金 | 手当 | 控除
      "target": "individual",            // individual | business
      "official_url": "https://…",
      "valid_from": "2026-04-01",        // ISO date or null (null = no bound)
      "valid_until": null,
      "status": "active",                // active | inactive
      "source_documents": [ … ],
      "requirements":     [ … ]
    }
  ]
}
```

### source_documents[]

| field | meaning |
|---|---|
| `title` | Section heading the text was taken from |
| `url` | The page it came from |
| `fetched_at` | ISO date the text was read |
| `license` | Publisher's license, e.g. `"PDL1.0"` — or `null` |
| `body` | The 要綱 text, as published |

### requirements[]

| field | meaning |
|---|---|
| `kind` | `income` \| `age` \| `residence` \| `household` \| `employment` \| `other` |
| `operator` | `lt` \| `lte` \| `gt` \| `gte` \| `eq` \| `in` \| `exists` |
| `value` | The machine-readable condition (shapes below) |
| `raw_text` | **Verbatim 要綱 excerpt** — the citation shown to the user |
| `document_ref` | 0-based index into this program's `source_documents` |

`value` by operator:

```jsonc
{ "threshold": 18 }    // lt / lte / gt / gte — compared numerically against the profile field
{ "eq": "杉並区" }      // eq
{ "in": ["…", "…"] }   // in
{}                     // exists — the profile field just has to be present
```

Three `measure` values change how a requirement is read, because the plain comparison would be
wrong or unanswerable:

- `{"measure": "収入"}` on an `income` requirement — the profile carries 所得 (net/taxable), not
  収入 (gross). Not convertible, so it resolves to 要確認 rather than comparing the wrong quantity.
  **Every `income` requirement without this key is 所得.**
- `{"measure": "住民税非課税"}` — answered by asking the user directly (they know), not computed
  from an income figure. Unanswered is 要確認, never 非該当: these conditions usually carry OR
  alternatives such as 児童扶養手当受給.
- `{"measure": "雇用保険被保険者期間"}` — the insured period isn't in the profile, so a current or
  former employee is 要確認 and only the clearly-not-被保険者 `self_employed` is 非該当.

A `note` key inside `value` is free-text explaining a judgment call; nothing evaluates it.

---

## Provenance and licensing

The conventions in this data matter more than the five rows themselves — they're what makes an
assessment auditable:

1. **`raw_text` is verbatim.** It is quoted back to the user as the reason for a verdict, so
   paraphrasing it turns a citation into a claim. If you can't quote it, you don't have it.
2. **`license: null` means unknown — assume all rights reserved.** Most Japanese municipal pages
   state no open license, so `null` is the honest common case. It is *not* "free to use". The
   engine carries this value all the way to each reason so a host app can decide what it may
   display. Where a publisher does state one (e.g. `PDL1.0`), it's recorded.
3. **`fetched_at` is a freshness bound, not a decoration.** Programs open, close, and change
   wording. Re-fetch before relying on any of this — the URLs are in every record for exactly that
   reason.

The 要綱 text in `body` and `raw_text` is quoted from the publishers named in each record, under
their terms; the MIT license on this repository covers the code and the structure, not the quoted
source text.
