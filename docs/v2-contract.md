# v2 中核のデータ契約と検証

2026-10-25。対象は測定、プロフィール、台帳、新セーブ、戦闘シミュレーション。入力・標的生成・画面・再現プレイヤー・描画は呼び出し側が担当する。数値の根拠は `SLT_v2_implementation_spec_2026-10-25.md` の初期値であり、人による試遊で最適化済みではない。

## 責務とトランザクション

- `V2Rules`: 調整値、固定測定条件、敵編成。
- `V2Measurement`: 射撃事実、標的イベント、視点の記録。
- `V2Profiles`: 一回の有効測定からの変換、採用・取消・防護購入の候補変更。
- `V2Ledger`: 既存 `TrainingLedger` の累積差分方式を再利用した一意な成果確定。
- `V2Save`: 設定だけの移行、原子的なv2保存、破損保全・直前保存の復旧。
- `V2Combat`: 時刻順の純粋な戦闘。描画は発生イベントを消費し、追加ダメージを与えない。

画面側の変更は `candidate = data.duplicate(true)` →候補変更→ `V2Save.save_data(candidate)` →成功時だけ `data = candidate` とする。採用、取消、購入、出撃切替、台帳精算のいずれも同じ順序を使う。保存失敗時は候補のクレジットや採用を画面へ確定させない。部隊へ入る前に未反映成果を保存し、訓練へ戻る際は購入前残高で上書きしない。

## 武器・測定API

武器は `0=handgun / 1=auto_rifle / 2=burst_rifle`。旧オートライフルIDは維持する。`V2Rules.MEASUREMENT_CONDITIONS` に半径0.42、左右範囲3.8、距離11、移動速度1.8、固定位置 `[0,1.6,0]`、アサルト弾間隔0.1、バースト弾間隔0.085を集中した。標的配置の制約とseedを呼び出し側が実装し、出現事実を保存する。

```gdscript
var measurement = V2Measurement.new()
measurement.begin(weapon, settings, seed, record_id)
measurement.shot(time, hit, q, target_id, origin, direction, end, burst_id, bullet_index)
measurement.target_event(time, "spawn", target_id, {"position": target.position})
measurement.pose(time, camera_origin, camera_rotation)
var pending = measurement.snapshot(elapsed) # 継続可能なチェックポイント
var result = measurement.completed(elapsed, interrupted, settings_changed) # 最終確定
```

3秒カウントダウン後の有効時間を呼び出し側が渡す。一時停止・非フォーカス・訓練中の部隊表示では、この時計を進めない。`completed` は終端操作であり、チェックポイントには使用しない。記録後の射撃を拒否し、繰り返し確定しても結果を変更しない。`snapshot` は未完了のまま複製する。

`record` の主要キーは次のとおり。

|キー|内容|
|---|---|
|`record_id`, `weapon`, `weapon_id`|一意ID、整数武器、文字列武器ID|
|`measurement_version`, `profile_version`|測定条件版と変換版。現在は各1|
|`date`, `elapsed`, `seed`, `conditions`, `settings`|日時、有効秒、seed、条件、個人設定|
|`mode`|`measurement`。自由練習の値からは変換不可|
|`shots`, `target_events`, `poses`, `events`|以下の事実列|
|`shot_count`, `hit_count`, `q_sum`|観測時の集計。プロフィールはshot列から再集計する|
|`completed`, `interrupted`, `settings_changed`, `restored`|有効性の判定材料|
|`valid`, `invalid_reason`|最終確定時の表示用判定・理由|

shotは `{time, type:"shot", sequence, hit, q, target_id, origin, direction, end, burst_id, bullet_index}`。`target_id` は文字列、ベクトルは数値3要素配列。標的イベントは `{time,type,sequence,target_id,state}`。`state` に含まれるVector3/Vector2も再帰的に配列へ変換する。姿勢は `{time,origin,rotation}` で最大30Hz。`events` はshotと標的イベントの挿入順を保持するため、同時刻の「命中→撃破→次の出現」を再ソートしない。

shotの時刻は `[0,60)`、非減少。終了前のバースト実弾だけを残す。1記録の安全上限はshot 12,000、標的イベント24,000、姿勢1,800、統合イベント最大36,000。通常の入力間隔制御は呼び出し側の責務であり、この上限を射撃性能へ適用しない。初期アサルトの最大600発やバーストの重複防止は入力側の制御による。

## プロフィールと育成

`V2Profiles.from_record(record)` は無効なら `{}`。60秒完了、1発以上、同一条件、非復元、対応する測定・変換版が必須。N/H/Qを実弾列から再計算し、`rpm=N`, `p=H/N`, `q=命中弾q平均`, `c=0.30*q` とする。全外れも有効でP/Q/Cは0。時刻を詰めたりRPMへ下限を置いたりしない。

