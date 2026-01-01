FROM debian:12.7

ARG GID
ARG GNAME
ARG UID
ARG UNAME

# ローカルのdebian.sourcesファイルをイメージ内にコピー
COPY .devcontainer/debian.sources /etc/apt/sources.list.d/debian.sources

# # sbt インストールのために公式レポジトリを追加したり
# RUN echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | tee /etc/apt/sources.list.d/sbt.list && \
#     echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | tee /etc/apt/sources.list.d/sbt_old.list && \
#     curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x99E82A75642AC823" | apt-key add && \
#     apt-get update && \
#     apt-get install -y sbt

# Step 1: Install prerequisites for adding apt repositories
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      curl \
      gnupg2 \
      lsb-release \
      ca-certificates \
      locales

# Configure locales for Japanese support
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && echo "ja_JP.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen

# Set locale environment variables
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_CTYPE=ja_JP.UTF-8

# Set timezone
ENV TZ=Asia/Tokyo

# Step 2: Add Docker, GitHub CLI, and Google Cloud SDK repositories
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/google-cloud.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null

    # Step 3: Install main packages and perform setup
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      # CLI for Docker, GitHub, and Google Cloud
      docker-ce-cli gh google-cloud-cli \
      # Certificate utils
      libnss3-tools \
      # Network utils
      iputils-ping net-tools openssh-client lsof \
      # jq
      jq \
      # Python
      python3 pipx \
      # Git
      git git-lfs \
      # Sudo
      sudo \
      # Editors and viewers
      vim \
      less \
      # Basic tools
      procps \
      grep sed which tree \
      # Timezone data
      tzdata \
      # Archive tools
      zip unzip \
      # peco
      peco \
      # redis
      redis-tools \
    # Clean up apt
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/*

# Create python symlink
RUN ln -s $(which python3) /usr/bin/python

# Atuinのインストール（システム全体にインストール）
RUN curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh && \
    # バイナリをシステムパスに移動
    mv /root/.atuin/bin/atuin /usr/local/bin/ && \
    chmod +x /usr/local/bin/atuin && \
    # rootのAtuinディレクトリをクリーンアップ
    rm -rf /root/.atuin

# Atuin init for interactive shells is configured in ~/.bashrc below

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# DuckDBとxsvバイナリをシステム全体にインストール
# DuckDB CLI をダウンロードして /usr/local/bin に配置
RUN curl -L -o /tmp/duckdb.zip https://github.com/duckdb/duckdb/releases/download/v1.0.0/duckdb_cli-linux-amd64.zip && \
    cd /tmp && unzip duckdb.zip && \
    mv duckdb /usr/local/bin/ && \
    chmod +x /usr/local/bin/duckdb && \
    # xsv をダウンロードして /usr/local/bin に配置
    curl -L -o /tmp/xsv.tar.gz https://github.com/BurntSushi/xsv/releases/download/0.13.0/xsv-0.13.0-x86_64-unknown-linux-musl.tar.gz && \
    cd /tmp && tar -zxf xsv.tar.gz && \
    mv xsv /usr/local/bin/ && \
    chmod +x /usr/local/bin/xsv && \
    # クリーンアップ
    rm -f /tmp/duckdb.zip /tmp/xsv.tar.gz

# ENTRYPOINTスクリプトをコピー
COPY .devcontainer/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

#  外部化したシェル設定ファイルをコンテナにコピー
# このレイヤーは、コピー元のシェルスクリプトファイルが変更された場合にのみ無効化される
COPY .devcontainer/shell/.bash_profile /etc/skel/.bash_profile
COPY .devcontainer/shell/.bashrc_custom /etc/skel/.bashrc_custom
COPY .devcontainer/shell/paths.sh /etc/skel/paths.sh
COPY .devcontainer/shell/env.sh /etc/skel/env.sh
COPY .devcontainer/shell/.profile /etc/skel/.profile
# 他のカスタムファイルがあればここに追加 (e.g. aliases.sh)
# COPY.devcontainer/shell/aliases.sh /etc/skel/.aliases.sh

#  メインの.bashrcからカスタム設定を読み込むように設定
# このRUN命令は静的な文字列を追記するだけなので、
# 直前のCOPYレイヤーがキャッシュされている限り、このレイヤーもキャッシュされる
RUN echo '\n# Load custom dev container configurations' >> /etc/skel/.bashrc && \
    echo '# First, load environment variables' >> /etc/skel/.bashrc && \
    echo 'if [ -f ~/env.sh ]; then . ~/env.sh; fi' >> /etc/skel/.bashrc && \
    echo '# Second, set up paths' >> /etc/skel/.bashrc && \
    echo 'if [ -f ~/paths.sh ]; then . ~/paths.sh; fi' >> /etc/skel/.bashrc && \
    echo '\n# Then, load custom functions and aliases' >> /etc/skel/.bashrc && \
    echo 'if [ -f ~/.bashrc_custom ]; then . ~/.bashrc_custom; fi' >> /etc/skel/.bashrc
    # echo 'if [ -f ~/.aliases.sh ]; then. ~/.aliases.sh; fi' >> /etc/skel/.bashrc

# User and group setup
    # Create docker group
RUN groupadd -g 999 docker && \
    # Check if group exists, create only if it doesn't
    if ! getent group ${GNAME} > /dev/null 2>&1; then \
        groupadd -o -g ${GID} ${GNAME}; \
    fi && \
    useradd -o -l -u ${UID} -g ${GNAME} -G docker -m ${UNAME} && \
    chown ${UNAME}:${GNAME} /home/${UNAME} && \
    mkdir -p /home/${UNAME}/repos && \
    chown -R ${UID}:${GID} /home/${UNAME}/repos && \
    # Sudoers access
    echo "${UNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ${UNAME}

WORKDIR /home/${UNAME}

# Ensure bash-preexec is available for Atuin bash integration
RUN curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash_preexec

# tfenv のインストール
RUN git clone https://github.com/tfutils/tfenv.git ~/.tfenv && \
    # tfenv で terraform 1.13.0 をインストール
    ~/.tfenv/bin/tfenv install 1.13.0 && \
    ~/.tfenv/bin/tfenv use 1.13.0

# pipx を使えるように & webssh、CSVツールをインストール
RUN pipx ensurepath && \
    pipx install webssh && \
    pipx install csvkit && \
    pipx install visidata

# COPY --chown=${UNAME}:${GNAME} package.json ./
    # sdkman のインストール
RUN curl -s "https://get.sdkman.io" | bash \
    # sdk コマンドを使えるようにして java 11 をインストール
    && bash -c "source /home/${UNAME}/.sdkman/bin/sdkman-init.sh && sdk install java 11.0.26-tem && sdk use java 11.0.26-tem && sdk default java 11.0.26-tem"
    # # cmak 3.0.0.6 のインストール
    # && rm -rf cmak && curl -sL https://github.com/yahoo/CMAK/releases/download/3.0.0.6/cmak-3.0.0.6.zip -o cmak.zip && unzip -o cmak.zip && rm cmak.zip && mv cmak-3.0.0.6 cmak

# asdf install
RUN git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.13.1

ENV PATH="/home/${UNAME}/.asdf/bin:/home/${UNAME}/.asdf/shims:${PATH}"

# Node.jsプラグインをインストール
RUN asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git && \
    # Node.js インストール
    asdf install nodejs 22.17.0 && \
    asdf install nodejs 24.9.0 && \
    asdf global nodejs 22.17.0 && \
    corepack enable npm && \
    # corepack で npm のバージョンを固定
    npm -v && \
    npm install -g @anthropic-ai/claude-code && \
    npm install -g @google/gemini-cli && \
    npm install -g difit && \
    npm install -g dotenv-cli

# ENTRYPOINT は非インタラクティブシェルとして実行され、通常はシェルの初期化ファイルを読み込みまない
# これにより、ログインシェルで bash を用いて bash シェルを手動で実行したときとは異なる環境になる
# そのため、 JAVA_HOME や PATH が .bashrc に設定されている場合、それらの設定が読み込まれない
# そのため、 ENTRYPOINT で環境変数を設定する
ENV JAVA_HOME=/home/${UNAME}/.sdkman/candidates/java/current
ENV PATH=$JAVA_HOME/bin:$PATH
# WORKDIR /home/${UNAME}/cmak
# code-serverのポート設定（デフォルト: 4035）
ENV CODE_SERVER_PORT=4035
# difitのポート設定（デフォルト: 8035）
ENV DIFIT_PORT=8035
ENV VITE_PREVIEW_PORT=8036
ENV REVIEW_KNOWLEDGE_RAG_SERVER_PORT=8037
ENV KPI_WORKBENCH_PORT=8038
EXPOSE $DIFIT_PORT $VITE_PREVIEW_PORT $REVIEW_KNOWLEDGE_RAG_SERVER_PORT $CODE_SERVER_PORT $KPI_WORKBENCH_PORT
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# docker composeでCMD命令を上書きしている
CMD ["sh", "-c", "code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth password"]
