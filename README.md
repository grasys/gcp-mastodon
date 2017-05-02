# Google Cloud PlatformでMastodon！

こちらのリポジトリはインプレスR&Dから出版された「これがマストドンだ! 使い方からインスタンスの作り方まで」の13章に掲載されているコマンドラインなどをまとめたリポジトリになります。

## 踏み台兼作業用インスタンスの作成

### opsの構成前に実施する確認

Google Cloud Platrformにログインしているユーザを確認します。
`<your account>` の部分があなたのGoogle Accountであれば大丈夫です。

```bash
$ gcloud auth list
Credentialed Accounts:
 - <your account> ACTIVE
```

Google Cloud SDKで使うデフォルトの `account` と `project id` を確認します。
既に作成したプロジェクトの `project id` と `<your project id>` が同じであれば大丈夫です。
`account` は先ほど確認した `<your account>` と同じであることを確認してください。

```bash
$ gcloud config list
[core]
account = <your account>
project = <your project id>
```

### opsを作る

今回はマシンタイプを `n1-standard-1` としていますが、 `g1-small` ぐらいでも大丈夫です。

```bash
$ gcloud compute instances create ops \
  --machine-type n1-standard-1 \
  --tags ops \
  --zone asia-northeast1-a \
  --image-project debian-cloud \
  --image debian-8-jessie-v20170327 \
  --scopes cloud-platform
```

### SSHのFWルールを更新

#### 適用したいポリシー

下記のポリシーで設定したい場合の例となります。
そこまで厳しくする必要のない場合は、スキップしても大丈夫です。

- ops以外のインスタンスは外部からのsshを許可しない
- opsへのsshも自IPからのみとする

```bash
$ SOURCE_IP=`curl -s httpbin.org/ip | jq -r .origin`
$ gcloud compute firewall-rules update default-allow-ssh \
  --allow TCP:22 \
  --source-ranges ${SOURCE_IP}/32 \
  --target-tags ops
```

#### gcloudコマンドで一回ログイン

プロジェクトメタデータにssh公開鍵を登録します。

```bash
$ gcloud compute ssh ops --zone asia-northeast1-a
```

一回ログインできたらログアウトしちゃいましょう。

#### ssh-agentに関して

ssh-agentの説明は省きます。単純に、サーバ上にsshのprivate_keyを置かないために、ssh-agentを使ってログインしたいだけです。
ちなみに、著者がMacユーザのため、Mac以外の場合の場合は検証していませんので、各自調べてみてください。

```bash
$ ssh-add ~/.ssh/google_compute_engine
$ ssh -A <username>@<ops ip>
```

### opsにログインしたら実施しておくこと

#### インスタンス作成の時に利用するGCSのバケットを作成

```bash
$ BUCKET_NAME=<your bucket name>
$ gsutil mb ${BUCKET_NAME}
```

#### このリポジトリをダウンロード

```bash
$ git clone https://github.com/grasys/gcp-mastodon.git
```

#### スタートアップスクリプトをGCSへアップロード

```bash
$ cd gcp-mastodon/startup-scripts
$ gsutil cp postgresql/setup-master.sh \
  ${BUCKET_NAME}/psql/master.sh
$ gsutil cp postgresql/setup-slave.sh \
  ${BUCKET_NAME}/psql/slave.sh
$ gsutil cp redis-server/setup.sh \
  ${BUCKET_NAME}/redis/setup.sh
$ gsutil cp web/setup-first-instance.sh \       
  ${BUCKET_NAME}/web/setup.sh
```

## redisを作る

```bash
$ gcloud compute instances create prd-redis001 \
  --machine-type n1-standard-1 \
  --tags redis \
  --zone asia-northeast1-a \
  --image-project debian-cloud \
  --image debian-8-jessie-v20170327 \ 
  --scopes cloud-platform \
  --metadata startup-script-url=gs://${BUCKET_NAME}/redis/setup.sh
```

## DBを作る

マスタ/スレーブレプリケーションを作ります。

### ディスクを作る

```bash
$ gcloud compute disks create prd-db001-data --project grasys-mastodon \
  --size 100GB --type pd-ssd --zone asia-northeast1-a
$ gcloud compute disks create prd-db002-data --project grasys-mastodon \
  --size 100GB --type pd-ssd --zone asia-northeast1-b
```

### インスタンスを作る

マスタ

```bash
$ gcloud compute instances create prd-db001 \
  --machine-type n1-standard-2 \
  --tags db,master \
  --zone asia-northeast1-a \
  --image-project debian-cloud \
  --image debian-8-jessie-v20170327 \
  --scopes cloud-platform \
  --metadata startup-script-url=gs://${BUCKET_NAME}/psql/master.sh
```

