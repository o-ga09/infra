#!/bin/sh
# orca serve をコンテナ向けに起動する。
#   ORCA_PORT             待ち受けポート（既定 6768）
#   ORCA_PAIRING_ADDRESS  クライアントに伝える接続先ホスト名/IP（任意）
#   ORCA_EXTRA_ARGS       そのまま渡す追加フラグ（任意。例: "--allow-public"）
set -eu

mkdir -p "$HOME" "$ORCA_USER_DATA_PATH" "$CLAUDE_CONFIG_DIR"

# git は PAT を使う場合に備え、認証情報を環境変数から渡せるようにする（値はイメージに焼かない）
git config --global --replace-all safe.directory '*' || true

set -- serve --bind 0.0.0.0 --port "${ORCA_PORT:-6768}" --supervise
if [ -n "${ORCA_PAIRING_ADDRESS:-}" ]; then
  set -- "$@" --pairing-address "$ORCA_PAIRING_ADDRESS"
fi
if [ -n "${ORCA_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2086
  set -- "$@" $ORCA_EXTRA_ARGS
fi

exec /usr/local/bin/orca "$@"
