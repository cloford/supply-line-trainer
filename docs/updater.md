# Windows 自動更新

Windows 配布版では起動時に GitHub の正式な最新版を確認し、新しい版があれば練習を続けながら ZIP を取得します。「再起動して更新」を押すと保存後にゲームが終了し、本体を入れ替えて再起動します。開発用のエディター実行・ソース実行では更新しません。

取得先は `cloford/supply-line-trainer` の正式リリースにある `SupplyLineTrainer_Windows_vVERSION.zip` です。数値の `major.minor.patch` で新旧を比較し、プレリリース、ダウングレード、GitHub API の SHA-256 がないファイルは適用しません。HTTPS の GitHub 配布 URL と GitHub の配布 CDN だけを許可し、サイズ・SHA-256・ZIP 内のパス・展開後のサイズを検証します。ZIP は本体 EXE と PCK、および同じ階層の `.txt` / `.md` のみを許可し、適用するのは本体2ファイルだけです。

更新データとバックアップは `user://updates/<ランダムなトークン>/` に残します。現在のゲームの実行ファイルとプロセスハンドルを確認して終了を待ち、更新操作の確認トークンがある場合だけ適用します。旧本体は配置先でも `.previous-<トークン>-<ファイル名>` に変更して保持し、開いている旧ファイルへの上書きを避けます。復元時に新本体があれば `.failed-<トークン>-<ファイル名>` に退避します。セーブデータには触れません。管理者権限やプロセスの強制終了、自動削除は使いません。

新しいゲームは起動完了時にトークンとバージョンを返します。起動できない・確認前に終了した場合は旧本体に戻して起動します。30秒以内に起動確認がなく、まだ新しいゲームが動いている場合は強制終了せず `result.json` に `manual-recovery` を記録します。その場合はゲームを閉じてから、同じフォルダーの `backup/SupplyLineTrainer.exe` と `.pck` をゲームの配置先へコピーしてください。権限不足などで復元できない場合もバックアップを残します。Windows の保護機能や PowerShell の実行制限で動かない場合は手動で配布 ZIP を展開して更新できます。

## 組み込み

`updater.gd` をプリロードして Node として追加します。起動後に `check(true)` を呼ぶと新しい版を自動取得します。`status_changed(message)` で表示を更新し、`ready_changed(ready)` と `ready_to_apply` で再起動ボタンを制御します。手動取得の場合は `check(false)` のあと `download()` を呼びます。`release_version` は更新先のバージョンです。

保存を完了してから `apply_update()` を呼んでください。ゲームの初期化が成功した箇所で `SupplyLineUpdater.acknowledge_update()` を呼び、更新後の起動を確認します。更新状態は `status` でも参照できます。エクスポート設定の `include_filter` に `update_apply.ps1` を含める必要があります。

検証は Godot の `--headless --path . --script updater_tests.gd` で実行できます。`update_apply.ps1` は同じユーザー権限で動く補助プログラムです。GitHub の配布元とローカルユーザーを信頼する設計であり、署名検証や管理者向け配布管理の代替ではありません。
