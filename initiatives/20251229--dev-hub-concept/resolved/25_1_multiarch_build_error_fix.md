# マルチアーキテクチャ対応エラー修正

## 概要

DevContainer のビルドが失敗する問題を修正しました。原因は Dockerfile が x86_64/amd64 アーキテクチャのバイナリのみを想定していたため、arm64 (Apple Silicon) 環境でビルドが失敗していました。

## エラーログ

`initiatives/20251229--dev-hub-concept/202601030912-error.log`

### エラー内容

```
#14 ERROR: process "/bin/sh -c curl -L "https://github.com/F1bonacc1/process-compose/releases/download/v${PROCESS_COMPOSE_VERSION}/process-compose_Linux_x86_64.tar.gz" ..." did not complete successfully: exit code: 2

gzip: stdin: not in gzip format
tar: Child returned status 1
tar: Error is not recoverable: exiting now
```

ダウンロードしたファイルが 9 バイトしかなく、実際の tar.gz ではなかった（GitHubが404やリダイレクトを返していた）。

## 根本原因

1. **アーキテクチャ固定**: Dockerfile がバイナリのアーキテクチャを固定していた
   - process-compose: `Linux_x86_64` 固定
   - duckdb: `linux-amd64` 固定
   - xsv: `x86_64-unknown-linux-musl` 固定

2. **バージョン問題**: process-compose v1.39.2 が存在しない（最新は v1.85.0）

3. **ファイル名の誤り**: process-compose のファイル名が `Linux` (大文字) ではなく `linux` (小文字)

## 修正内容

### 1. TARGETARCH ビルド引数の追加

```dockerfile
ARG GID
ARG GNAME
ARG UID
ARG UNAME
ARG TARGETARCH  # 追加
```

**TARGETARCH について:**

`TARGETARCH` は Docker Buildx が自動的に提供する特殊なビルド引数です。ホストOSから明示的に渡す必要はありません。

- **自動設定**: Docker Buildx がビルド時に自動的に検出して設定
- **可能な値**: `amd64`, `arm64`, `arm`, `ppc64le`, など
- **使用方法**: Dockerfile で `ARG TARGETARCH` と宣言するだけで利用可能
- **docker-compose.yml での設定不要**: build.args に追加する必要なし

Docker Buildx が提供する自動ビルド引数:
- `TARGETPLATFORM`: 例: `linux/arm64`, `linux/amd64`
- `TARGETARCH`: 例: `arm64`, `amd64`
- `TARGETOS`: 例: `linux`
- `TARGETVARIANT`: 例: `v7` (ARM の場合)
- `BUILDPLATFORM`: ビルドを実行しているプラットフォーム
- `BUILDARCH`: ビルドを実行しているアーキテクチャ

参考: [Docker 公式ドキュメント - Automatic platform ARGs](https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope)

**実際の動作例:**
```dockerfile
ARG TARGETARCH
RUN echo "Building for: ${TARGETARCH}"
# Apple Silicon (M1/M2/M3) → "Building for: arm64"
# Intel Mac/Linux → "Building for: amd64"
```

### 2. process-compose のマルチアーキテクチャ対応

**修正前:**
```dockerfile
ARG PROCESS_COMPOSE_VERSION=1.39.2
RUN curl -L "https://github.com/F1bonacc1/process-compose/releases/download/v${PROCESS_COMPOSE_VERSION}/process-compose_Linux_x86_64.tar.gz" \
```

**修正後:**
```dockerfile
ARG PROCESS_COMPOSE_VERSION=1.85.0
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "arm64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -L "https://github.com/F1bonacc1/process-compose/releases/download/v${PROCESS_COMPOSE_VERSION}/process-compose_linux_${ARCH}.tar.gz" \
```

変更点:
- バージョンを 1.39.2 → 1.85.0 に更新
- ファイル名を `Linux_x86_64` → `linux_${ARCH}` に変更
- `${ARCH}` は `amd64` または `arm64`

### 3. duckdb のマルチアーキテクチャ対応

