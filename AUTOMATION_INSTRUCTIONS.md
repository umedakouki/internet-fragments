# 余白採集室 日次運用指示

## 目的

インターネット上のあらゆるものを、日付ではなく育ち続けるジャンルへ収集する。写真、イラスト、文章、ウェブページ、動画、音声、コード、データ、文書、ゲーム、投稿、メタデータだけの記録など、媒体は限定しない。並べたときの比較可能性と、出典・権利条件を追跡できることを優先する。

## 毎回最初に確認するもの

1. この指示書
2. 自動化メモ
3. `git status --short --branch`
4. `data/genres/index.json` と対象ジャンルJSON
5. 直近の日記と公開サイト

既存の未コミット変更を勝手に戻さない。当日分が公開済みでも、必要な修復や質のある追補がなければ重複作業をしない。

## 日次処理

毎回、次のうち1つを主作業として選ぶ。

- 既存ジャンルを深掘りする
- 新ジャンルを設ける
- 標本をより適切な主ジャンルへ移す
- ジャンルを統合する
- ジャンルを非公開アーカイブにする

新ジャンルは10〜50件で開始する。既存ジャンルの追補に最低件数はなく、質のある1件だけでもよい。ジャンル全体の件数上限は設けない。

収集できないテーマは、試した検索、失敗原因、再試行方法を当日の日記へ `frozen` と記録し、別テーマまたは別作業へ移る。HTTP 429や一時的な5xxでは待機を増やして再試行し、短時間の連続試行やTLS検証の無効化はしない。

## データ

- 索引: `data/genres/index.json`
- ジャンル: `data/genres/{genreId}.json`
- 日記: `diary/YYYY-MM-DD.md`
- 再配布可能な資産: `assets/collections/` 以下。既存パスは日付形式のままでよい

ジャンルIDは小文字英数字とハイフンで安定させ、題名変更後も変えない。ジャンルには `id`、`title`、`subtitle`、`description`、`method`、`status`、`tags`、`relatedGenres`、任意の `mapPosition`、`representativeItemId`、`createdAt`、`updatedAt`、`history`、`itemCount`、`items` を持たせる。

標本は1つの主ジャンルだけに置き、横断関係は複数の `tags` で表す。標本には少なくとも `id`、`title`、`family`、`curatorNote`、`sourceUrl`、`mediaType`、`tags`、`license` または `rights` を持たせる。保存資産がある場合は作者名と `localAsset` または互換用の `localImage` も記録する。

`mediaType` は `image`、`video`、`audio`、`text`、`link` のいずれか。再配布できない、容量が大きい、取得制限がある資料は複製せず、必要最小限の抜粋・説明・プレビュー・メタデータと原典リンクだけを保存する。歌詞、書籍、記事などを全文転載しない。

## ジャンルの関係と状態

- 自動関係は共通タグから生成する
- 編集上の関係は `relatedGenres` に記録する
- 配置補正が必要な場合だけ `mapPosition: { x, y }` を0〜100で記録する
- 非公開にする場合は `status: archived` とし、索引には残す
- 統合する場合は旧項目を `status: merged`、`redirectTo` 付きで残す
- 作成、追補、移動、分離、統合、非公開化はジャンルの `history` と当日の日記の両方へ追記する

`?genre={genreId}` を正規URLとする。既存の `?collection=YYYY-MM-DD` は `legacyCollections` から対応ジャンルへ転送し、過去リンクを壊さない。

## 取得と整理

- APIは可能な限り一括取得し、ファイル取得だけを直列化する
- 取得済みファイルは再取得せず、中断後に再開できるようにする
- ID、原典URL、権利条件、作者、取得日、媒体情報を原典から確認する
- 重複、リンク切れ、出典不明、機械生成スパム、個人情報、違法性や誤解の危険が高い資料を除外する
- 一時ファイル、ブラウザープロファイル、スクリーンショットは `output/` に置き、成功後に不要なら削除する
- 日付専用のJSONや収集スクリプトを新設しない。再利用価値のある処理だけをジャンル名または汎用名で残す

Windows PowerShell 5で日本語スクリプトを実行する場合:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/run-utf8.ps1 -Path scripts/example.ps1
```

## 検証

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/validate-genre.ps1 -All
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/validate-genre.ps1 -Genre genre-id -CheckLinks
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-site.ps1 -Genre genre-id
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-pages.ps1 -Genre genre-id
```

機械検証では、ジャンルID・状態・タグ・関連先・転送先・履歴順・日記・代表資料・件数・主所属・全棚横断のID／原典重複・ローカル資産・媒体・権利情報を確認する。

実ブラウザーでは、PCと390pxで漂流マップ、タグ強調、ランダム選択、棚を開く、隣の棚、一覧切替、直接URL、旧日付URL転送、戻る・進む、媒体フィルター、詳細表示、原典リンク、横溢れ、JavaScriptエラーを確認する。`prefers-reduced-motion` でも操作可能であることを確認する。

## 公開

検証済みの意図した変更だけをコミットし、`main` へプッシュする。`gh` がPATHにない場合は `.tools/bin/gh.exe` を使う。Pages完了後、公開URLから次をHTTP 200で取得して内容も確認する。

- HTML
- `data/genres/index.json`
- 変更したジャンルJSON
- 代表資産または、メタデータのみの棚では代表原典リンク
- 旧日付URLの転送表示

失敗した工程は原因、実施した修復、次回の再試行方法を日記に残す。作業ツリーに意図した変更だけがあることを最後に確認する。
