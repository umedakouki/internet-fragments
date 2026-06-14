# 余白採集室

インターネット上の断片を、日付ではなく育ち続けるジャンルとして収集する静的アーカイブです。各標本は1つの主ジャンルに所属し、タグと編集された関係から別の棚へ漂流できます。写真、イラスト、文章、動画、音声、コード、データなど、出典を追跡できるあらゆる媒体を対象にします。

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

`http://localhost:8000` で漂流マップを表示します。特定ジャンルの正規URLは `?genre=genre-id` です。旧 `?collection=YYYY-MM-DD` は対応ジャンルへ転送されます。

## 検証

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/validate-genre.ps1 -All
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-site.ps1 -Genre street-letterforms
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-pages.ps1 -Genre street-letterforms
```

## 公開先

https://umedakouki.github.io/internet-fragments/

## 権利

キュレーション文とサイトコードを除き、収集資料には各原典の権利条件が適用されます。再配布できない資料は複製せず、短い説明や抜粋、メタデータと原典リンクだけを記録します。
