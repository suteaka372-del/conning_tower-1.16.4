# Development stats (自動生成)

このブランチは GitHub Actions の「Development stats」ワークフローが毎日作り直します。手で編集しないでください。

- `devstats/YYYY-MM.json` … 月ごとの装備開発の集計
- `devstats/latest.json` … 直近3か月分を合わせたもの (Conning Tower の「開発」タブが使う)

元データ: [poi](https://github.com/poooi/poi-server/wiki) の公開データ `createitemrecords`
(poi・KC3改・Kcanotify の利用者が報告した開発結果)。

形式: `rows` = `[燃料, 弾薬, 鋼材, ボーキ, 秘書艦の艦ID, 試行回数, [装備ID, 出た回数, ...]]`

## airsim (制空権シミュレーター用)

- `airsim/abyssal.json` … 深海棲艦の素の対空値と搭載数 (`ships` = `{ 艦ID: [対空, [搭載数...]] }`)

元データ: [KC3Kai/kancolle-replay](https://github.com/KC3Kai/kancolle-replay) の `js/kcSHIPDATA.js` (MIT License, Copyright (c) 2016 fourinone41)。
