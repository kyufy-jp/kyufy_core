# 制度データの追加ガイド

同梱の制度は5件だけです。これは**フォーマットの見本**であって、データセットではありません。
このgemは制度を自分で足す前提で設計されています。YAMLを1ファイル書けば1制度増えます。
慣れれば1件30分ほどです。

前提知識は [README.ja.md](../README.ja.md)、判定ロジックの背景は
[docs/INVARIANTS.md](INVARIANTS.md) にあります。

---

## 全体の流れ

1. 制度の**公式ページ**を1つ決める（要件が書いてあるページ。PDFの要綱でも可）。
2. `db/seeds/programs/<制度名>.yml` を作る。**1ファイル1制度**。
3. 要件を「機械可読な条件」と「要綱の逐語引用」のセットで書く。
4. 取り込む。
5. 実際に判定して、意図した結果になるか確認する。

```bash
bin/rails runner 'KyufyCore.import_yaml("db/seeds/programs/your_program.yml")'
```

---

## テンプレート

コピーして使ってください。`<>` の部分は置き換えます。
**引用部分（`body` と `raw_text`）に、自分で書いた要約を入れないでください。**
公式ページから逐語でコピーします（理由は[後述](#raw_text-のルール)）。

```yaml
# <制度名> — <実施主体>
# Source (retrieved YYYY-MM-DD): <公式URL>
# raw_text はすべて <どのセクション> からの逐語引用。
- name: <制度名>
  authority: <実施主体。例: 東京都福祉局 / 三鷹市>
  jurisdiction: municipality      # national / prefecture / municipality
  prefecture_code: "13"           # 文字列。国の制度なら null
  municipality_code: "13204"      # 文字列。jurisdiction が municipality のときは必須
  category: 助成金                # 給付金 / 補助金 / 助成金 / 手当 / 控除
  target: individual              # individual / business
  official_url: <公式URL>
  valid_from: 2026-04-01          # 申請開始日。不明なら null
  valid_until: 2026-09-30         # 申請期限。通年・不定なら null
  status: active                  # active / inactive
  source_documents:
    - title: <ページタイトル、または要綱名>
      url: <公式URL>
      fetched_at: 2026-08-05      # 取得日
      license: null               # 不明なら null。PDL1.0 等が明示されていればそれを書く
      body: |
        <公式ページの該当箇所を逐語でコピー。要件が書かれている段落全体。>
        <ここが引用の根拠になり、pgvectorの検索対象にもなる。>
  requirements:
    - kind: age
      operator: lte
      value:
        threshold: 18
      raw_text: <年齢要件の文を、公式ページから逐語でコピー>
      document_ref: 0             # source_documents の何番目か（0始まり）
    - kind: residence
      operator: eq
      value:
        eq: <自治体名>
      raw_text: <居住要件の文を、公式ページから逐語でコピー>
      document_ref: 0
```

---

## フィールドリファレンス

### 制度（Program）

| フィールド | 必須 | 内容 |
|---|---|---|
| `name` | ○ | 制度名 |
| `authority` | | 実施主体 |
| `jurisdiction` | ○ | `national` / `prefecture` / `municipality` |
| `prefecture_code` | `national` 以外○ | JIS X 0401（2桁）。**文字列**（`"13"`。`13` と書くと先頭0のある県で壊れます） |
| `municipality_code` | `municipality` のとき○ | JIS X 0402（5桁）。**文字列**（`"13204"`） |
| `category` | ○ | `給付金` / `補助金` / `助成金` / `手当` / `控除` のいずれか |
| `target` | | `individual` / `business` |
| `official_url` | ○ | 公式URL。判定結果の全理由に付いて返ります |
| `valid_from` / `valid_until` | | 申請期間。`null` は「制限なし」。**期間外の制度は判定対象から外れます**（正しい除外） |
| `status` | | 既定 `active`。`inactive` にすると判定対象外 |

### 出典（source_documents）

| フィールド | 内容 |
|---|---|
| `title` | ページタイトルや要綱名 |
| `url` | 出典URL |
| `body` | **公式ページの逐語コピー**。200文字ずつに分割され、埋め込みベクトル化されます（`raw_text` がない要件の引用を補完するため） |
| `fetched_at` | 取得日。制度は毎年変わるので必ず入れてください |
| `license` | 出典のライセンス。**不明なら `null`。`null` は「自由」ではなく「不明」の意味です** |

### 要件（requirements）

| フィールド | 内容 |
|---|---|
| `kind` | `income` / `age` / `residence` / `household` / `employment` / `other` |
| `operator` | `lt` / `lte` / `gt` / `gte` / `eq` / `in` / `exists` |
| `value` | 演算子ごとの形（下記） |
| `raw_text` | **要綱の逐語引用**。これが判定結果に出る引用文になります |
| `document_ref` | `source_documents` のインデックス（0始まり）。省略可 |

`kind` は利用者のプロフィールの項目に対応します。プロフィールは
`age` / `residence` / `household_size` / `prior_year_income_jpy` / `employment` / `target` /
`resident_tax_exempt` の7項目だけです。ここにない情報は判定できません（→ 要確認になります）。

---

## `value` の書き方

### 演算子ごとの形

```yaml
operator: lte      # lt / lte / gt / gte
value:
  threshold: 2000000    # 数値

operator: eq
value:
  eq: 杉並区

operator: in
value:
  in: [ employee, self_employed ]

operator: exists
value: {}          # プロフィールにその項目が入力されているか
```

- `income` の数値は **前年の「所得」（円）** です。「収入」ではありません。
- 判定できない場合（該当する項目が未入力、値が数値でない等）は、すべて**要確認**になります。
  推測はしません。

### 特別扱いされる `value`

以下は `RuleCheck` に専用の分岐があります。制度要件としてよく出てくるうえ、
素直に数値比較すると誤判定になるためです。

| 書き方 | 挙動 |
|---|---|
| `kind: income` + `value: { measure: 住民税非課税 }` | 利用者の `resident_tax_exempt` で判定。`true` → 該当、`false`/未入力 → **要確認**（非該当にはしません。実際の制度では「または児童扶養手当受給世帯」等のOR条件が付くことが多いため）。未入力なら「住民税は非課税ですか?」という**逆質問**が結果に付きます |
| `kind: income` + `value: { measure: 収入 }` | 常に**要確認**。プロフィールは所得しか持たないので、収入基準は判定できません |
| `kind: employment` + `value: { measure: 雇用保険被保険者期間 }` | `self_employed` のみ非該当、それ以外は**要確認**（被保険者期間はプロフィールにないため）。逆質問付き |

### `kind: residence` は特別

居住要件は `RuleCheck` を通りません。制度の `jurisdiction` / `prefecture_code` /
`municipality_code` と、利用者の住所を突き合わせた**地理判定の結果**で決まります。

- 完全一致 → 該当
- 住所が制度より粗い（例：制度は杉並区、利用者は「東京都」までしか分からない）→ **要確認**
- 住所を正規化できなかった → **要確認**（除外はしません）
- 対象地域外 → その制度自体が判定対象から外れます

したがって `residence` 要件の `value` は実質メモ書きです。**大事なのは `raw_text`**
（引用文として表示される）と、制度側のコード指定が正しいことです。

### `kind: other` の使いどころ

プロフィールに対応する項目がないので、**常に要確認**になります。
「機械では判定できないが、利用者に伝えるべき条件」を可視化するために使います。

```yaml
- kind: other
  operator: eq
  value:
    eq: 該当
    note: エアコン未設置 or 冷房不可（プロフィールから判定不可 → 要確認）
  raw_text: 自宅にエアコンが1台もない世帯
  document_ref: 0
```

> **落とし穴：`kind: other` に `operator: exists` を使わないでください。**
> `exists` は「項目が入力されているか」を見る演算子で、プロフィールに `other` という項目は
> 存在しないため、**非該当**（制度全体が非該当）になってしまいます。要確認にしたい場合は
> 上のように `eq` を使ってください。

---

## `raw_text` のルール

**要綱の文を、一字一句そのままコピーしてください。**

- 要約・言い換えをした時点で、それは引用ではなく主張になります。利用者の次の行動は
  「この結果を持って窓口に行く」ことなので、原文はそこで通用しますが、要約は通用しません。
- `raw_text` が空の要件は、pgvectorが `body` から近い箇所を探して補完します。
  それでも見つからなければ、その要件は**引用なし**として要確認に落ちます
  （ルールが該当を出していても、です）。
- 逆に言えば、`raw_text` を丁寧に書くほど判定の質が上がります。ここが一番手をかける価値の
  ある場所です。

詳しくは [INVARIANTS.md](INVARIANTS.md) のルール5・6を参照。

---

## 自分の自治体がJISコード表にない場合

`KyufyCore::Geo::MUNICIPALITIES` に入っているのは、**東京23区とさいたま市（+10区）だけ**です
（全国表は取り込み側の責任という切り分け）。三鷹市・八王子市・町田市などは入っていません。

ここに無い自治体の制度を追加すると、**その自治体の住民の住所が正規化できず、判定が全部
要確認どまり**になります。デモとしては見栄えが悪いので、制度を足すときは地理テーブルも
一緒に足してください。

ホストアプリの初期化ファイルに置きます（`config/initializers/kyufy_core.rb` など）。

```ruby
KyufyCore.configure do |c|
  c.extra_municipalities = {
    "三鷹市"   => "13204",
    "八王子市" => "13201",
    "町田市"   => "13209"
  }
end
```

- **コードは必ず文字列**です。数値や桁数違いを渡すと、その場で `ArgumentError` になります
  （黙って正規化に失敗して全部要確認になるより、起動時に落ちたほうが良いため）。
- ここでの指定は同梱テーブルより優先されます。同梱の値が古い・誤っている場合の上書きにも使えます。
- 同梱の `KyufyCore::Geo::MUNICIPALITIES` 自体は変わりません（`data/geo.json` の書き出し内容も
  変わりません）。あくまでホストアプリ側の追加です。

コードは[総務省の全国地方公共団体コード](https://www.soumu.go.jp/denshijiti/code.html)から
引けます（5桁のうち先頭2桁が都道府県コード。**検査数字を含む6桁ではなく5桁**を使います）。

### 同じ名前の区が複数あるときは

`中央区` `北区` `港区` などは複数の市に存在するため、**素の名前では登録しません**。
既存の表では `中央区（東京都）` `港区（東京都）` のように市名を含む形にしてあります。
`北区` は東京都（13117）にもありますが、大阪市・京都市・名古屋市・神戸市・さいたま市にも
あるため、あえて入っていません。

これは意図的な仕様です。**間違った自治体に一致させるくらいなら、正規化に失敗して要確認に
落とすほうが良い**という判断です（[INVARIANTS.md](INVARIANTS.md) ルール3）。
`extra_municipalities` で足すときも同じ性質を保ってください
（`"北区"` ではなく `"北区（東京都）" => "13117"` のように書く）。

なお、住所を自由入力させると正規化の失敗が増えます。UI側では
[`data/geo.json`](../data/geo.json) を使って**選択式にする**のが確実です。

---

## 取り込みと確認

### 取り込む

```ruby
KyufyCore.import_yaml("db/seeds/programs/your_program.yml")  # 1ファイル
KyufyCore.import_dir                                          # db/seeds/programs/*.yml 全部
KyufyCore.import_dir("path/to/your/dir")                      # 任意のディレクトリ
```

**取り込みは必ず新規作成です。**同じファイルを2回取り込むと制度が重複します。
やり直すときは先に消してください。

```ruby
KyufyCore::Program.destroy_all   # 要件・出典・チャンクも一緒に消えます
```

### Dockerで動かしている場合

イメージにリポジトリをコピーする作りなので、YAMLを足したらビルドし直すか、
起動中のコンテナにファイルを送って取り込みます。

```bash
docker compose cp db/seeds/programs/your_program.yml api:/app/db/seeds/programs/
docker compose exec api bin/rails runner 'KyufyCore.import_yaml("db/seeds/programs/your_program.yml")'
```

投入処理はDBが空のときしか動かないので、最初からやり直す場合は `docker compose down -v` してください。

### 確認する

```ruby
p KyufyCore::Program.count, KyufyCore::Requirement.count

result = KyufyCore.assess(profile: { age: 40, residence: "三鷹市", household_size: 2,
                                     prior_year_income_jpy: 1_500_000, target: "individual" })
result.each { |r| puts "#{r.program_name}: #{r.verdict}" }
result.first.reasons.each { |x| puts "  #{x[:kind]} #{x[:verdict]} #{x[:citation]}" }
```

---

## よくある詰まり方

| 症状 | 原因 |
|---|---|
| その制度がまったく出てこない | `status` が `inactive` / `valid_until` が過去 / `valid_from` が未来 / `target` がプロフィールと不一致 / 対象地域外 / `categories` で絞り込んでいる |
| 全部「要確認」になる | `raw_text` が空（引用なし → 要確認に落ちる）、`kind: other` ばかり、住所が正規化できていない（→ 上の地理テーブル） |
| 「該当」が1件も出ない | 上に加えて、`value` の形が演算子と合っていない（例：`lte` なのに `threshold` がない）。合っていない場合は判定不能＝要確認になります |
| 取り込みでバリデーションエラー | `jurisdiction: municipality` なのに `municipality_code` がない / `category` が5種類以外 / `official_url` がない |
| 制度が重複して表示される | 同じファイルを2回取り込んだ。`KyufyCore::Program.destroy_all` してやり直す |
| コードが `"01100"` ではなく `1100` になる | YAMLで数値として書いている。**必ずクォートで囲んで文字列に**してください |

---

## 追加前のチェックリスト

- [ ] 出典は公式ページか（まとめサイト・ニュース記事ではないか）
- [ ] `fetched_at` を入れたか（制度は年度で変わります）
- [ ] `raw_text` は逐語コピーか（要約していないか）
- [ ] コード類はすべて文字列（クォート付き）か
- [ ] `license` は、実際に確認できた内容か（不明なら `null` のまま。**推測で書かない**）
- [ ] `valid_until` は公式ページの申請期限と一致しているか
- [ ] 判定できない条件を `other` として残したか（黙って落とさない）
- [ ] 実際に `assess` して、意図した判定になったか

---

## ライセンスについて（重要）

追加した要綱本文は、**その自治体・省庁の著作物**です。このgemのMITライセンスは
コードにかかるもので、あなたが追加した引用文には及びません。

- 公開するサービスに要綱本文をそのまま載せてよいかは、出典ごとに確認してください。
- 「政府標準利用規約」「CC BY」等が明示されていればその旨を `license` に書きます。
- 明示がなければ `license: null`（不明）のままにします。**「書いていない＝自由」ではありません。**
- 安全側に倒すなら、判定結果には公式URLを併記し、原文は出典側で読んでもらう作りにします。

詳しくは [data/README.md](../data/README.md) の「Provenance and licensing」を参照してください。
