# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stage 1: Extract RedisInsight from official image
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 公式イメージはマルチアーキテクチャ対応（amd64/arm64）
# Docker が自動的に現在のアーキテクチャに対応したイメージを選択
FROM redis/redisinsight:latest AS redisinsight-source

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stage 2: Node.js LTS for RedisInsight sqlite3 rebuild
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM node:lts-bookworm AS redisinsight-builder

# RedisInsightアプリケーションをコピー
COPY --from=redisinsight-source /usr/src/app /usr/src/app

# sqlite3をDebian環境用に再ビルド
# 公式イメージはAlpine Linux（musl libc）ベースだが、MDCはDebian（glibc）ベース
# そのため、ネイティブモジュールを再ビルドする必要がある
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      python3 \
      make \
      g++ \
      && \
    cd /usr/src/app/redisinsight/api && \
    npm rebuild sqlite3 --build-from-source && \
    apt-get remove -y python3 make g++ && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Stage 3: Main MDC image
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FROM debian:bookworm

ARG GID
ARG GNAME
ARG UID
ARG UNAME
ARG TARGETARCH
ARG MDC_REPO_ROOT
ARG DOCKER_GID

# ローカルのdebian.sourcesファイルをイメージ内にコピー
COPY .devcontainer/debian.sources /etc/apt/sources.list.d/debian.sources

# スクリプトをコピー
COPY .devcontainer/build/setup-group.sh /usr/local/bin/

# ホスト由来のユーザーグループ確保
RUN /usr/local/bin/setup-group.sh ${GNAME} ${GID}

# Docker グループ確保
RUN /usr/local/bin/setup-group.sh docker ${DOCKER_GID}

# # sbt インストールのために公式レポジトリを追加したり
# RUN echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | tee /etc/apt/sources.list.d/sbt.list && \
#     echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | tee /etc/apt/sources.list.d/sbt_old.list && \
#     curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x99E82A75642AC823" | apt-key add && \
#     apt-get update && \
#     apt-get install -y sbt

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 1: Install prerequisites for adding apt repositories
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      curl \
      gnupg2 \
      lsb-release \
      ca-certificates \
      locales \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 2: Add Docker, GitHub CLI, and Google Cloud SDK repositories
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/google-cloud.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 3: Install main packages and perform setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      # C/C++ build tools (for native module compilation)
      build-essential \
      # CLI for Docker and GitHub
      docker-ce-cli gh \
      # Certificate utils
      libnss3-tools \
      # Network utils
      iputils-ping net-tools openssh-client lsof \
      # jq
      jq \
      # Git
      git git-lfs \
      # Sudo
      sudo \
      # Editors and viewers
      vim \
      less \
      # Terminal multiplexer (for persistent AI agent sessions)
      tmux \
      # Basic tools
      procps \
      grep sed which tree ripgrep file \
      # Timezone data
      tzdata \
      # Archive tools
      zip unzip xz-utils \
      # peco
      peco \
      # redis
      redis-server redis-tools \
      # Process management: supervisord (PID 1)
      supervisor \
      # pandoc: Document converter (docx/pptx -> Markdown)
      pandoc \
      # poppler-utils: PDF text extraction (pdftotext)
      poppler-utils \
      # libreoffice: Document converter (doc/ppt -> txt)
      libreoffice-writer \
      # pipx: Python application installer (for mise pipx: backend)
      pipx \
      # nginx: Web server and reverse proxy
      nginx \
      # bubblewrap: Linux sandbox backend for Codex
      bubblewrap \
      # fuse3: FUSE support for gocryptfs (crypt-mount)
      fuse3 \
    # Clean up apt
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Japanese fonts (for Playwright headless browser rendering)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RUN mkdir -p /usr/share/fonts/truetype/noto && \
    curl -fL "https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf" \
    -o /usr/share/fonts/truetype/noto/NotoSansCJKjp-Regular.otf && \
    fc-cache -f

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# s6-overlay: PID 1 保護・プロセス監視
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ARG S6_OVERLAY_VERSION=3.1.6.2
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    rm /tmp/s6-overlay-noarch.tar.xz

