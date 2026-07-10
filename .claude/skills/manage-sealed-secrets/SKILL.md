---
name: manage-sealed-secrets
description: >
  このリポジトリ（k8sマニフェスト用GitOpsリポジトリ）で、各アプリ（secretary, mh-api など）の
  `secretary-secrets` 等のSecretを作成・更新するスキル。SealedSecretsコントローラーで暗号化し、
  ArgoCDが同期する。「シークレットを追加して」「secretにキーを足して」「sealed-secretを更新して」
  「Slackトークンを設定して」のように、manifests/配下のSecret/SealedSecretを触る依頼があったときに
  必ずこのスキルを使用すること。
---

# SealedSecrets 管理スキル

`manifests/<app>/` 配下の平文 `secret.yaml`（gitignore済み）と暗号化済み `sealed-secret.yaml`
（コミット対象）を安全に更新するためのワークフロー。

## 絶対に守ること

1. **`sealed-secret.yaml` を手で編集しない。** 暗号文は `kubeseal` の出力をそのまま使う。
   手動でフィールドを追記/削除すると壊れる（過去に一度、手動編集をやってしまいユーザーから
   明示的に止められた実例がある）。
2. **平文の値をコミットしない。** `manifests/<app>/secret.yaml` は `.gitignore` の
   `**/secret.yaml` で除外されている。コミットするのは `kubeseal` の出力（`sealed-secret*.yaml`）だけ。
3. **1キーだけ追加/変更したいときは、全キーを組み立て直さない。** 既存の値を打ち直すと
   タイポや欠落のリスクがある。代わりに、クラスタ上の**現在のSecretの値**を起点にして、
   変更したいキーだけ `jq` でマージしてから再シールする（下記手順）。
4. **平文の秘密値をシェルのコマンドライン引数にそのまま書かない。** ヒアドキュメント/変数経由でも
   コマンド自体はセッションログに残る。可能な限り `kubectl get secret ... -o json | jq ...` の
   パイプラインで完結させ、値を人間が読むメッセージに書き出さない。

## アプリごとの namespace 対応を先に確認する

`manifests/<app>/*.yaml` の `metadata.namespace` を見て、そのアプリが何個の namespace で
動いているか確認する。例えば `secretary` は API（Deployment, `secretary` namespace）と
バッチ（CronWorkflow, `argo-workflows` namespace）の2箇所で動くため、`secretary-secrets` を
**両方の namespace** に用意する必要がある。namespace ごとに必要なキーが異なる場合もある
（例: Slack Socket Mode 用の `SLACK_BOT_TOKEN`/`SLACK_APP_TOKEN`/`SLACK_ALLOWED_USER_ID` は
APIサーバー側の `secretary` namespaceにしか要らない）。判断がつかない場合はユーザーに確認する。

## 手順: 既存キーへの1キー追加/更新（推奨パス）

```sh
# 1. 対象 namespace のライブSecretを取得し、変更したいキーだけ差し替えて再シール
NEW_VALUE_B64=$(printf '%s' '<新しい値>' | base64 | tr -d '\n')
kubectl -n <namespace> get secret <secret-name> -o json \
  | jq --arg v "$NEW_VALUE_B64" '.data.<KEY> = $v
      | del(.metadata.creationTimestamp, .metadata.resourceVersion, .metadata.uid, .metadata.selfLink, .status)' \
  | kubeseal --format yaml \
      --controller-name=sealed-secrets --controller-namespace=kube-system \
  > .tmp-sealed-<namespace>.yaml

# 2. sealed-secret.yaml が複数namespace分のマルチドキュメントの場合、
#    対象namespaceのドキュメントだけを新しい内容に差し替える（他のnamespaceのドキュメントは触らない）
python3 - <<'EOF'
with open('manifests/<app>/sealed-secret.yaml') as f:
    docs = f.read().split('\n---\n')
with open('.tmp-sealed-<namespace>.yaml') as f:
    new_doc = f.read().rstrip('\n')
# docs のうち対象namespaceのドキュメントを new_doc に置き換えてから書き戻す
EOF

# 3. サーバーサイドdry-runで検証してからコミット
kubectl apply --dry-run=server -f manifests/<app>/sealed-secret.yaml
rm .tmp-sealed-<namespace>.yaml
```

