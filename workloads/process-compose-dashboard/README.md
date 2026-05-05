# Process Compose Dashboard

Process Compose の Web ダッシュボード実装です。

## 📋 概要

Nginx + 静的HTMLによる`process-compose`のWebベースのダッシュボードです。
リアルタイムログストリーミング、プロセス管理、テキスト選択・コピーが可能です。

## 🎯 機能

### 1. ダッシュボード (`index.html`)
- 各機能へのナビゲーション
- APIエンドポイント情報

### 2. ログビューア (`logs.html`)
- WebSocketによるリアルタイムログストリーミング
- テキスト選択・コピー可能
- タイムスタンプ表示
- 自動スクロール
- 接続時間カウンター

### 3. プロセス管理 (`processes.html`)
- プロセス一覧表示
- プロセスの起動/停止/再起動
- CPU/メモリ使用状況表示
- 自動更新（5秒ごと）

## 🏗️ アーキテクチャ

```
ブラウザ (http://localhost:4802)
    ↓
Nginx (ポート4802, supervisordで管理)
    ↓
    ├── /        → 静的HTML (/var/www/process-compose-dashboard/)
    ├── /api/*   → proxy_pass → process-compose:4040
    └── /ws/*    → proxy_pass → process-compose:4040 (WebSocket)
```

## 📁 ディレクトリ構成

```
workloads/process-compose-dashboard/
├── README.md                           # このファイル
├── nginx/
│   └── process-compose-dashboard.conf  # Nginx設定
└── html/
    ├── index.html                      # ダッシュボード
    ├── logs.html                       # ログビューア
    └── processes.html                  # プロセス管理
```

## 🔧 技術仕様

### バインドマウント

このディレクトリの内容は、docker-compose.ymlでバインドマウントされます：

```yaml
# Nginx設定
- type: bind
  source: ../workloads/process-compose-dashboard/nginx/process-compose-dashboard.conf
  target: /etc/nginx/sites-enabled/process-compose-dashboard.conf
  read_only: true

# HTMLファイル
- type: bind
  source: ../workloads/process-compose-dashboard/html
  target: /var/www/process-compose-dashboard
  read_only: true
```

### ホットリロード

バインドマウントされているため、ファイルを編集すると即座に反映されます：

- **HTML/CSS/JS**: ブラウザをリフレッシュするだけ
- **Nginx設定**: `sudo nginx -s reload` で反映

## 🚀 使い方

### アクセス

ブラウザで以下のURLを開く：

- **ダッシュボード**: http://localhost:4802/
- **ログビューア**: http://localhost:4802/logs.html
- **プロセス管理**: http://localhost:4802/processes.html

### ログストリーミング

1. ログビューアを開く
2. プロセスを選択
3. 「接続」ボタンをクリック
4. リアルタイムでログが表示される

### プロセス管理

1. プロセス管理ページを開く
2. 各プロセスの起動/停止/再起動が可能
3. 📋ボタンでログビューアに直接遷移

## 🔍 トラブルシューティング

### Nginx設定のテスト

```bash
sudo nginx -t
```

### Nginxの再起動

```bash
sudo nginx -s reload
```

### ログ確認

```bash
# Nginx エラーログ
tail -f /var/log/nginx/process-compose-dashboard-error.log

# supervisord ログ
tail -f /var/log/supervisor/nginx-stderr.log
```

## 📚 関連ファイル

- **Dockerfile**: `.devcontainer/Dockerfile` - Nginxインストール
- **supervisord設定**: `.devcontainer/supervisord/nginx.conf`
- **docker-compose**: `.devcontainer/docker-compose.yml` - バインドマウント設定

## 📝 開発

### ファイル編集

HTMLやCSS、JavaScriptを編集する場合：

1. このディレクトリのファイルを編集
2. ブラウザをリフレッシュ（バインドマウントなので即反映）

### Nginx設定変更

`nginx/process-compose-dashboard.conf`を編集後：

```bash
# 設定テスト
sudo nginx -t

# リロード
sudo nginx -s reload
```

---

**最終更新**: 2026-01-25