# アーキテクチャ別のバイナリ
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "x86_64" ;; \
        "arm64") echo "aarch64" ;; \
        *) echo "x86_64" ;; \
    esac) && \
    curl -fL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCH}.tar.xz" \
    -o /tmp/s6-overlay-arch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && \
    rm /tmp/s6-overlay-arch.tar.xz

# /etc/s6-rc ディレクトリを早期に作成
RUN mkdir -p /etc/s6-rc

# s6-rc サービス定義をコピー
# v10設計: supervisord, process-compose, docker-entrypoint を s6-overlay で管理
COPY .devcontainer/config/s6-rc.d/ /etc/s6-overlay/s6-rc.d/

# cont-init.d 初期化スクリプトをコピー（mise環境設定等）
# s6-overlay v3 では oneshot サービスとしてディレクトリ構造が必要
COPY .devcontainer/config/cont-init.d/10-setup-mise-env/ /etc/s6-overlay/s6-rc.d/10-setup-mise-env/
# 実際のスクリプト本体を scripts/ にコピー
COPY --chmod=755 .devcontainer/config/cont-init.d/10-setup-mise-env.sh /etc/s6-overlay/scripts/10-setup-mise-env.sh
# user bundle に登録（空ファイルを作成）
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/10-setup-mise-env

# s6-rc サービスの run スクリプトに実行権限を付与
# 注記: COPY 命令は権限を保持するはずだが、明示的に設定することで確実性を高める
RUN find /etc/s6-overlay/s6-rc.d -type f -name 'run' -exec chmod +x {} \;

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process management: supervisord
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# デフォルト設定をコピー（フォールバック用）
COPY .devcontainer/config/supervisord/seed.conf /etc/supervisor/seed.conf

# ★★★ ユーザー作成前に検証するとエラーになるため、ここでは実行しない ★★★
# RUN echo "🔍 Validating default supervisord configuration..." && \
#     supervisord -c /etc/supervisor/seed.conf -t && \
#     echo "✅ Default supervisord configuration is valid"

# ★★★ supervisord検証について ★★★
# ビルド時に `supervisord -t` を実行すると、実際にsupervisordが起動して
# プロセスをspawnするため、ビルドがハングする問題が発生する。
# seed.confはフォールバック用の最小限設定であり、頻繁に変更されないため、
# 実行時エラーに任せる方針とする。
# 詳細: initiatives/20251229--dev-hub-concept/25_4_3_docker_build_debug_log.md Part 3

# 注記: supervisordの実際の設定は workloads/supervisord/project.conf が使用される
# docker-entrypoint.sh で project.conf → /etc/supervisor/supervisord.conf にシンボリックリンクされる

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Nginx: Web server and reverse proxy for Process Compose Dashboard
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 注記: Nginxプロセス管理設定は workloads/supervisord/project.conf に記載

# Remove default Nginx site
RUN rm -f /etc/nginx/sites-enabled/default

# Create directory for static HTML files (バインドマウント用)
RUN mkdir -p /var/www/process-compose-dashboard

# 注記: Nginx設定ファイルとHTMLファイルは workloads/process-compose-dashboard/ から
#       docker-compose.yml でバインドマウントされる
# ダミーファイル作成（log-forwarder のワイルドカード対策）
RUN mkdir -p /var/log/supervisor && \
    touch /var/log/supervisor/_keepalive.log

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# python
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Create python symlink
RUN ln -s $(which python3) /usr/bin/python

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Atuin
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Atuinのインストール（システム全体にインストール）
RUN curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh && \
    # バイナリをシステムパスに移動
    mv /root/.atuin/bin/atuin /usr/local/bin/ && \
    chmod +x /usr/local/bin/atuin && \
    # rootのAtuinディレクトリをクリーンアップ
    rm -rf /root/.atuin

