# 余白採集室

インターネット上の断片を、日付ではなく育ち続けるジャンルとして収集する静的アーカイブです。各標本は1つの主ジャンルに所属し、タグと編集された関係から別の棚へ漂流できます。写真、イラスト、文章、動画、音声、コード、データなど、出典を追跡できるあらゆる媒体を対象にします。

収集者は日本語で考え、日本の生活、街路、個人サイト、道具、制度、文字文化、インターネット文化から問いを始めます。日本だけに限定せず、翻訳、輸入、移動、技術、歴史、類似した生活習慣を辿って国外の資料へ広がります。外国資料だけの棚でも、日本から何を辿ってそこへ着いたかを記録します。

## 構成

- `data/genres/index.json`: ジャンル索引、状態、旧日付URL対応
- `data/genres/{genreId}.json`: ジャンル情報、標本、更新履歴
- `assets/collections/`: 再配布可能な保存資産。移行前の日付パスを維持
- `diary/`: 日付別の探索・分類・更新記録
- `AUTOMATION_INSTRUCTIONS.md`: 日次運用指示
- `scripts/validate-genre.ps1`: データ検証
- `scripts/verify-site.ps1`: 実ブラウザー検証

## ローカル表示

```powershell
python -m http.server 8000
```

`http://localhost:8000` で漂流マップを表示します。ジャンルの正規URLは `?genre=genre-id`、標本の直接URLは `?genre=genre-id&item=item-id` です。旧 `?collection=YYYY-MM-DD` は対応ジャンルへ転送されます。

## 検証

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/validate-genre.ps1 -All
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-site.ps1 -Genre street-letterforms
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-pages.ps1 -Genre street-letterforms
```

日次作業の完了処理は次の1コマンドにまとめています。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/run-automation.ps1 -Genre street-letterforms -CommitMessage "Update collection" -Publish
```

## 公開先

https://umedakouki.github.io/internet-fragments/

## 権利

キュレーション文とサイトコードを除き、収集資料には各原典の権利条件が適用されます。収集対象にすることとファイルを再配布することは分けて判断します。新規追加または更新する標本では、`rightsStatus` に `clear` / `unknown` / `restricted`、`captureMode` に `stored` / `excerpt` / `linked` を使います。権利者不明はPublic Domainではありません。再配布根拠が確認できない資料は複製せず、短い説明または必要最小限の抜粋、メタデータ、原典リンクだけを記録します。

更新の止まったブログや古いウェブページに残る言葉も、取得時に公開され、個人を傷つける情報を含まず、全文を複製しない場合は `text` または `link` 標本として扱えます。画像、文章、音声、動画、ウェブ、コード、データを同じ比較軸で混在させることもできます。