スレーブ

```bash
$ gcloud compute instances create prd-db002 \
  --machine-type n1-standard-2 \
  --tags db,slave \
  --zone asia-northeast1-b \
  --image-project debian-cloud \
  --image debian-8-jessie-v20170327 \
  --scopes cloud-platform \
  --metadata startup-script-url=gs://${BUCKET_NAME}/psql/slave.sh
```

## GlusterFSクラスタを作る

### ディスクを作る

```bash
$ gcloud compute disks create prd-gluster001-data \
  --project grasys-mastodon \
  --size 100GB \
  --type pd-ssd \
  --zone asia-northeast1-a
$ gcloud compute disks create prd-gluster002-data \
  --project grasys-mastodon \
  --size 100GB \
  --type pd-ssd \
  --zone asia-northeast1-b
$ gcloud compute disks create prd-gluster003-data \
  --project grasys-mastodon \
  --size 100GB \
  --type pd-ssd \
  --zone asia-northeast1-c
```

### インスタンスを作る

```bash
$ gcloud compute instances create prd-gluster001 \
  --project grasys-mastodon \
  --machine-type n1-standard-2 \
  --tags gluster \
  --zone asia-northeast1-a \
  --image-project debian-cloud \
  --image debian-8-jessie-v20170327 \
  --scopes cloud-platform

$ gcloud compute instances create prd-gluster002 \
  --project grasys-mastodon \
  --machine-type n1-standard-2 \
  --tags gluster \
  --zone asia-northeast1-b \
  --image-project debian-cloud \
  --image debian-8-jessie-v20170327 \
  --scopes cloud-platform

$ gcloud compute instances create prd-gluster003 \
  --project grasys-mastodon \
  --machine-type n1-standard-2 \
  --tags gluster \
  --zone asia-northeast1-c \
  --image-project debian-cloud \
  --image debian-8-jessie-v20170327 \
  --scopes cloud-platform
```

### ディスクアタッチ

```bash
$ gcloud compute instances attach-disk prd-gluster001 \
  --disk prd-gluster001-data \
  --project grasys-mastodon \
  --device-name prd-gluster001-data \
  --zone asia-northeast1-a

$ gcloud compute instances attach-disk prd-gluster002 \
  --disk prd-gluster001-data \
  --project grasys-mastodon \
  --device-name prd-gluster002-data \
  --zone asia-northeast1-b

$ gcloud compute instances attach-disk prd-gluster003 \
  --disk prd-gluster001-data \
  --project grasys-mastodon \
  --device-name prd-gluster003-data \
  --zone asia-northeast1-c
```

### 諸々設定

各インスタンスに入って実施してください。

```bash
# アタッチディスクフォーマット
$ sudo mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-${HOSTNAME}-data

# Brick作成、アタッチディスクをマウント
$ sudo mkdir -p /data/brick1
$ sudo sh -c "echo '/dev/disk/by-id/google-${HOSTNAME}-data /data/brick1 ext4 defaults 1 2' >> /etc/fstab"
$ sudo mount -a && mount
$ sudo mkdir -p /data/brick1/media
```

prd-gluster001で実施してください。

```bash
# GlusterFS起動
$ sudo systemctl start glusterfs-server

# 他のGlusterFSと接続
$ sudo gluster peer probe prd-gluster002
$ sudo gluster peer probe prd-gluster003

# Gluster Volume作成/開始
$ sudo gluster volume create media-volume replica 3 transport tcp \
  prd-gluster001:/data/brick1/media \
  prd-gluster002:/data/brick1/media \
  prd-gluster003:/data/brick1/media
$ sudo gluster volume start media-volume
```

## Webサーバ作る

```bash
$ gcloud compute instances create prd-web001 \
  --machine-type n1-standard-2 \
  --tags web \
  --zone asia-northeast1-a \
  --image-project debian-cloud \
  --image debian-8-jessie-v20170327 \
  --scopes cloud-platform \
  --metadata startup-script-url=gs://${BUCKET_NAME}/web/setup.sh
```

## Webクラスタ用のGlobalロードバランサを作る