# Atuin init for interactive shells is configured in ~/.bashrc below

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Process management: process-compose
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Install process-compose
ARG PROCESS_COMPOSE_VERSION=1.85.0
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "arm64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -fL "https://github.com/F1bonacc1/process-compose/releases/download/v${PROCESS_COMPOSE_VERSION}/process-compose_linux_${ARCH}.tar.gz" \
    -o /tmp/process-compose.tar.gz && \
    tar -xzf /tmp/process-compose.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/process-compose && \
    rm /tmp/process-compose.tar.gz

# デフォルト設定をコピー（フォールバック用）
RUN mkdir -p /etc/process-compose
COPY .devcontainer/config/process-compose/seed.yaml /etc/process-compose/seed.yaml

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Editor: code server
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RedisInsight: Redis GUI Tool (Web Server only)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 公式Dockerイメージからアプリケーションを抽出（マルチアーキテクチャ対応）
# - Stage 1 で redis/redisinsight:latest から /usr/src/app をコピー
# - Docker が自動的に現在のアーキテクチャ（amd64/arm64）に対応したイメージを選択
# - GUI依存関係不要（Webサーバーモードのみ）

# RedisInsightアプリケーションディレクトリを作成
RUN mkdir -p /usr/src/app

# Stage 2 (redisinsight-builder) から再ビルド済みのRedisInsightをコピー
COPY --from=redisinsight-builder /usr/src/app /usr/src/app

# データディレクトリを作成（設定・ログ保存用）
# RedisInsightは /data をデフォルトで使用
RUN mkdir -p /data

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Data aggregation tools for easily aggregating and analyzing ndjson and csv (e.g., with SQL)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# DuckDBとxsvバイナリをシステム全体にインストール
# DuckDB CLI をダウンロードして /usr/local/bin に配置
RUN DUCKDB_ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "aarch64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -fL -o /tmp/duckdb.zip https://github.com/duckdb/duckdb/releases/download/v1.0.0/duckdb_cli-linux-${DUCKDB_ARCH}.zip && \
    cd /tmp && unzip duckdb.zip && \
    mv duckdb /usr/local/bin/ && \
    chmod +x /usr/local/bin/duckdb && \
    rm -f /tmp/duckdb.zip && \
    # xsv をダウンロードして /usr/local/bin に配置 (amd64 のみ)
    if [ "${TARGETARCH}" = "amd64" ]; then \
        curl -fL -o /tmp/xsv.tar.gz https://github.com/BurntSushi/xsv/releases/download/0.13.0/xsv-0.13.0-x86_64-unknown-linux-musl.tar.gz && \
        cd /tmp && tar -zxf xsv.tar.gz && \
        mv xsv /usr/local/bin/ && \
        chmod +x /usr/local/bin/xsv && \
        rm -f /tmp/xsv.tar.gz; \
    fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Encryption tools: gocryptfs + age (for confidential directory management)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# gocryptfs: FUSE-based transparent encryption
# age: Modern file encryption using GitHub SSH keys
# yq: YAML parser for user group expansion
# 参照: projects/MDC/initiatives/20260110--git-crypt-aproach/

# age のインストール
ARG AGE_VERSION=1.2.0
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "arm64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -fL -o /tmp/age.tar.gz "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${ARCH}.tar.gz" && \
    tar xzf /tmp/age.tar.gz -C /tmp/ && \
    mv /tmp/age/age /usr/local/bin/ && \
    mv /tmp/age/age-keygen /usr/local/bin/ && \
    chmod +x /usr/local/bin/age /usr/local/bin/age-keygen && \
    rm -rf /tmp/age /tmp/age.tar.gz