プロフィールは `{weapon,record_id,basic,label,date,rpm,p,q,c,timeline,shot_count,hit_count,interval_mean,interval_sd,profile_version,flavor}`。`timeline` は60秒内の全発射時刻。`basic(weapon)` は基礎兵士で、HG60発、アサルト300発、バースト180発、P0.6、C0.05。整数秒と弾番号から時刻を作り、浮動小数の累積で基礎発射数を変えない。

`data.profiles` と `data.previous_profiles` は各3要素で、空の辞書または `{profile,record}`。採用元記録を通常履歴から独立して保存し、履歴200件を超えても現在・直前の記録は残る。`adopt(data,record)` と `revert(data,weapon)` は候補を変更するだけで報酬や完了数へ触れない。変換版の異なる記録は無言で変換し直さない。保存時も元recordから算出したRPM/P/Q/C/発射列等と保存プロフィールを照合する。

その他のAPIは `current(data,weapon)`、`unlocked(data,weapon)`、`squad_level(data)`、`hp(data,weapon)`、`purchase(data,weapon)`、`set_deployed(data,weapon,enabled)`。

初期HP100。HP式は `100*(1+0.20*測定防具+0.10*防護段階)`。防護は最大5、費用250/500/900/1400/2000。累計0/1000/3000でHG/アサルト/バーストの固定枠を無料解放する。加入・防具に追加費用はない。ロック兵種の購入・出撃切替を拒否する。名前、防護、防具、解放はプロフィール変更で失わない。

フレーバーは10発未満を中立とし、それ以上では間隔の変動係数0.2未満を安定、0.9以上を連射と休止、Q0.8以上かつ90発未満を中心狙い、240発以上を高頻度とする。複数該当時はこの順。説明用の暫定分類で、能力は変更しない。

## 台帳

`V2Ledger.checkpoint(data, record)`、`finish(data,record,status,measurement={})`、`recover(data)` は既存訓練record（`id/weapon/difficulty/duration/elapsed/active/credits/scoring_version/point_fraction`）を扱う。測定は `training_history.entry.measurement` に付加する。15秒および一時停止・終了時の呼び出しは画面側が行う。

所持 `credits` と累計 `lifetime_credits` は十進文字列。累計はcheckpointの所持差分だけを加算する。購入では累計を減らさない。完了ID、兵種ごとの `measurement_counts`、`armor` は、同じ有効測定の終端候補で確定する。IDと武器は訓練recordと一致しなければ完了へ数えない。3回目で恒久防具を無料解放し、4回目でも再支払いしない。

中断復元はrecordが誤ってcompletedを持っていても強制的に `restored=true/completed=false` とする。既存checkpoint分だけを確定し、測定完了へ格上げしない。

通常履歴は200件。`settled_training_ids` と `completed_measurement_ids` は削除せず恒久保持する。履歴削除後に同じIDが再登録されても報酬を再発行しないことを優先する。ID列は記録本体と比べて小さいが件数に比例して増加する。将来圧縮する場合も、一意性を失う古いIDの単純削除を行わない。

## 新セーブと移行

`V2Save.PATH = user://save_v2.json`、一時ファイルは `save_v2.tmp`、直前保存は `save_v2.previous.json`。旧 `save_v1.json` は読込と日時・一意suffix付きバックアップのコピーだけに使用し、書き込まない。

旧進行を初期辞書へコピーしない。感度、基準ゲーム、DPI、FOV、照準、音、更新等の明示allowlistだけを型・有限値・範囲検証して移行する。未知の設定キー、進行、残高、履歴、途中記録は引き継がない。新設定 `effects_enabled` は既定true。UI選択用の `selected_weapon/selected_difficulty/selected_duration/help_seen/v2_notice_seen/selected_measurement` は新規の既定値から開始する。

初回保存成功後は再移行しない。backup/read/createの失敗は `migration_failed=true`, `migration_error`, `retry_possible=true` を返す。画面は理由と再試行を表示し、失敗データを初期状態として上書き保存しない。

保存は候補を複製・検証→一時ファイル書込とflush→再読込検証→現セーブをpreviousへ移動→一時ファイルを現セーブへrenameの順。失敗時はfalseと `last_error` を返す。rename失敗後はpreviousをコピーして現セーブを復旧し、previousも保持する。

ロード時に現セーブが破損していてpreviousが有効なら、破損現セーブを一意ファイル名で保護してからpreviousを復旧する。両方破損なら保存を停止し、理由と再試行可能性を返す。有効な現セーブを壊れた候補で上書きしない。新セーブに残る旧形式の進行を推測して復元しない。

## 戦闘APIと時刻

```gdscript
combat.configure(data, seed) # startも同義
combat.set_data(data) # 次区間へ適用する候補
combat.set_paused(true)
var events = combat.advance(delta)
var display_state = combat.snapshot()
var save_fields = combat.persistent_state()
combat.retry(data) # retreat/idle時のみ
combat.continue_expedition(data) # 第一遠征達成後の任意継続
```

