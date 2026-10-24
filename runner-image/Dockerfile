# ARC ランナー用イメージ。GitHub-hosted の ubuntu-latest にあって
# 素の actions-runner に無いコマンド（gh / zip / aws など）を足す。
FROM ghcr.io/actions/actions-runner:latest

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      zip unzip jq curl ca-certificates git gnupg \
 && rm -rf /var/lib/apt/lists/*

# gh CLI（公式 apt リポジトリ）
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# AWS CLI v2（アーキテクチャに合わせて取得）
RUN case "$(uname -m)" in x86_64) a=x86_64;; aarch64) a=aarch64;; esac \
 && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${a}.zip" -o /tmp/awscli.zip \
 && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscli.zip

USER runner