# gocryptfs のインストール
ARG GOCRYPTFS_VERSION=2.6.1
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "arm64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -fL -o /tmp/gocryptfs.tar.gz "https://github.com/rfjakob/gocryptfs/releases/download/v${GOCRYPTFS_VERSION}/gocryptfs_v${GOCRYPTFS_VERSION}_linux-static_${ARCH}.tar.gz" && \
    tar xzf /tmp/gocryptfs.tar.gz -C /tmp/ && \
    mv /tmp/gocryptfs /usr/local/bin/ && \
    chmod +x /usr/local/bin/gocryptfs && \
    rm -f /tmp/gocryptfs.tar.gz /tmp/gocryptfs.1

# yq のインストール
ARG YQ_VERSION=4.44.1
RUN ARCH=$(case "${TARGETARCH}" in \
        "amd64") echo "amd64" ;; \
        "arm64") echo "arm64" ;; \
        *) echo "amd64" ;; \
    esac) && \
    curl -fL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}" && \
    chmod +x /usr/local/bin/yq

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This section is responsible for copying shell configuration files into the container.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#  外部化したシェル設定ファイルをコンテナにコピー
# このレイヤーは、コピー元のシェルスクリプトファイルが変更された場合にのみ無効化される
COPY .devcontainer/config/shell/.bash_profile /etc/skel/.bash_profile
COPY .devcontainer/config/shell/.bashrc_custom /etc/skel/.bashrc_custom
COPY .devcontainer/config/shell/env.sh /etc/skel/env.sh
COPY .devcontainer/config/shell/.profile /etc/skel/.profile
# 他のカスタムファイルがあればここに追加 (e.g. aliases.sh)
# COPY .devcontainer/config/shell/aliases.sh /etc/skel/.aliases.sh

#  メインの.bashrcからカスタム設定を読み込むように設定
# このRUN命令は静的な文字列を追記するだけなので、
# 直前のCOPYレイヤーがキャッシュされている限り、このレイヤーもキャッシュされる
RUN echo '\n# Load custom dev container configurations' >> /etc/skel/.bashrc && \
    echo '\n# Load custom functions and aliases' >> /etc/skel/.bashrc && \
    echo 'if [ -f ~/.bashrc_custom ]; then . ~/.bashrc_custom; fi' >> /etc/skel/.bashrc
    # echo 'if [ -f ~/.aliases.sh ]; then. ~/.aliases.sh; fi' >> /etc/skel/.bashrc

RUN echo "" >> /etc/skel/env.sh && \
    echo "# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> /etc/skel/env.sh && \
    echo "# ここから下は Dockerfile の ENV で設定されたものを追記" >> /etc/skel/env.sh && \
    echo "# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> /etc/skel/env.sh && \
    echo "" >> /etc/skel/env.sh

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# These sections are for organizing the Dockerfile into logical steps.
# Each section is clearly labeled to indicate its purpose.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Configure locales for Japanese support
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && echo "ja_JP.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen

# Set locale environment variables
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_CTYPE=ja_JP.UTF-8

# Set timezone
ENV TZ=Asia/Tokyo

# env.sh にも追記 ( Dockerfile の ENV が継承されない特殊環境用 ― 例: Claude Code VSCode Extension )
# このタイミングではまだスケルトン ( /etc/skel ) からコピーされていないので
RUN echo "export LANG=${LANG}" >> /etc/skel/env.sh && \
    echo "export LANGUAGE=${LANGUAGE}" >> /etc/skel/env.sh && \
    echo "export LC_CTYPE=${LC_CTYPE}" >> /etc/skel/env.sh && \
    echo "export TZ=${TZ}" >> /etc/skel/env.sh

RUN echo "" >> /etc/skel/env.sh && \
    echo "# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> /etc/skel/env.sh && \
    echo "# ここから下は /home/\${UNAME}/env.sh, /root/env.sh それぞれ独立して Dockerfile の ENV で設定されたものが追記される" >> /etc/skel/env.sh && \
    echo "# ↑ /etc/skel/env.sh の内容が各ユーザーの env.sh にコピーされるため" >> /etc/skel/env.sh && \
    echo "# つまり、 USER で指定したものに応じた \${HOME}/env.sh に追記される" >> /etc/skel/env.sh && \
    echo "# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> /etc/skel/env.sh && \
    echo "" >> /etc/skel/env.sh

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# User and group setup
#   and sudoers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# このタイミングで スケルトン (/etc/skel) からコピーされる

