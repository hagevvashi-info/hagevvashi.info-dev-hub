---
name: csv-parse
description: CSVファイルをパースして中身を確認・分析する。`*.csv` ファイルを読み取る際に使用する。入力として `*.csv` ファイルパスを受け取るリクエストや、ファイル検索で `*.csv` ファイルが見つかった際に使用する。
disable-model-invocation: false
---

# CSV Parse Skill

## Overview

このスキルは、DuckDBのCLI機能を使用して、ローカルのCSVファイルをSQLで高速かつ効率的に読み取り・分析するための手順を定義します。

## Instructions & Best Practices

CSVファイルの解析を求められた場合、以下のステップとコマンド例に従ってDuckDBを使用してください。

### 1. 構造の把握（プレビュー）

最初から全件を読み込んでトークンを消費するのではなく、まずは数行を抽出してカラム名やデータ型を把握してください。

```shell
duckdb -c "SELECT * FROM '対象のファイルパス.csv' LIMIT 5;"
```

### 2. データの集計・フィルタリング

全体の構造を把握した後、ユーザーの要求に応じてSQLを活用し、必要なデータのみを抽出・集計します。

```shell
# 例: 特定の列でグループ化し、件数が多い順に10件取得する
duckdb -c "SELECT column_name, COUNT(*) as count FROM '対象のファイルパス.csv' GROUP BY column_name ORDER BY count DESC LIMIT 10;"
```

### 3. イレギュラーなCSVへの対応（エラー時のフォールバック）

列数が行ごとに異なるなど、RFC規格に沿っていない不規則なCSVファイルで読み込みエラーが発生した場合は、read_csv 関数と null_padding=true オプションをフォールバックとして使用してください。

```shell
duckdb -c "SELECT * FROM read_csv('対象のファイルパス.csv', null_padding=true) LIMIT 5;"
```

## 制約事項 (Constraints)

**読み取り専用**: 破壊的な操作（UPDATEやDELETEなど）は行わず、データの確認と抽出（SELECT）のみに使用すること。

**エスケープ処理**: ファイルパスにスペースや特殊文字が含まれる場合は、必ずシングルクォーテーション(')で囲むこと
