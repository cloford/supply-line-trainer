# リリース手順

## v2.0.0の大型変更

更新説明と配布内READMEの先頭へ「個人設定のみ引継ぎ、新育成開始」を明記する。旧`save_v1.json`は上書きせず日時付き保全、新方式は`save_v2.json`。旧進行・履歴を混ぜず、既存のセーブを削除するよう案内しない。通常EXEと配布PCKで隔離セーブを使い、実ユーザーの記録を公開しない。[v2フィードバック](https://github.com/cloford/supply-line-trainer/discussions/8)をゲーム・README・リリースで共用する。

## Windows版の作成

1. `project.godot` を Godot 4.7.2 stable で開き、リリース対象のバージョンと `CHANGELOG.md` を確認する。
2. Windows Desktop プリセットでリリースビルドを書き出す。`export_presets.cfg` の出力先は `../build/SupplyLineTrainer.exe`。Godot は `.pck` も同じ場所へ出力する。
3. 作業用の空フォルダーへ `SupplyLineTrainer.exe` と `SupplyLineTrainer.pck` を置き、ZIP直下または一つだけのルートフォルダー内へ入れて圧縮する。同階層の説明は `.md`／`.txt` のみとし、画像・テスト・セーブ・サブフォルダーを配布ZIPへ含めない。ZIP名は `SupplyLineTrainer_Windows_v<version>.zip`（例：`SupplyLineTrainer_Windows_v1.9.0.zip`）。
4. 作成したZIPのSHA-256を記録し、ZIPを展開してEXEとPCKが揃うことを確認する。

PowerShellでのハッシュ確認例：

```powershell
Get-FileHash -Algorithm SHA256 .\SupplyLineTrainer_Windows_v1.4.0.zip
```

## GitHub Release

1. タグを `v<version>` 形式で作成し、同じタグの正式版GitHub Releaseを作る。プレリリースにはしない。
2. ZIPを唯一の配布アセットとしてアップロードする。アセット名はZIP名と一致させる。
3. GitHubが表示するアセットのSHA-256 digest（`sha256:<64桁の小文字16進数>`）を確認し、手元で計算した値と照合する。値が一致しない、digestが表示されない、またはファイル名が違う場合は公開を完了扱いにしない。
4. リリース本文に変更点と必要な手動導入手順を記載する。公開後、正式版のリリース情報、ZIP、サイズ、digestが揃っていることを確認する。

## v1.4.0の初回手動導入

v1.4.0は一度だけ手動で導入してもらう。GitHub Releasesから `SupplyLineTrainer_Windows_v1.4.0.zip` を取得し、既存インストールを上書きせず、新しいフォルダーへ展開して起動する。以後の更新はゲーム内の更新機能を利用できる。

進行データはゲームフォルダーではなくGodotのユーザーデータ領域に保存される。v1.4.0では旧採点記録の移行前に `save_before_v1_4.json` を作成し、新しい採点記録へ分離する。導入案内では、移行のため初回起動前に既存のセーブファイルを削除・移動しないよう伝える。バックアップの作成に失敗した場合、ゲームは保存を停止する。

## バージョン別フィードバック

現在、専用カテゴリは作成されておらず、GitHub Discussions の General を利用する。既存スレッドは[v1.3.0](https://github.com/cloford/supply-line-trainer/discussions/1)と[v1.4.0](https://github.com/cloford/supply-line-trainer/discussions/2)。新しいリリースの案内を作る前に Discussions 一覧で同じバージョンの既存スレッドを確認し、重複作成を避ける。

各バージョンの案内スレッドは変更点、既知の制約、再現手順に含めてほしい情報を記載する。リリース本文とREADMEから同じスレッドへリンクする。ゲーム内の「意見を送る」ボタンは `main.gd` の `feedback_url` をそのバージョンのスレッドURLへ更新する。作成できない場合は完了と報告せず、必要な権限や利用者の操作を具体的に示す。