# User and group setup
# Create supervisor group for healthcheck access
RUN groupadd -r supervisor
# GNAME グループと docker グループは apt-get より前に作成済み（GID 確保のため）
RUN useradd -o -l -u ${UID} -g ${GNAME} -G supervisor,docker -m -s /bin/bash ${UNAME}
RUN chown ${UNAME}:${GNAME} /home/${UNAME}
RUN mkdir -p /home/${UNAME}/repos
RUN chown -R ${UID}:${GID} /home/${UNAME}/repos

RUN echo "${UNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# root ユーザー用にも同様の設定を適用
# 既存ユーザー（root）には /etc/skel/ の内容が自動コピーされないため、明示的にコピー
# /etc/skel/.bashrc には既にカスタム設定の読み込みが含まれているため、そのままコピーするだけで良い
RUN cp /etc/skel/.bashrc_custom /root/.bashrc_custom && \
    cp /etc/skel/env.sh /root/env.sh && \
    cp /etc/skel/.bashrc /root/.bashrc

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# for mise
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# MDC_REPO_ROOT ディレクトリを作成（mise用）
RUN mkdir -p /home/${UNAME}/${MDC_REPO_ROOT}
RUN chown -R ${UID}:${GID} /home/${UNAME}/${MDC_REPO_ROOT}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# for redis
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Redis データディレクトリを作成（権限設定）
# /var/lib/redis: Redis の AOF ファイル保存先（redis.conf の dir で指定）
# Docker volume redis-data がこのディレクトリにマウントされる
# chown: Redis は ${UNAME}:${GNAME} で実行されるため、書き込み権限が必要
RUN mkdir -p /var/lib/redis && \
    chown ${UNAME}:${GNAME} /var/lib/redis

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# for redisinsight
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# RedisInsight データディレクトリの権限設定
# /data: RedisInsight の設定・ログ保存先（デフォルト）
# chown: RedisInsight は ${UNAME}:${GNAME} で実行されるため、書き込み権限が必要
RUN chown -R ${UNAME}:${GNAME} /data /usr/src/app

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [General user operations]
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Switch to general user
USER ${UNAME}
WORKDIR /home/${UNAME}

# 一般ユーザーでインストールする系のコマンドにPATHを通す
ENV PATH="/home/${UNAME}/.local/bin:${PATH}"
RUN echo "export PATH=/home/${UNAME}/.local/bin:${PATH}" >> /home/${UNAME}/env.sh

# Ensure bash-preexec is available for Atuin bash integration
RUN curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash_preexec

# claude code install
RUN curl -fsSL https://claude.ai/install.sh | bash


# sdkman のインストール
RUN curl -fsSL 'https://get.sdkman.io' | bash && \
    bash -c "source ~/.sdkman/bin/sdkman-init.sh && sdk install java 11.0.26-tem && sdk use java 11.0.26-tem && sdk default java 11.0.26-tem"
    # # cmak 3.0.0.6 のインストール
    # && rm -rf cmak && curl -sL https://github.com/yahoo/CMAK/releases/download/3.0.0.6/cmak-3.0.0.6.zip -o cmak.zip && unzip -o cmak.zip && rm cmak.zip && mv cmak-3.0.0.6 cmak

