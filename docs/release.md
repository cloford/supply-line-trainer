# Aim Runner 0.2.6の配布

直前の配布版からのゲーム内更新を今後のWindows公開の必須条件とする。配布候補を隔離して差し替え、再起動、セーブ保持、旧ファイルの保全を確認する。公開後は実際のリリースAPI・ZIPを使って再確認する。[検証](026-verification.md) ／ [開発時のルール](../AGENTS.md)

## 0.2.5の配布記録

タグは `v0.2.5`、ZIPは `SupplyLineTrainer_Windows_v0.2.5.zip`。0.25からはゲームを終了し、ZIP全体を別フォルダーへ展開してEXEを起動する。既存の保存先をそのまま使用する。[検証・実画像](025-semver-verification.md) ／ [Discussion #18](https://github.com/cloford/supply-line-trainer/discussions/18)

## 0.25の配布記録

Tab中の練習変更、指の初回誘導、標的編集と自由練習の配点、アイコンUI、確認付き初期化を反映するWindows版です。新規タグv0.25、ZIPは`SupplyLineTrainer_Windows_v0.25.zip`。過去のタグ・配布物を上書きしません。

[検証・調整値・画像・未確認事項](025-verification.md) ／ [版別の配布・Discussion](versions.md)。通常の更新はセーブを保持します。工具内の全データ初期化は任意の検証用操作で、個人設定も戻します。

## 0.24の配布記録

起動をHG無限自由練習へ直結し、自動開口・3秒表示・非同期の一時停止保存を反映したWindows版です。新規タグv0.24、ZIPは`SupplyLineTrainer_Windows_v0.24.zip`。過去のタグ・配布物を上書きしません。

[検証・画像・未確認事項](024-verification.md) ／ [CPUの前後計測](024-performance.md) ／ [配布EXEの照合結果](024-release-exe.json)。外部画面操作へ依存せず、同一EXEと未変更製品PCKを検証ラッパーで確認しました。OS物理入力とは区別します。

## 0.23の配布記録

命中時の停止原因計測、保存要求の集約、初回の円形開口・出現音・新規武器ロックを反映したWindows版です。タグはv0.23、配布ZIPは`SupplyLineTrainer_Windows_v0.23.zip`。既存v2のセーブを保持します。

[検証・未確認事項](023-verification.md) ／ [修正前後の計測](023-performance.md) ／ [版ごとの配布・Discussion](versions.md)。公開後のAPI/CDN取得とハッシュ一致も記録します。旧版を上書きせず新しいタグ・配布として公開します。

## 0.22の配布記録

製品名をAim Runnerへ変更。配布・更新互換用のEXE/PCK/ZIP名とGitHub URL、既存セーブ保存先は維持します。新規公開タグはv0.22です。

[版ごとの配布・更新内容・Discussion](versions.md)。公開ごとに新規タグと専用Discussionを用意し、既存配布を上書きしません。公開後はAPI/CDN実ダウンロード・ハッシュ・最新表示を確認します。

# リリース手順

## 0.21以降の公開番号と更新

公開表記0.21、タグ`v0.21`、ZIP`SupplyLineTrainer_Windows_v0.21.zip`。次は0.22、0.29の次は0.30。`ReleaseVersion`の新旧世代と整数連番を使い、古い番号体系の配布を最新へ戻さない。既存タグ・配布物を上書きしない。

旧1.x／2.xの公開済みアップデーターは新番号を認識できず、0.21はゲーム終了後にZIPを別フォルダーへ手動展開する。**既存v2の育成・設定・プロフィールはリセットしない。セーブを削除させない。** アセット名・サイズ・digest・latestを確認する。ゲーム内の0.21フィードバックは`next_game.gd`から[Discussion #9](https://github.com/cloford/supply-line-trainer/discussions/9)へ接続する。

## v2.0.0の大型変更

更新説明と配布内READMEの先頭へ「個人設定のみ引継ぎ、新育成開始」を明記する。旧`save_v1.json`は上書きせず日時付き保全、新方式は`save_v2.json`。旧進行・履歴を混ぜず、既存のセーブを削除するよう案内しない。通常EXEと配布PCKで隔離セーブを使い、実ユーザーの記録を公開しない。[v2フィードバック](https://github.com/cloford/supply-line-trainer/discussions/8)をゲーム・README・リリースで共用する。

## Windows版の作成

1. `project.godot` を Godot 4.7.2 stable で開き、リリース対象のバージョンと `CHANGELOG.md` を確認する。
2. Windows Desktop プリセットでリリースビルドを書き出す。`export_presets.cfg` の出力先は `../build/SupplyLineTrainer.exe`。Godot は `.pck` も同じ場所へ出力する。
3. 作業用の空フォルダーへ `SupplyLineTrainer.exe` と `SupplyLineTrainer.pck` を置き、ZIP直下または一つだけのルートフォルダー内へ入れて圧縮する。同階層の説明は `.md`／`.txt` のみとし、画像・テスト・セーブ・サブフォルダーを配布ZIPへ含めない。ZIP名は `SupplyLineTrainer_Windows_v<version>.zip` とし、公開する版番号へ揃える。
4. 作成したZIPのSHA-256を記録し、ZIPを展開してEXEとPCKが揃うことを確認する。

PowerShellでのハッシュ確認例：

```powershell
Get-FileHash -Algorithm SHA256 .\SupplyLineTrainer_Windows_v2.0.0.zip
```

## GitHub Release

1. タグを `v<version>` 形式で作成し、同じタグの正式版GitHub Releaseを作る。プレリリースにはしない。
2. ZIPを唯一の配布アセットとしてアップロードする。アセット名はZIP名と一致させる。
3. GitHubが表示するアセットのSHA-256 digest（`sha256:<64桁の小文字16進数>`）を確認し、手元で計算した値と照合する。値が一致しない、digestが表示されない、またはファイル名が違う場合は公開を完了扱いにしない。
4. リリース本文に変更点と必要な手動導入手順を記載する。公開後、正式版のリリース情報、ZIP、サイズ、digestが揃っていることを確認する。

## バージョン別フィードバック

新しいリリースごとに同じ版のDiscussionが存在するか確認し、既存なら再利用する。ゲーム内・README・リリースから同じスレッドへリンクし、変更点、既知の制約、再現手順に必要な情報を記載する。

## 履歴と作業ファイル

以前の配布手順や検証資料は対応するGitタグから参照する。作業ツリーへ旧版のコピーを増やさない。撮影出力、隔離テストのセーブ、ビルド成果物はGit管理対象外とし、配布ファイルはGitHub Releaseへ添付する。現行の素材表記と必要なテストは保持する。