**修正前:**
```dockerfile
RUN curl -L -o /tmp/duckdb.zip https://github.com/duckdb/duckdb/releases/download/v1.0.0/duckdb_cli-linux-amd64.zip
```

**修正後:**
```dockerfile
RUN DUCKDB_ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "aarch64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -L -o /tmp/duckdb.zip https://github.com/duckdb/duckdb/releases/download/v1.0.0/duckdb_cli-linux-${DUCKDB_ARCH}.zip
```

変更点:
- arm64 の場合は `aarch64` を使用（DuckDB のリリース命名規則に合わせる）

### 4. xsv の条件付きインストール

**修正前:**
```dockerfile
RUN curl -L -o /tmp/xsv.tar.gz https://github.com/BurntSushi/xsv/releases/download/0.13.0/xsv-0.13.0-x86_64-unknown-linux-musl.tar.gz && \
    cd /tmp && tar -zxf xsv.tar.gz && \
    mv xsv /usr/local/bin/
```

**修正後:**
```dockerfile
# xsv をダウンロードして /usr/local/bin に配置 (amd64 のみ)
if [ "${TARGETARCH}" = "amd64" ]; then \
    curl -L -o /tmp/xsv.tar.gz https://github.com/BurntSushi/xsv/releases/download/0.13.0/xsv-0.13.0-x86_64-unknown-linux-musl.tar.gz && \
    cd /tmp && tar -zxf xsv.tar.gz && \
    mv xsv /usr/local/bin/ && \
    chmod +x /usr/local/bin/xsv && \
    rm -f /tmp/xsv.tar.gz; \
fi
```

変更点:
- xsv は arm64 バイナリが存在しないため、amd64 の場合のみインストール
- arm64 では xsv は利用できない（必要であれば cargo でビルドする必要あり）

## 検証

修正後、ビルドが正常に完了:

```
#33 exporting to image
#33 writing image sha256:58ff7854d4d3db6e6e39d25cc0f84afac554d271d87505c2efe464aaafcaf2be done
#33 naming to docker.io/library/devcontainer-dev done
#33 DONE 5.0s

 devcontainer-dev  Built
```

## アーキテクチャ対応一覧

| ツール | amd64 | arm64 | 備考 |
|--------|-------|-------|------|
| process-compose | ✅ | ✅ | v1.85.0 で両方サポート |
| duckdb | ✅ | ✅ | `amd64` / `aarch64` |
| xsv | ✅ | ❌ | arm64 バイナリなし |
| code-server | ✅ | ✅ | インストールスクリプトが自動判定 |
| Atuin | ✅ | ✅ | インストールスクリプトが自動判定 |

## 今後の対応

### xsv の arm64 対応

xsv を arm64 でも利用したい場合は、以下の方法が考えられる:

1. **Rust でビルド**: Dockerfile 内で cargo を使ってソースからビルド
   ```dockerfile
   RUN if [ "${TARGETARCH}" = "arm64" ]; then \
       cargo install xsv; \
   fi
   ```

2. **代替ツールの検討**:
   - `csvkit` (Python製、アーキテクチャ非依存)
   - `miller` (Go製、マルチアーキテクチャ対応)
   - `csvq` (Go製、マルチアーキテクチャ対応)

3. **スキップ**: xsv が必須でなければ、arm64 では利用しない（現在の実装）

## 関連ファイル

- [.devcontainer/Dockerfile](.devcontainer/Dockerfile)
- [.devcontainer/docker-compose.yml](.devcontainer/docker-compose.yml)
- [initiatives/20251229--dev-hub-concept/202601030912-error.log](initiatives/20251229--dev-hub-concept/202601030912-error.log)

## 参考

- [Docker Buildx - Multi-platform builds](https://docs.docker.com/build/building/multi-platform/)
- [process-compose releases](https://github.com/F1bonacc1/process-compose/releases)
- [DuckDB releases](https://github.com/duckdb/duckdb/releases)
- [xsv releases](https://github.com/BurntSushi/xsv/releases)