# ENTRYPOINT は非インタラクティブシェルとして実行され、通常はシェルの初期化ファイルを読み込みまない
# これにより、ログインシェルで bash を用いて bash シェルを手動で実行したときとは異なる環境になる
# そのため、 JAVA_HOME や PATH が .bashrc に設定されている場合、それらの設定が読み込まれない
# そのため、 ENTRYPOINT で環境変数を設定する
ENV JAVA_HOME=/home/${UNAME}/.sdkman/candidates/java/current
ENV PATH=${JAVA_HOME}/bin:${PATH}
# env.sh にも追記 ( Dockerfile の ENV が継承されない特殊環境用 ― 例: Claude Code VSCode Extension )
RUN echo "export JAVA_HOME=/home/${UNAME}/.sdkman/candidates/java/current" >> /home/${UNAME}/env.sh && \
    echo "export PATH=${JAVA_HOME}/bin:${PATH}" >> /home/${UNAME}/env.sh

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# mise: Polyglot version manager (asdf + tfenv 統合)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase A で検証済み: インストール時間 4.077秒
# - Node.js, Terraform, gcloud, Python を統一管理
# - .mise.toml による宣言的ツール管理
# - asdf互換プラグインをサポート

# Step 1: mise本体のインストール
# 注記: デフォルト配布先 mise.jdx.dev ではなく GitHub Releases を使い、
# Docker build 中の一時的な到達性問題を避ける
RUN curl -fsSL https://mise.run | MISE_INSTALL_FROM_GITHUB=1 sh

# Step 1.5: legacy file サポートを有効化（オプション）
# 注記: 既存の .node-version, .nvmrc, .python-version などを読む場合のみ必要
# Phase I 追加調査3で検証: デフォルトで無効のため、グローバル設定で有効化
RUN mise settings set idiomatic_version_file_enable_tools node && \
    mise settings set idiomatic_version_file_enable_tools python && \
    mise settings set idiomatic_version_file_enable_tools terraform

# Step 2: .mise.toml をCOPYしてビルド時にツールをインストール
# 注記: この .mise.toml は実行時に bind mount で上書きされる
# 理由1: ビルド時にツールをインストールすることで、イメージに焼き込む（再現性）
# 理由2: 実行時に bind mount されることで、.mise.toml の変更を即座に反映（柔軟性）
# COPY先は docker-compose.yml の working_dir と一致させる
# 重要: デフォルト値なし（MDC_REPO_ROOT は docker-compose.yml から必ず渡される）
COPY --chown=${UNAME}:${GNAME} .mise.toml /home/${UNAME}/.mise.toml

# Step 3: ビルド時にツールをインストール
# Phase A-H で検証済み: 総インストール時間 37.013秒（6ツール）
# Python環境改善 Phase 1: uv もここでインストールされる（.mise.toml に追加）
# 注記: GitHub APIレート制限を回避するため、ビルド時に GITHUB_TOKEN を渡す
#       docker-compose.yml の build.args に GITHUB_TOKEN を追加する
RUN export MISE_PYTHON_GITHUB_ATTESTATIONS=false && \
    export MISE_NODE_VERIFY=0 && \
    export MISE_NODE_GPG_VERIFY=0 && \
    mise trust && \
    mise install

# Step 4.1: Python依存ライブラリのインストール（uv使用）
# 注記: pyproject.toml を .mise.toml と同じディレクトリ（WORKDIR）に配置
# 理由1: ビルド時にツールをインストールすることで、イメージに焼き込む（再現性）
# 理由2: 実行時に bind mount されることで、pyproject.toml の変更を即座に反映（柔軟性）
# 注記: [tool.hatch.build.targets.wheel] bypass-selection = true が必要
#       hatchling 1.19+ では packages = [] が非推奨となり、bypass-selection を使用する
COPY --chown=${UNAME}:${GNAME} pyproject.toml /home/${UNAME}/pyproject.toml
RUN mise exec -- uv pip install --system .

# Step 4.2: Python CLIツールのインストール（uv tool install）
# 旧環境: pipx install で管理していたツールを uv に統一
RUN mise exec -- uv tool install webssh && \
    mise exec -- uv tool install csvkit && \
    mise exec -- uv tool install visidata

