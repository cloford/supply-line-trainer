# 0.21 進行・実績・保存と版番号の契約

## 解放の正本

`Progression` が五武器の名称、安定ID、条件、実績文言を管理する。練習の解放条件はハンドガン0、アサルトライフル10、バーストライフル100、マークスマンライフル500、グレネードランチャー1,500の累計「撃破・追従達成」。兵士三枠の加入条件である従来の累計クレジットは変更しない。実績によるクレジット報酬・能力倍率はない。

- `Progression.total(data)` は累計達成数。
- `Progression.unlocked(data, weapon)` は練習の利用可否。
- `Progression.weapon_rows(data)` は解放済み全武器と直近の未解放一つ。行は `id` / `weapon`（整数0〜4）、`weapon_id`（安定文字列）、`name`（未解放は `???`）、`unlocked`、`threshold`、`current`、`remaining`、`icon` を持つ。全解放後は未解放行を残さない。
- `Progression.achievements(data)` は全実績定義に `title`、`unlocked`、`unlocked_at` を付けて返す。
- `Progression.pending_notifications(data)` は解除済み・未読の実績のみ。`id`、`title`、`description`、`unlocked_at` を持つ。
- `Progression.mark_seen(candidate, id)` は通知の既読のみ変更する。解除状態は別に保持する。
- `Progression.list_visible(data)` は累計5以上、または既存者の一覧維持状態で真。
- `Progression.mark_list_seen(candidate)` は一覧の初回演出既読 `progression.list_seen` を保存候補へ記録する。

実績IDは `first_kill`、`five_progress`、`unlock_auto_rifle`、`unlock_burst_rifle`、`unlock_marksman_rifle`、`unlock_grenade_launcher`。最初の撃破実績は実際の撃破一体で解除し、追従だけでは解除しない。追従による達成も5達成・武器解放の条件に使う。

## セッション入力と確定

既存セッションに以下の累計値を追加する。発射数・命中率・兵士プロフィール用の値とは別に管理する。

```gdscript
record.progress_kills = kills_in_this_session # 非負整数、標的一体につき一回
record.progress_tracking_seconds = valid_tracking_in_this_session # 標的上の有効追従秒
record.progress_measurement = is_measurement
```

AR（武器1）は追従秒のみ、その他の武器は撃破のみを採用する。追従秒の総和の整数部分が達成数であり、端数はセッションをまたいで保存する。ARの通常標的の撃破と追従を重複加算しない。GLで一発三体を倒した場合は撃破3であり、発射数は1のまま。

`V2Ledger.checkpoint` は自由練習の累計入力と前回の保存済み `active_training` との差分を反映する。撃破時およびAR達成境界でゲーム側がチェックポイントを保存する。終了時は最後の差分だけを反映する。`settled_training_ids` にある記録は再精算しない。

測定のチェックポイントは進行を仮記録するだけ。`V2Ledger.finish` が60秒の同一条件測定を `V2Profiles.from_record` で検証し、記録ID・武器の一致を確認してから全量を一回確定する。中断・条件変更・復元・無発射は確定しない。測定中の武器や条件を自動変更しない。

再現・プレビュー・試射・自動戦闘からは通常この入力を渡さない。中核側でも `progress_excluded=true`、または `mode` が `replay` / `preview` / `demo` / `battle` / `test_fire` の記録は加算しない。

ゲーム側は `data.duplicate(true)` を候補として精算し、`V2Save.save_data(candidate)` に成功したときだけ実データへ採用する。失敗時は候補とセッション累計を保持して再試行する。通知へ渡す解除情報も保存済みデータから取る。通知既読を候補へ保存してからUIキューへ渡すことで、再起動の再通知を防ぐ。

## 既存セーブ

保存パスは `user://save_v2.json`、保存版は従来どおり2。育成・プロフィール・名前・クレジット・設定・三兵士枠をリセットしない。追加するのは `progression` オブジェクト。旧v1からv2への従来の設定限定移行は変更しない。

既存v2で `progression` がない場合だけ一度移行する。同じ記録IDの履歴・保存中セッションを重ねて数えず、`stats.kills` / `metrics.kills` と `stats.track_time` / `metrics.track_time` に存在する非負で有限の事実を採用する。命中数・発射数・得点・クレジットから撃破を推測しない。測定記録は従来の有効測定検証を通った場合だけ集計する。履歴上限のため既に失われた記録を復元・推測しない。

既存三武器は、履歴・保存中セッション・採用/前回プロフィール・有効測定回数が示す利用事実がある武器の利用可能状態を保存する。解放条件の達成数を架空に付与しない。移行による実績は解除済み・通知既読として保存し、大量の初回バナーを避ける。移行解除日時は移行日時であり、過去の実際の解除日時を推測した値ではない。

保存は従来の一時ファイル検証、直前セーブ保全、リネーム確定を使う。新しい進行オブジェクトも検証し、破損時は既存の保護・復旧経路を使う。

## 版番号

`ReleaseVersion` が表示と更新比較の正本。公開版は `0.21`、内部表記が必要な箇所は `0.21.0` を明示的に同義とする。

旧体系（例1.x.y / 2.x.y / 三要素の旧0.x.y）を世代0、新しい二要素 `0.21` 以降を世代1とする。世代比較を優先し、同じ世代内は整数配列で比較する。0.29の次は0.30、旧2.0.0より新0.21が優先される。新体系から旧体系へ戻らない。

任意の `0.x.y` を新体系とみなさない。今回未使用の `0.21.0` だけを明示した内部同義とし、将来版の公開タグは二要素の `v0.22` 等を使う。将来内部三要素表記が必要なら、その版の定義も明示的に更新する。

0.21の公開タグは `v0.21`、配布名は `SupplyLineTrainer_Windows_v0.21.zip`。既存タグ・配布物を上書きしない。

既に配布済みの旧アップデーターは書き換えられない。旧版は三要素のみ受け付けたり、2.0.0→0.21を更新と認識しないため、0.21のZIPをGitHub Releasesから手動でダウンロードして展開し、ゲームを終了してから新しい実行ファイルで起動する。ユーザーデータフォルダーは同じなので、既存v2の育成・設定を引き継ぐ。0.21以降のアップデーターは新体系の比較に対応する。

## 中核の自動検証

隔離APPDATAと `SLT_TEST_DATA=1` で `progression_tests.gd`、`release_version_tests.gd`、`updater_tests.gd` を実行する。境界1/5/9/10/100/500/1,500、AR端数、測定仮記録/有効確定、除外モード、保存失敗と再試行、再読込、旧履歴ID重複、実績既読、既存武器維持、世代比較、ZIP名と通信・ダイジェスト検証を扱う。描画・試遊はゲーム統合側の別検証とする。