```bash
# ヘルスチェックを作成
$ gcloud compute http-health-checks create http-web-health-check \
  --description "Health Check for Web cluster."

# バックエンドサービスを作成
$ gcloud compute backend-services create web-cluster-lb \
  --global \
  --protocol HTTP \
  --http-health-checks http-web-health-check

# インスタンスグループを作成
$ gcloud compute instance-groups unmanaged create web-instance-group \
  --zone asia-northeast1-a

# インスタンスグループに追加
$ gcloud compute instance-groups unmanaged add-instances web-instance-group \
  --instances prd-web001 \
  --zone asia-northeast1-a

# バックエンドサービスに追加
$ gcloud compute backend-services add-backend web-cluster-lb \
  --instance-group web-instance-group \
  --instance-group-zone asia-northeast1-a \
  --global

# URLマップを作成
$ gcloud compute url-maps create mastodon-web-lb \
  --default-service web-cluster-lb

# HTTPProxyを作成
$ gcloud compute target-http-proxies create http-web-cluster-lb-proxy \
  --url-map mastodon-web-lb

# 静的IPを取得
$ gcloud compute addresses create web-cluster \
  --global

# フォワーディングルールを作成
$ WEB_CLUSTER_IP=`gcloud compute addresses describe web-cluster --global --format json | jq -r .address`
$ gcloud compute forwarding-rules create http-web-cluster-lb-forwarding-rule \
  --ports 80 \
  --target-http-proxy http-web-cluster-lb-proxy \
  --address ${WEB_CLUSTER_IP} --global
```

## Let's Encriptで証明書を作成する

```bash
# CloudDNSにゾーンとレコードセットを追加
$ gcloud dns managed-zones create mastodonzone \
  --dns-name <your domain>
$ gcloud dns record-sets transaction start -z mastodonzone
$ WEB_CLUSTER_IP=`gcloud compute addresses describe web-cluster --global --format json | jq -r .address`
$ gcloud dns record-sets transaction add -z mastodonzone \
  --name <your domain> --ttl 300 \
  --type A "${WEB_CLUSTER_IP}"

# 証明書の生成
$ sudo systemctl stop nginx
$ sudo apt-get install -y certbot -t jessie-backports
$ sudo certbot certonly \
  --preferred-challenges http \
  --register-unsafely-without-email --agree-tos \
  --standalone -d <your domain name>
```

## HTTPSフォワーディングルールを作る

```bash
# GCPオブジェクトの証明書を作成
$ gcloud compute ssl-certificates create mastodon`date +%Y%m%d` \
  --private-key <path to private key> \
  --certificate <path to certificate>

# HttpsProxyを作成
$ gcloud compute target-https-proxies create https-web-cluster-lb-proxy \
  --ssl-certificate mastodon`date +%Y%m%d` \
  --url-map mastodon-web-lb

# フォワーディングルールを作成
$ WEB_CLUSTER_IP=`gcloud compute addresses describe web-cluster --global --format json | jq -r .address`
$ gcloud compute forwarding-rules create https-web-cluster-lb-forwarding-rule \
  --ports 443 \
  --target-https-proxy https-web-cluster-lb-proxy \
  --address ${WEB_CLUSTER_IP} \
  --global
```

## 画像等のメディア

GlusterFSクラスタをWebサーバにマウントします。

```bash
# GlusterFSクライアントインストール
$ sudo apt-get install -y glusterfs-client

# マウント
$ sudo mkdir /home/mastodon/media
$ sudo mount -t glusterfs -o backupvolfile-server=gluster002,backupvolfile-server=gluster003 prd-gluster001:/media-volume /home/mastodon/media

# メディアファイル用のシンボリックリンク
$ mkdir /home/mastodon/media/{accounts,media_attachments}
$ sudo chown mastodon.mastodon /home/mastodon/media/*
```

## スタートアップスクリプトを削除する

```bash
$ gcloud compute instances remove-metadata prd-web001 \
  --zone asia-northeast1-a \
  --keys startup-script-url
$ gcloud compute instances remove-metadata prd-redis001 \
  --zone asia-northeast1-a \
  --keys startup-script-url
$ gcloud compute instances remove-metadata prd-db001 \
  --zone asia-northeast1-a \
  --keys startup-script-url
$ gcloud compute instances remove-metadata prd-db002 \
  --zone asia-northeast1-b \
  --keys startup-script-url
```

## Webサーバをイメージ化

```bash
$ gcloud compute disks snapshot prd-web001 \
  --snapshot-names prd-web001-`date +%Y%m%d` \
  --zone asia-northeast1-a

$ gcloud compute disks create prd-web001-tmp \
  --source-snapshot prd-web001-`date +%Y%m%d` \
  --zone asia-northeast1-a

$ gcloud compute images create prd-web001-`date +%Y%m%d` \
  --source-disk prd-web001-tmp \
  --source-disk-zone asia-northeast1-a
```