# Step 4.3: グローバルnpmパッケージのインストール
# 注記: mise reshim を明示的に実行することで、shim の再現性を保証
# 参照: initiatives/20260121-20260122-shell-environment-consistency/strategy_shell_environment_consistency.md
# 注記: Node.jsは既にmiseでインストール済み
# 注記: PATHは既にENVで設定済みのため、export不要
RUN mise exec -- npm install -g @google/gemini-cli && \
    mise exec -- npm install -g difit && \
    mise exec -- npm install -g dotenv-cli && \
    mise exec -- npm install -g playwright && \
    mise exec -- npm install -g @openai/codex && \
    mise reshim && \
    mise exec -- playwright install --with-deps chromium

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Port Allocation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4000番台: MDC Infrastructure ports
# 8000番台: Application ports
#
# ⚠️ 重要: docker-compose.yml の ports セクションと同期すること
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 4000番台: MDC Infrastructure (always open)
ENV STATIC_FILE_SERVER_PORT=4001
ENV CODE_SERVER_PORT=4035
ENV SUPERVISORD_PORT=4222
ENV PROCESS_COMPOSE_PORT=4040
ENV PROCESS_COMPOSE_DASHBOARD_PORT=4802

# 4000番台: MDC Infrastructure (optional)
ENV DIFIT_PORT=4025
ENV REDISINSIGHT_PORT=4803

# 8000番台: Applications

# 9000番台: Private services (container-internal only)
ENV PLAYWRIGHT_MCP_PORT=9001
ENV PLAYWRIGHT_MCP_BROWSER=chromium

RUN echo "export STATIC_FILE_SERVER_PORT=4001" >> /home/${UNAME}/env.sh && \
    echo "export CODE_SERVER_PORT=4035" >> /home/${UNAME}/env.sh && \
    echo "export SUPERVISORD_PORT=4222" >> /home/${UNAME}/env.sh && \
    echo "export PROCESS_COMPOSE_PORT=4040" >> /home/${UNAME}/env.sh && \
    echo "export DIFIT_PORT=4025" >> /home/${UNAME}/env.sh && \
    echo "export PROCESS_COMPOSE_DASHBOARD_PORT=4802" >> /home/${UNAME}/env.sh && \
    echo "export REDISINSIGHT_PORT=4803" >> /home/${UNAME}/env.sh && \
    echo "export PLAYWRIGHT_MCP_PORT=9001" >> /home/${UNAME}/env.sh && \
    echo "export PLAYWRIGHT_MCP_BROWSER=chromium" >> /home/${UNAME}/env.sh

# EXPOSE (docker-compose.yml の ports セクションと対応)
# 4000番台: Infrastructure
EXPOSE $STATIC_FILE_SERVER_PORT
EXPOSE $CODE_SERVER_PORT
EXPOSE $SUPERVISORD_PORT
EXPOSE $PROCESS_COMPOSE_PORT
EXPOSE $DIFIT_PORT
EXPOSE $REDISINSIGHT_PORT
EXPOSE $PROCESS_COMPOSE_DASHBOARD_PORT
# 8000番台: Applications

# 9000番台: Private services は external publish しないため EXPOSE しない

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# <Root User operations again>
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Entrypoint & CMD
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USER root
# ユーザー切り替え前に実行する必要があるため、rootユーザーで実行する
# ENTRYPOINTスクリプトをコピー
COPY .devcontainer/build/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# デバッグモード用ENTRYPOINTスクリプトをコピー
COPY .devcontainer/build/debug-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/debug-entrypoint.sh

# ENTRYPOINTを最後に設定（ユーザー切り替え後）
# これにより、コンテナ起動時のデフォルトユーザーが <一般ユーザー> になる
ENTRYPOINT ["/init"]
# s6-overlay を PID 1 として起動（/init）
# v10設計: s6-overlay が以下のサービスを管理
#   - docker-entrypoint (oneshot): 初期化処理（Phase 1-5）
#   - supervisord (longrun): code-server等のプロセス管理
#   - process-compose (longrun): TUIプロセス管理

# 一般ユーザーに切り替え
# USER ${UNAME}
# WORKDIR /home/${UNAME}
