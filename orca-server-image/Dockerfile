# Orca のヘッドレスサーバー（orca serve）を k3s で常駐させるためのイメージ。
# 公式のサーバー専用配布物（Node 同梱）を GitHub Releases から取得し、sha256 を検証して使う。
# 更新は ARG を手で書き換える PR で行う（バージョンと sha256 は必ずセットで更新すること）。
FROM debian:bookworm-slim

# https://github.com/stablyai/orca/releases の orca-server-sha256sums.txt を参照
ARG ORCA_VERSION=1.4.274
ARG ORCA_SHA256=b2f34c5a80e5b00f2b260833c1f9869e40e5e499cb2e9693e585a6c029c1c7ca
# https://downloads.claude.ai/claude-code-releases/<version>/manifest.json の checksum は取得時に検証する
ARG CLAUDE_CODE_VERSION=2.1.287
# エージェントが動作確認（スクショ・テスト・Lint）に使う開発ツール。
# Node: https://nodejs.org/dist/v<ver>/SHASUMS256.txt の node-v<ver>-linux-x64.tar.xz
# Flutter: https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json の sha256
# 更新はバージョンと sha256 をセットで書き換える PR で行う（pnpm / Playwright は npm の版数のみ）。
ARG NODE_VERSION=26.13.1
ARG NODE_SHA256=5c063e46bab0fbc1c17cc445d7ff129cbdcd0471be6ed83b6ab864f8143bc864
ARG PNPM_VERSION=12.23.0
ARG PLAYWRIGHT_VERSION=1.65.1
ARG FLUTTER_VERSION=3.50.1
ARG FLUTTER_SHA256=4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client jq tini ripgrep procps gnupg \
 && rm -rf /var/lib/apt/lists/*

# gh CLI（公式 apt リポジトリ。runner-image と同じ手順）
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Orca サーバー（linux-x64-glibc）。sha256 が一致しなければビルドを失敗させる
RUN curl -fsSL "https://github.com/stablyai/orca/releases/download/v${ORCA_VERSION}/orca-server-linux-x64.tar.gz" -o /tmp/orca-server.tar.gz \
 && echo "${ORCA_SHA256}  /tmp/orca-server.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/orca \
 && tar -xzf /tmp/orca-server.tar.gz -C /opt/orca --strip-components=1 \
 && rm /tmp/orca-server.tar.gz \
 && ln -s /opt/orca/bin/orca-ide /usr/local/bin/orca

# Claude Code（公式バイナリ。manifest の checksum で検証）
RUN base="https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}" \
 && sum="$(curl -fsSL "${base}/manifest.json" | jq -r '.platforms["linux-x64"].checksum')" \
 && curl -fsSL "${base}/linux-x64/claude" -o /usr/local/bin/claude \
 && echo "${sum}  /usr/local/bin/claude" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/claude

# Node.js（公式 tarball。sha256 が一致しなければビルドを失敗させる）。Orca 同梱の Node とは別物
RUN apt-get update && apt-get install -y --no-install-recommends xz-utils unzip zip libatomic1 \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz \
 && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE' \
 && rm /tmp/node.tar.xz \
 && npm install -g "pnpm@${PNPM_VERSION}" "playwright@${PLAYWRIGHT_VERSION}" \
 && npm cache clean --force

# Playwright のブラウザ（chromium のみ）と OS 依存ライブラリ。非 root の orca から読めるよう共有パスに置く
# グローバルインストールした playwright をプロジェクト側から require できるよう NODE_PATH も通す
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    NODE_PATH=/usr/local/lib/node_modules
RUN playwright install --with-deps chromium \
 && rm -rf /var/lib/apt/lists/* \
 && chmod -R a+rX /opt/ms-playwright

# Flutter SDK（stable、sha256 検証）。flutter 自身が bin/cache に書き込むため orca 所有にする
RUN apt-get update && apt-get install -y --no-install-recommends libglu1-mesa \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz \
 && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz
ENV PATH=/opt/flutter/bin:$PATH \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    DART_SUPPRESS_ANALYTICS=true \
    CI=true

# 非 root で実行する。状態は /data（HOME と Orca のユーザーデータ）、作業ツリーは /work に置く
RUN useradd --uid 1000 --user-group --no-create-home --home-dir /data/home --shell /bin/bash orca \
 && mkdir -p /data /work /data/home \
 && chown -R orca:orca /data /work /opt/flutter

ENV HOME=/data/home \
    ORCA_USER_DATA_PATH=/data/orca \
    CLAUDE_CONFIG_DIR=/data/home/.claude \
    DISABLE_AUTOUPDATER=1

COPY entrypoint.sh /usr/local/bin/orca-entrypoint
RUN chmod 0755 /usr/local/bin/orca-entrypoint

USER orca
# Flutter / Dart のキャッシュ（Web 用 SDK 含む）をビルド時に取得しておき、実行時のダウンロードを避ける。
# analytics 設定はビルド用 HOME に書かれるだけで、実行時の HOME（/data/home）には影響しない
RUN git config --global --add safe.directory /opt/flutter \
 && flutter config --no-analytics --enable-web >/dev/null \
 && flutter precache --web --no-android --no-ios --no-linux --no-macos --no-windows \
 && flutter --version
WORKDIR /work
EXPOSE 6768
VOLUME ["/data", "/work"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/orca-entrypoint"]
