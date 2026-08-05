# kyufy_core（日本語）

**日本の公的給付（給付金・補助金・助成金・手当・控除）の受給資格を判定する、オープンソースの
判定エンジンです。** 利用者の状況（プロフィール）と制度の要件を突き合わせて、
**該当 / 非該当 / 要確認** を、**要綱の逐語引用と公式URL付き**で返します。

> **これは参考判定です。最終確認は各制度の公式窓口で行ってください。**

英語版は [README.md](README.md)、設計ルールは [docs/INVARIANTS.md](docs/INVARIANTS.md)、
制度データの追加手順は [docs/ADDING_PROGRAMS.ja.md](docs/ADDING_PROGRAMS.ja.md) にあります。
ライセンスは MIT ですが、**同梱している要綱本文の扱いは別です**（[後述](#ライセンスと要綱本文の取り扱い)）。

---

## 5分で判断する

### このgemがやること

- 制度（Program）と要件（Requirement）をデータとして持つ。**要件ごとに、機械可読な条件と要綱の
  逐語引用がセットで保存される**。これが設計の中心です。
- プロフィール（年齢・居住地・世帯人数・前年所得など7項目）を受け取り、制度ごとに
  該当 / 非該当 / 要確認 と、その理由・引用・出典URLを返す。
- **申請漏れを起こさない**ことを最優先にした判定ロジック。制度を候補から外してよいのは
  「終了・期間外・対象地域外」の3つだけで、それ以外は必ず何らかの判定を返します。
- 住所の自由入力をJISコードに正規化（政令指定都市の行政区↔親市の階層も扱う）。
- LLM・埋め込みモデルは差し替え可能（Anthropic / OpenAI互換 / ローカル / テスト用Null）。

### このgemがやらないこと

- **判定をLLMにさせません。** 該当/非該当/要確認はすべてルールで決まります。LLMは説明文を書くだけ。
  APIが落ちてもテンプレート文にフォールバックし、判定は変わりません。
- **UIを持ちません。** 画面・認証・課金はホストアプリ側の責任です。
  最小の実装例が [kyufy-web](https://github.com/kyufy-jp/kyufy-web) にあります。
- **制度データベースではありません。** 同梱は実在制度5件（要件12件）だけです。これは
  「フォーマットと判定ロジックの動くサンプル」であって、網羅的なデータではありません。
  制度を増やす前提の設計です → [制度追加ガイド](docs/ADDING_PROGRAMS.ja.md)。

### 採用の向き / 不向き

**向いている**

- 給付金・支援制度のマッチング、申請漏れの発見、行政の窓口支援などを作る場合。
- 「なぜその判定なのか」を出典付きで示す必要がある場合。審査で説明できる形になります。
- Rails（またはPostgreSQLを使えるサーバ環境）で作る場合。

**向いていない**

- **Cloudflare Workers / Pages 単体では動きません。** Rails engine + PostgreSQL + pgvector が必要です。
  Workersを使う場合は、このエンジンをDockerで別のサーバ（Fly.io / Render / VPS など）に置き、
  JSON APIとして `fetch` で呼ぶ構成になります。
- 制度データを自分で用意する時間がない場合。同梱5件のままでは、デモとしては動きますが
  サービスとしては薄いです。
- 判定の根拠を問わず、とにかく候補を出したい場合。このエンジンは、根拠がなければ
  該当を出さず要確認に倒します。

---

## まず動かす（Ruby不要・Docker）

PostgreSQL + pgvector と JSON API が立ち上がり、実在制度5件が投入済みの状態になります。
マシンには何もインストールされません。

```bash
docker compose up --build   # 初回はビルド + 投入で1分ほど
```

```bash
curl -s localhost:3100/kyufy_core/assessments \
  -H 'content-type: application/json' \
  -d '{"profile":{"age":42,"residence":"杉並区","household_size":3,
       "prior_year_income_jpy":900000,"target":"individual"}}'
```

5制度すべてが判定されて返ります（国・東京都・杉並区のいずれも）。除外できるのは
終了・期間外・対象地域外だけだからです。上記のプロフィールでは3件が要確認になります。
推測で該当を出すことを、エンジンが拒否しているためです。

- **ポートは3000ではなく3100です。** `rails server` は `127.0.0.1:3000`、Dockerは `0.0.0.0:3000` に
  bindするため、両方が同時にポート3000を保持でき、`localhost:3000` が別のアプリに繋がってしまう
  事故を避けています。変更は `KYUFY_PORT`（DBに直接繋ぐ場合は `KYUFY_DB_PORT`、既定5433）。
- **APIキー不要・ネットワーク不要。** Nullアダプタで動くので、埋め込みは決定的、説明文は
  テンプレートです。判定・引用・出典URLはルール由来なので、**モデルの有無で結果は変わりません**。
  実際の生成文が欲しい場合は `KYUFY_LLM=anthropic KYUFY_ANTHROPIC_API_KEY=sk-… docker compose up`。
- **リセット**は `docker compose down -v`。投入済みDBに再投入すると制度が重複するため、
  エントリポイントはDBが空のときだけ投入します。
- これは**開発用構成**です（認証なし・TLSなし、リポジトリ内のダミーアプリを起動）。
  公開しないでください。

---

## Railsアプリに組み込む

RubyGems未公開のため、gitから入れます。

```ruby
# Gemfile
gem "kyufy_core", github: "kyufy-jp/kyufy_core"
```

```bash
bin/rails kyufy_core:install:migrations
bin/rails db:migrate
```

```ruby
# config/routes.rb（JSON APIを使う場合のみ）
mount KyufyCore::Engine => "/kyufy_core"
```

```ruby
KyufyCore.import_dir   # db/seeds/programs/*.yml を投入
```

必要環境：Ruby 3.2以上、Rails 8.1以上、PostgreSQL +
[pgvector](https://github.com/pgvector/pgvector)。
マイグレーションが `vector(1536)` 列を作るので、別の次元数の埋め込みモデルを使う場合は
`config.embedding_dim` と一緒に変更してください。

### 判定する

```ruby
result = KyufyCore.assess(
  profile: {
    age: 52,
    residence: "新宿区",              # 自由入力。内部でJISコードに正規化
    household_size: 3,
    prior_year_income_jpy: 864_000,   # 前年の「所得」。「収入」ではありません
    employment: "self_employed",
    target: "individual",
    resident_tax_exempt: nil          # 住民税非課税世帯か。true/false/nil を本人が回答（計算しない）
  },
  categories: %w[給付金 手当 控除],   # 任意。給付金 補助金 助成金 手当 控除
  plain_language: false               # true でやさしい日本語の説明文
)

result.each do |r|
  r.program_id     # "prog_…"（生の主キーは公開しない）
  r.program_name   # 制度名
  r.verdict        # :eligible（該当）/ :ineligible（非該当）/ :needs_review（要確認）
  r.reasons        # 要件ごとの理由。引用・出典URL・ライセンス・逆質問を含む
  r.disclaimer     # 免責文（必ず付随する）
end
```

`reasons` の各要素：

| キー | 内容 |
|---|---|
| `requirement_id` | `req_…` |
| `kind` | `income` / `age` / `residence` / `household` / `employment` / `other`（日本語表記は `Requirement.kind_label`） |
| `verdict` | `:eligible` / `:ineligible` / `:needs_review` |
| `explanation` | 説明文（LLMまたはテンプレート） |
| `citation` | 要綱の逐語引用 |
| `citation_status` | `:present` / `:unavailable`。引用が取れない要件は要確認に落ちる |
| `source_url` | 公式URL |
| `license` | 出典のライセンス（`null` は「不明」であって「自由」ではない） |
| `follow_up` | 要確認を解消できる逆質問（該当する場合のみ） |

### 世帯・複数人

```ruby
KyufyCore.assess_household(household: { members: [ 本人, 母, 父 ] })  # 所得を合算して1件の結果
KyufyCore.assess_batch(profiles: [ a, b, c ])                          # 1人ずつ判定して結果を配列で返す
```

### JSON API

```
POST /kyufy_core/assessments            # { profile: {...} }  -> { assessments: [...] }
POST /kyufy_core/assessments/batch      # { profiles: [...] } -> { results: [{ assessments: [...] }, …] }
POST /kyufy_core/assessments/household  # { members: [...] }  -> { assessments: [...] }
```

いずれも `categories` と `plain_language` を任意で受け取ります。プロフィールは前述の7項目のみ
許可され、それ以外は捨てられます。認証はこのgemには入っていません（ホストアプリの責任）。

---

## 制度データを増やす

同梱の5件は出発点です。YAMLを1ファイル書けば1制度増えます。

```bash
# db/seeds/programs/your_program.yml を追加してから
bin/rails runner 'KyufyCore.import_yaml("db/seeds/programs/your_program.yml")'
```

フィールドの意味、`value` の書き方、要綱の引用ルールは
**[docs/ADDING_PROGRAMS.ja.md](docs/ADDING_PROGRAMS.ja.md)** にまとまっています。慣れれば1制度30分ほどです。

同梱のJISコード表は**東京23区とさいたま市だけ**です。三鷹市・八王子市などの制度を足すときは、
地理テーブルも一緒に足してください。足さないと、その自治体の住民の住所が正規化できず、
判定が全部要確認どまりになります。

```ruby
KyufyCore.configure do |c|
  c.extra_municipalities = { "三鷹市" => "13204", "八王子市" => "13201" }
end
```

コードは文字列で渡します（先頭の0が意味を持つため）。数値や桁数違いは起動時に `ArgumentError`
になります。

---

## gemを使わずに再利用する

Rubyを使わなくても、この2つは単体で持っていく価値があります。

- **[`data/`](data/README.md)** — JISコードの地理テーブルと、実在制度5件をプレーンJSONで書き出したもの。
  スキーマも記載。`KyufyCore::Geo` と `db/seeds/programs/*.yml` から生成され、ずれるとテストが落ちる
  ようになっているので、エンジンが実際に判定に使っているものと一致します。
  - `geo.json` — 47都道府県、政令指定都市20、市区町村33（東京23区＋さいたま市）のJISコード。
    **コードは文字列です**（先頭の0が意味を持つため。札幌市は `"01100"`）。
  - `programs.json` — 制度5件。各要件が要綱の逐語引用と公式URLを持ちます。
- **[`docs/INVARIANTS.md`](docs/INVARIANTS.md)** — このエンジンが守っている11のルール
  （申請漏れ防止、検索は根拠のためだけに使う、引用なしに該当を出さない、判定は決定的、など）。
  それぞれ「なぜ必要か」「どこで守っているか」付き。**他の言語で同種のものを作るなら、
  コードではなくこれを写してください。**

---

## ライセンスと要綱本文の取り扱い

- **このgemのコードは [MIT](MIT-LICENSE)** です。自由に使ってください。
- **同梱している要綱・公式ページの本文（`source_documents[].body` と `raw_text`）は別です。**
  これは各自治体・省庁の著作物で、こちらがライセンスできるものではありません。
  各制度の `license` フィールドがその出典の条件を示します。
  - `PDL1.0` — 政府標準利用規約準拠（同梱5件のうち1件）。
  - `null` — **不明であって、自由ではありません**（同梱5件のうち4件）。オープンライセンスの
    明示がないページから引用しているという意味です。
- サービスとして公開する場合、要綱本文をそのまま再配布してよいかは、**出典ごとに自分で確認**
  してください。判定結果に公式URLを併記し、原文は出典側で読ませる作りにするのが安全です。
- 制度を自分で追加する場合も、`license` は分かったことだけを書き、不明なら `null` のままに
  してください。詳細は [data/README.md](data/README.md) の「Provenance and licensing」。

---

## 開発

```bash
bundle install                        # ./vendor/bundle に入ります
RAILS_ENV=test bin/rails db:migrate   # マイグレーションは同梱のダミーアプリに対して走ります
bin/rails test                        # 全テスト（Nullアダプタ、ネットワーク・キー不要）
bundle exec rubocop -a                # rails-omakase スタイル
```

ダミーアプリのスキーマ形式は `:sql`（`test/dummy/db/structure.sql`）です。pgvectorの `vector()` 列と
HNSWインデックスが Ruby の `schema.rb` で往復できないためです。

実APIを叩くスモークテストが3つあり、対応する環境変数がなければスキップされます
（`KYUFY_ANTHROPIC_API_KEY` / `KYUFY_OPENAI_API_KEY`）。

---

## 参考

- [kyufy-web](https://github.com/kyufy-jp/kyufy-web) — このエンジンをマウントする最小のホストアプリ実装。
- [源内 / genai-ai-api](https://github.com/digital-go-jp/genai-ai-api) — デジタル庁の行政向けRAG（MIT）。
  「出典に基づいて答える」という設計の系譜。ただしkyufyは、引用を取り込み時に人手で確定させ、
  判定はルールで行う点で意図的に分岐しています。
- [東京都オープンデータカタログサイト](https://portal.data.metro.tokyo.lg.jp/) — 制度データの出典を
  探す場合はここから。
