# Aim Runner 0.23の演出部品

`IrisIntro`は全領域を覆う入力透過のControl。`start_wait(screen_pos, radius_pixels)`で標的付近だけを円形に見せ、最初の実撃破で`open_from(screen_anchor, effects_enabled)`を呼ぶ。開口時に中心を固定し、`advance(delta, active)`は停止・非フォーカス時に進めない。`skip()`は完了通知付き、`clear()`は通知なしで除去する。開口は0.78秒、強い演出が無効なら0.24秒。シェーダーはviewport内のピクセル距離で円を計算し、リサイズ時も中心の相対位置と表示比率を維持する。

`SpawnAudio`は`_ready()`で短い自作合成のポン音を生成する。再生は`spawn_at(position)`だけで、同一描画フレームの複数呼び出しを一度にまとめる。`configure(settings)`は`effects_enabled`、全体の`volume`、既存の`shot_volume`を参照する。生成時に再生せず、追従標的の位置更新からも呼ばない。実銃の録音や外部素材は使用していない。

`V2Interface.set_weapon_button(button, weapon, unlocked, selected, display_text)`は未解放選択肢を???と解放条件・黒いシルエットで表示する。アイコンのControlはマウス入力を受けず、文字領域を別に確保する。

既存の`progression_view_tests.gd`へ、待機・開口・停止・スキップ・リサイズ、未解放名とアイコン、音源生成・無音・同フレーム集約の検査を追加した。統合後の実描画・保存・検証範囲と、実音声の聞こえ方などの未確認事項は[配布版の検証報告](023-verification.md)を参照。