snapshotは `{status,section,time,allies,enemies,expedition_complete}`。sectionは0始まりの未突破区間。statusは `fighting/marching/retreat/idle/complete`。

味方は `{id,weapon,profile,armor,protection,name,hp,max_hp,alive,attack_clock,phase,shot_index,cycle,shots,hits,criticals}`。敵は `{id,kind,max_hp,hp,damage,interval,next_shot,alive}`。武器ごとの独立seedを使い、Pで命中したときだけCを抽選する。クリティカル倍率1.5、通常ダメージHG10/アサルト2/バースト4。命中判定、HP変更、死亡は発射時に確定する。

イベントは `{type,time,section,...}`。shot/hitは `actor_id/weapon/target_id/hit/critical/damage/target_hp/target_alive`。typeは `ally_shot/enemy_shot/hit/march/section/retreat/complete/retry`。`hit` は既に確定した被弾の演出通知で、追加ダメージ源ではない。marchは `front/duration`、completeは `front/expedition_complete`。保存用 `persistent_state()` は `front/battle_status/expedition_complete` を返す。

次の射撃イベントまでの時刻を処理する方式で、fpsから弾数を作らない。同時刻は味方固定枠順→生き残った敵の順。最後の敵を倒した時点で突破を優先し、倒れた敵の同時刻予約攻撃を発生させない。複数の境界通知で突破を二重処理しない。

攻撃時計は敵がいる交戦中かつ生存時だけ進む。先頭・末尾の無発射を含む60秒周期を反復する。敵変更で巻き戻さない。生存しプロフィールが同じなら区間間で時計・カーソルを保持する。新規加入、差替え、次区間復活、再挑戦は0から始める。区間開始で全回復、区間内復活なし。敵全滅後1.2秒歩行し、その間は時計を止める。全員出撃OFFはidleとして手動再挑戦待ち。

`delta>0.25`、停止、無効なdeltaでは時計を進めず、大停止後のまとめ撃ちを防ぐ。自動試験で長時間を積算する場合は通常tickへ明示分割する。実時間の未処理分を後から補填しない。

軽装HP10・攻撃3・2.8秒間隔、重装HP50・攻撃7・3.4秒間隔。敵ごとに0.13秒ずつ初撃をずらす。第一遠征12区間の軽装/重装数は `2/0,3/0,4/0,3/1,5/1,4/2,7/1,6/2,5/3,8/2,7/3,8/4`。継続戦線は合計12人を上限に、軽装を3区間ごとに重装へ置換し、重装上限8とする。敵HP指数増加を使わず、全敵を描画可能な数に収める。これは統合レビュー後の調整で、理由は[調整報告](v2-verification.md)を参照。進軍・敵撃破・達成からクレジットは発生しない。

## 自動検証

Godot 4.7.2、専用 `.test-appdata-v2-core` APPDATA、`SLT_TEST_DATA=1` で `--headless --path . --script v2_core_tests.gd` を実行。テストは専用パスを確認し、実ユーザーのセーブ環境では停止する。78項目、失敗0。

- 手計算N4/H2/Q0.75/RPM4/P0.5/C0.225、0発・全外れ・中心・端、自由練習・未完了・条件変更・復元の除外、終端バースト、同時刻の事実順。
- 30/60/120fpsで発射数・時刻・判定列一致、異seedの差、60秒の初/末の休止、10万試行のP0.6・命中時C0.2の統計一致。
- 大delta・停止・敵不在の時計凍結、区間の採用反映、位相維持、死亡復帰、再挑戦、同時刻の最後の敵撃破。
- 差分精算の重複防止、未採用/全外れの完了、3回目/4回目、復元除外、履歴205件後も現在/直前を保全、再保存・再読込。
- 旧原本ハッシュ不変、allowlist型検証、backup/read/temp/previous/renameの失敗、再試行、初回成功後の移行禁止、破損保全と復旧、元記録と保存プロフィールの不一致拒否。

固定seed55、最大600秒、HGは60発/分でNが変わらない合成記録を用いた進行比較。

|条件|突破済区間|結果|シミュレーション秒|
|---|---:|---|---:|
|基礎ハンドガンのみ|7|撤退|118.31|
|低命中HG P0.2/Q0.7|4|撤退|96.10|
|中命中HG P0.6/Q0.7|7|撤退|120.70|
|高命中HG P0.9/Q0.7|10|撤退|139.36|
|中命中HG＋基礎アサルト＋基礎バースト|12|第一遠征達成|99.60|
|基礎HG＋3回防具＋防護5|9|撤退|190.17|

初期数値は仕様値から変更していない。初期兵士で数区間を体験でき、防護・兵種加入で突破余地が増えることを自動試験で確認した。乱数やタイミング、過剰ダメージの影響を含む単一seedの比較であり、プレイヤーの強さや面白さを確定する結果ではない。中核担当による検証は自動試験のみ。実描画、配布EXE/PCK、入力遅延、音、720p/1080p、人間試遊は統合担当の別工程として扱う。