**注意**: `kubectl get secret ... | jq '...=... | kubectl get secret ...'` のように
`get`のネストで別コマンドの出力を埋め込もうとすると、サブシェルの実行順序次第で空文字が
混入することがある（過去に一度、Webhook URLが空のまま再シールしてしまい、
`git diff`でキーが消えているのに気づいて修正した実例がある）。必ず値を変数に確定させてから
`jq`に渡すこと。

## 手順: ゼロから新規作成する場合のみ

新しい `secret.yaml`/`sealed-secret.yaml` をこの手順で最初から作る場合に限り、
全キーを一括で組み立ててよい（既存キーがまだ存在しないので差分マージ手順は使えない）。

```sh
kubectl -n <namespace> create secret generic <secret-name> \
  --from-literal=KEY1=... \
  --from-literal=KEY2=... \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
      --controller-name=sealed-secrets --controller-namespace=kube-system \
  > manifests/<app>/sealed-secret.yaml
```

## GAR pull secret（`gar-secret`）

Deployment/CronWorkflow は `imagePullSecrets: gar-secret` を参照する。新しい namespace を
作るときは同様に必要:

```sh
kubectl -n <namespace> create secret docker-registry gar-secret \
  --docker-server=asia-northeast1-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat gar-reader-key.json)" \
  --docker-email=unused@example.com
```

## 検証とコミット

```sh
# YAML構文とdry-runの両方を確認してからコミットする
python3 -c "import yaml,sys; list(yaml.safe_load_all(open('manifests/<app>/sealed-secret.yaml')))" && echo "YAML OK"
kubectl apply --dry-run=server -f manifests/<app>/sealed-secret.yaml
git add manifests/<app>/sealed-secret.yaml
git commit -m "feat(<app>): <キー名>を追加"
```

pushはユーザーに確認してから行う（ArgoCD が automated+selfHeal のため、push すると即座に
クラスタへ反映される）。

## アプリ別の必要キー

### secretary (`manifests/secretary/`)

`o-ga09/adk-go-sample` が要求する環境変数。`secretary` namespace（API）と `argo-workflows`
namespace（バッチ）の両方に必要（※印は `secretary` namespaceのみ）。

| キー | 内容 |
|---|---|
| `GOOGLE_API_KEY` | Gemini API キー |
| `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` | Google OAuth クライアント |
| `GOOGLE_OAUTH_REFRESH_TOKEN` | 個人Gmailのrefresh token（アプリ repo の `cmd/oauth` で取得） |
| `MYSQL_DSN` | 例 `user:pass@tcp(mysql.mysql.svc.cluster.local:3306)/secretary?parseTime=true` |
| `LINE_CHANNEL_TOKEN` / `LINE_TARGET_USER_ID` | LINE Messaging API（フォールバック） |
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook（既定の通知チャネル） |
| `SLACK_BOT_TOKEN` / `SLACK_APP_TOKEN` ※ | Slack Socket Modeでの@メンション呼び出し用。両方揃わないとリスナーは起動しない |
| `SLACK_ALLOWED_USER_ID` ※ | @メンション呼び出しを許可するSlackユーザーID。`SLACK_BOT_TOKEN`/`SLACK_APP_TOKEN`を設定するなら必須（未設定だと誰でも呼び出せる） |

### mh-api (`manifests/mh-api/`)

`secret.yaml`/`sealed-secret.yaml` の実ファイルを読んで必要キーを確認する（このスキルには
まだ表を持っていない。使う際に判明したら追記する）。
