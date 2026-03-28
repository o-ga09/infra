# おうちk8s マニフェストリポジトリ

ArgoCDで管理するKubernetesマニフェストのリポジトリです。

## リポジトリ構成

```
.
├── apps/                        # ArgoCDのApplication定義
│   ├── my-app.yaml
│   └── mysql.yaml
└── manifests/                   # 各アプリのマニフェスト
    ├── my-app/
    │   ├── namespace.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── ingress.yaml
    └── mysql/
        ├── pvc.yaml
        ├── secret.yaml          # .gitignore対象
        ├── sealed-secret.yaml   # Sealed Secrets使用時はこちらをcommit
        ├── deployment.yaml
        └── service.yaml
```

### 各ディレクトリの役割

- `apps/` … ArgoCDのApplication定義を置く場所。ここに追加するとArgoCDが管理対象として認識する
- `manifests/` … 実際にk8sに適用されるマニフェスト。ArgoCDがこのディレクトリを監視してデプロイする

### Secretの管理

パスワード等を含む `secret.yaml` はGitに含めません。

```bash
# .gitignore
manifests/*/secret.yaml
```

クラスタへの適用は手動で行います。

```bash
kubectl apply -f manifests/mysql/secret.yaml
```

---

## ローカル開発環境のセットアップ

### 前提

- Docker Desktop がインストール済みであること
- `kubectl` がインストール済みであること
- `helm` がインストール済みであること

### kubeconfigの設定

```bash
# k3s-serverからkubeconfigを取得
scp -i ~/.ssh/ouchi_k8s ubuntu@192.168.1.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# サーバーアドレスを書き換え
sed -i '' 's/127.0.0.1/192.168.1.10/' ~/.kube/config

# 接続確認
kubectl get nodes
```

### SSHの設定

`~/.ssh/config` に以下を追記しておくと便利です。

```
Host k3s-server
    HostName 192.168.1.10
    User ubuntu
    IdentityFile ~/.ssh/ouchi_k8s

Host k3s-agent
    HostName 192.168.1.11
    User ubuntu
    IdentityFile ~/.ssh/ouchi_k8s
```

### hostsファイルの設定

`/etc/hosts` に以下を追記します。

```
192.168.1.200  argocd.home.local
192.168.1.200  grafana.home.local
192.168.1.200  myapp.home.local
```

---

## ArgoCDへの登録手順

### 1. リポジトリを登録

ArgoCDのUI（Settings → Repositories）またはCLIで登録します。

```bash
argocd repo add https://github.com/<yourname>/<repo> \
  --username <GitHubユーザー名> \
  --password <GitHub PAT>
```

### 2. Applicationを登録

```bash
kubectl apply -f apps/my-app.yaml
```

### 3. 同期確認

ArgoCDのUI（`https://argocd.home.local`）でSyncステータスが `Synced` になっていることを確認します。

以降は `manifests/` 以下を変更してGitにpushするだけで自動デプロイされます。

### 新しいアプリを追加する場合

1. `manifests/<app-name>/` にマニフェストを作成
2. `apps/<app-name>.yaml` にArgoCDのApplication定義を作成
3. `kubectl apply -f apps/<app-name>.yaml` でArgoCDに登録
4. 以降はGit pushで自動デプロイ
