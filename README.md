# 余白採集室

インターネット上に多数存在するものの、まだ明確な収集ジャンルになっていない断片を、日ごとに10～50件保存して紹介する静的ウェブサイトです。

## 構成

- `data/collections/`: 日付別のコレクションデータ
- `data/collections/index.json`: 公開済みコレクションの索引
- `assets/collections/`: 保存画像
- `diary/`: 探索と分類の判断を記録した日記
- `AUTOMATION_INSTRUCTIONS.md`: 日次作業の運用指示
- `scripts/`: 取得・整形用スクリプト

## ローカル表示

```powershell
python -m http.server 8000
```

`http://localhost:8000` を開いて確認します。

特定日のコレクションは `?collection=YYYY-MM-DD` で直接表示できます。

## 公開先

https://umedakouki.github.io/internet-fragments/

## 権利

キュレーション文とサイトコードを除き、収集画像には各原典のライセンスが適用されます。作者、ライセンス、原典URLは各標本の詳細画面とJSONデータに記録しています。
