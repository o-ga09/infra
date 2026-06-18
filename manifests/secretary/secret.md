# secretary-secrets の作成手順

アプリ（`o-ga09/adk-go-sample`）は以下のキーを **環境変数**として要求する。
Deployment / CronWorkflow いずれも `envFrom.secretRef: secretary-secrets` で注入する。

> ⚠️ **実値は絶対にコミットしない。** このリポジトリは `.gitignore` で `**/secret.yaml` を除外している。
> 平文を残したい場合は `manifests/secretary/secret.yaml`（gitignore 済み）に書き、`kubectl apply` で手動投入する。
> GitOps（ArgoCD）で管理したい場合は下記の **SealedSecret** を使う（推奨）。

## 必要なキー

| キー | 内容 |
|---|---|
| `GOOGLE_API_KEY` | Gemini API キー |
| `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` | Google OAuth クライアント |
| `GOOGLE_OAUTH_REFRESH_TOKEN` | 個人 Gmail の refresh token（アプリ repo の `cmd/oauth` で取得）|
| `MYSQL_DSN` | 例 `user:pass@tcp(mysql.mysql.svc.cluster.local:3306)/secretary?parseTime=true` |
| `LINE_CHANNEL_TOKEN` / `LINE_TARGET_USER_ID` | LINE Messaging API |

## ⚠️ 2つの namespace に作成する

- **API（Deployment）** は `secretary` namespace で動く
- **バッチ（CronWorkflow）** は `argo-workflows` namespace で動く（既存コントローラーの対象 namespace）

そのため `secretary-secrets` は **`secretary` と `argo-workflows` の両方**に作成する必要がある。

## 方法 A: SealedSecrets（推奨・GitOps）

このクラスタには SealedSecrets コントローラーが入っている（`mh-api` で `sealed-secret.yaml` を使用）。

```sh
# まず通常の Secret を組み立てて、kubeseal で暗号化 → SealedSecret を出力（secretary namespace 用）
kubectl -n secretary create secret generic secretary-secrets \
  --from-literal=GOOGLE_API_KEY=... \
  --from-literal=GOOGLE_OAUTH_CLIENT_ID=... \
  --from-literal=GOOGLE_OAUTH_CLIENT_SECRET=... \
  --from-literal=GOOGLE_OAUTH_REFRESH_TOKEN=... \
  --from-literal=MYSQL_DSN='user:pass@tcp(mysql.mysql.svc.cluster.local:3306)/secretary?parseTime=true' \
  --from-literal=LINE_CHANNEL_TOKEN=... \
  --from-literal=LINE_TARGET_USER_ID=... \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > sealed-secret.yaml

# argo-workflows namespace 用も同様に（-n を変更して）作成
kubectl -n argo-workflows create secret generic secretary-secrets \
  --from-literal=GOOGLE_API_KEY=... \
  ... （同上） ... \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > sealed-secret-argo-workflows.yaml
```

生成した `sealed-secret*.yaml` は暗号化済みなので **このディレクトリにコミットしてよい**（ArgoCD が同期する）。

## 方法 B: 手動作成（コミットしない）

```sh
# secretary namespace
kubectl -n secretary create secret generic secretary-secrets \
  --from-literal=GOOGLE_API_KEY=... \
  --from-literal=GOOGLE_OAUTH_CLIENT_ID=... \
  --from-literal=GOOGLE_OAUTH_CLIENT_SECRET=... \
  --from-literal=GOOGLE_OAUTH_REFRESH_TOKEN=... \
  --from-literal=MYSQL_DSN='user:pass@tcp(mysql.mysql.svc.cluster.local:3306)/secretary?parseTime=true' \
  --from-literal=LINE_CHANNEL_TOKEN=... \
  --from-literal=LINE_TARGET_USER_ID=...

# argo-workflows namespace（バッチ用）
kubectl -n argo-workflows create secret generic secretary-secrets \
  --from-literal=GOOGLE_API_KEY=... \
  # ... 同じキーを指定 ...
```

## GAR pull secret（gar-secret）

Deployment / CronWorkflow とも `imagePullSecrets: gar-secret` を参照する。
`mh-api` namespace と同様、各 namespace に作成する。

```sh
for ns in secretary argo-workflows; do
  kubectl -n "$ns" create secret docker-registry gar-secret \
    --docker-server=asia-northeast1-docker.pkg.dev \
    --docker-username=_json_key \
    --docker-password="$(cat gar-reader-key.json)" \
    --docker-email=unused@example.com
done
```
