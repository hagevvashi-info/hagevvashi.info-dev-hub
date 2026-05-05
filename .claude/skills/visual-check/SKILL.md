---
name: visual-check
description: ブラウザ表示が伴うファイル（.css, .html, .js, .jsx, .ts, .tsx など）の実装・修正時に**必ず使う**ビジュアル実装チェックワークフロー。実装完了後、ユーザーに提示する前に Playwright でスクリーンショットを撮り、達成基準を満たすまで実装・確認を繰り返す。**新規作成・既存修正どちらも対象**。
disable-model-invocation: false
---

# ビジュアル実装チェック

ブラウザ表示が伴うファイル（.css, .html, .js など）の実装・修正依頼を受けたとき、**必ずこのワークフローで進めること**。

## 対象となるケース

- HTML/CSS/JS ファイルの新規作成
- 既存のスタイル・テンプレートファイルの修正
- ブラウザで動作する機能の追加（PDF生成ボタン、モーダル、アニメーションなど）
- **実装後、ユーザーに提示する前に必ず Playwright で視覚確認すること**

## STEP 0: 対象 URL を特定する

以下の優先順位で対象 URL を決定する。

1. **ユーザーが URL を明示している場合** → そのまま使う
2. **上記で特定できない場合** → ユーザーに確認する

## STEP 1: 現状を Playwright でスクリーンショット確認

以下のコマンドパターンでスクリーンショットを撮影し、現在の表示状態を確認する。

```shell
PLAYWRIGHT_PATH=$(npm root -g)/playwright
node -e "
const { chromium } = require('$PLAYWRIGHT_PATH');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('<対象URL>');
  await page.waitForTimeout(500);
  await page.screenshot({ path: '/tmp/visual_before.png' });
  await browser.close();
})();
"
```

- 必要に応じて `clip` オプションで確認したい箇所をトリミングする
- スクリーンショットを Read で読み込み、**達成基準との差を具体的に言語化する**

## STEP 2: 差を埋めるアプローチを計画・実装

- STEP 1 で確認した差分をもとに、どの CSS プロパティ・値を変更するかを計画する
- 対象ファイル（.css / .html / .tsx など）を Read で読んでから Edit で修正する
- 一度に複数箇所を変えず、**1 つの仮説 → 確認** のサイクルで進める

## STEP 3: 修正後を Playwright でスクリーンショット確認

```shell
node -e "
const { chromium } = require('$PLAYWRIGHT_PATH');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('<対象URL>');
  await page.waitForTimeout(500);
  await page.screenshot({ path: '/tmp/visual_after.png' });
  await browser.close();
})();
"
```

- 修正後のスクリーンショットを Read で読み込み、**達成基準を満たしているか判断する**
- 満たしていれば完了。満たしていなければ STEP 2 に戻る

## STEP 4: STEP 1〜3 を達成基準を満たすまで繰り返す

- 達成基準を満たすまでループする
- **ユーザーへの確認依頼は達成基準を満たした後に行う**
- ユーザーに「確認してください」と投げる前に、必ず自分で Playwright で確認すること
