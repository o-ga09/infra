# Orca のヘッドレスサーバー（orca serve）を k3s で常駐させるためのイメージ。
# 公式のサーバー専用配布物（Node 同梱）を GitHub Releases から取得し、sha256 を検証して使う。
# 更新は ARG を手で書き換える PR で行う（バージョンと sha256 は必ずセットで更新すること）。
FROM debian:bookworm-slim

# https://github.com/stablyai/orca/releases の orca-server-sha256sums.txt を参照
ARG ORCA_VERSION=1.4.274
ARG ORCA_SHA256=b2f34c5a80e5b00f2b260833c1f9869e40e5e499cb2e9693e585a6c029c1c7ca
# https://downloads.claude.ai/claude-code-releases/<version>/manifest.json の checksum は取得時に検証する
ARG CLAUDE_CODE_VERSION=2.1.287

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

# 非 root で実行する。状態は /data（HOME と Orca のユーザーデータ）、作業ツリーは /work に置く
RUN useradd --uid 1000 --user-group --no-create-home --home-dir /data/home --shell /bin/bash orca \
 && mkdir -p /data /work \
 && chown orca:orca /data /work

ENV HOME=/data/home \
    ORCA_USER_DATA_PATH=/data/orca \
    CLAUDE_CONFIG_DIR=/data/home/.claude \
    DISABLE_AUTOUPDATER=1

COPY entrypoint.sh /usr/local/bin/orca-entrypoint
RUN chmod 0755 /usr/local/bin/orca-entrypoint

USER orca
WORKDIR /work
EXPOSE 6768
VOLUME ["/data", "/work"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/orca-entrypoint"]
