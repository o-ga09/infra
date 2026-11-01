# gopher-office

2D バーチャルオフィス（Ebitengine + Agones）。アプリのリポジトリ: https://github.com/o-ga09/gopher-office

```
Cloudflare Tunnel → ingress-nginx ─ /       → office-web
                                  ├ /v1     → office-api ── MySQL / Redis / k8s API（GameServerAllocation）
                                  └ /room   → office-gateway ── Pod IP:7654 → GameServer（Agones Fleet "office"）
```

Agones 本体は `apps/agones.yaml`（Helm、`agones-system`）。GameServer は `gopher-office` Namespace に置く。

## 初回に手で行うこと（ArgoCD に載せる前）

ArgoCD は同期の最初（PreSync）にマイグレーションの Job を動かすので、**先に Secret と DB が必要**。

1. **DB とユーザーを作る**（既存の MySQL に、専用の DB とユーザーを作る）
   ```sql
   CREATE DATABASE gopher_office CHARACTER SET utf8mb4;
   CREATE USER 'gopher_office'@'%' IDENTIFIED BY '<生成した値>';
   GRANT ALL ON gopher_office.* TO 'gopher_office'@'%';
   ```
2. **Secret を作る**（Namespace `gopher-office`、名前 `office-secret`）。キーは下表のとおり（R2 の 4 キーは P6 のアイコン画像用）:

   | キー | 値 |
   |---|---|
   | `MYSQL_DSN` | `gopher_office:<パスワード>@tcp(mysql.mysql.svc.cluster.local:3306)/gopher_office?parseTime=true&charset=utf8mb4` |
   | `PLAYER_TOKEN_SECRET` | 32 バイト以上のランダム値（API だけが持つ） |
   | `ROOM_TOKEN_SECRET` | 32 バイト以上のランダム値（API・ゲートウェイ・GameServer が共有）。`PLAYER_TOKEN_SECRET` と別の値にする |
   | `S3_ENDPOINT` | R2 のエンドポイント `https://<アカウントID>.r2.cloudflarestorage.com`（アイコン画像用） |
   | `S3_BUCKET` | R2 のバケット名（非公開のまま。API が代わりに配信する） |
   | `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` | R2 の API トークン（対象バケットの Object Read & Write だけ）から発行した S3 互換の認証情報 |

   > R2 の 4 キー（アイコン画像用）は、gopher-office の P6 のイメージ（`-icon-store` フラグ対応）が出てから使う。
   > 先に R2 のバケットとトークンを作り、この 4 キーを `office-secret` に足してから、このリポジトリの変更をマージすること。
   > 既存アイコンの R2 への移行は、デプロイ後に `cmd/iconmigrate`（`-icon-store=s3`、`MYSQL_DSN` と `S3_*` / `AWS_*` を環境変数で渡す）を 1 回実行する。

   `.claude/rules/secrets.md` のとおり、`kubeseal` で `sealed-secret.yaml` にして、この Namespace に置く。
   **このファイルが無いまま同期すると、Pod は `CreateContainerConfigError` になり、PreSync の Job が失敗する。**
3. **GHCR のイメージを pull できるようにする**: `ghcr.io/o-ga09/gopher-office/{gameserver,gateway,api,web}` は、
   初回はプライベートで作られる。パッケージを Public にするか、pull 用の Secret を作って `imagePullSecrets` を足す。
4. **Cloudflare Tunnel** の Public Hostname に `office.o-ga09.com` → ingress-nginx のサービスを追加する（ダッシュボードでの設定）。

## 構成の要点

- **Fleet** `office`: 待機（Ready）を 1〜2 台保つ（FleetAutoscaler の Buffer、最大 6）。ポートは公開しない（`portPolicy: None`）
- **割り当て**: API が `GameServerAllocation` でルームに 1 台を割り当て、ルーム ID を annotation `roomId` で GameServer に渡す。無人が 5 分続くと GameServer が自分で Shutdown する
- **RBAC**: API は `gameserverallocations` の create と `gameservers` の get、ゲートウェイは `pods` の get だけ
- **Redis**: 既存の `redis` を共有（DB 1）。割り当ての直列化（ロック）とルーム→GameServer の記録に使う
- **イメージ**: `:main` を `imagePullPolicy: Always` で使う。固定したいときは `sha-<コミット>` に変える（CI での自動更新は未設定）
- `/internal/*`（API の内部用）は Ingress に出していない

## 確認

```bash
kubectl -n gopher-office get fleet,gs,pods
kubectl -n gopher-office logs deploy/office-api
```
