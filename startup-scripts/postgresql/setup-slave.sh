#!/bin/bash

# Diskアタッチ
gcloud compute instances attach-disk ${HOSTNAME} \
--disk ${HOSTNAME}-data \
--project grasys-mastodon \
--device-name ${HOSTNAME}-data \
--zone asia-northeast1-b

# Diskフォーマット
sudo mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-${HOSTNAME}-data

# autofsをインストール
sudo apt-get install -y autofs

# autofsの設定
sudo mkdir /var/autofs
sudo sh -c "echo '/var/autofs    /etc/auto.postgresql  --timeout 3600' >> /etc/auto.master"
sudo sh -c "echo \"google-${HOSTNAME}-data  -fstype=ext4    :/dev/disk/by-id/google-${HOSTNAME}-data\" > /etc/auto.postgresql"

# postgresqlをインストール
sudo apt-get install -y postgresql postgresql-contrib

# pgpool2ライブラリをインストール
sudo apt-get install -y postgresql-9.4-pgpool2

# データ用ディスクをマウント
sudo systemctl restart autofs
sudo mkdir -p /var/autofs/google-${HOSTNAME}-data/postgresql/main
sudo chown -R postgres.postgres /var/autofs/google-${HOSTNAME}-data/postgresql
sudo mkdir /usr/local/var
sudo ln -s /var/autofs/google-${HOSTNAME}-data/postgresql /usr/local/var/postgresql
sudo chown -R postgres.postgres /usr/local/var/postgresql

# data directoryを変更
sudo systemctl stop postgresql
sudo -u postgres sh -c "/usr/lib/postgresql/9.4/bin/initdb --pgdata /usr/local/var/postgresql/main"
sudo sed -i -e "s;data_directory[\ ]*=[\ ]*'/var/lib/postgresql/9.4/main';data_directory = '/usr/local/var/postgresql/main';g" /etc/postgresql/9.4/main/postgresql.conf

# postgres Linuxユーザの以外のユーザがログインできるようにする
sudo sed -i -e 's;^host[\ ]*all[\ ]*all[\ ]*127.0.0.1/32[\ ]*md5;host    all             all             10.146.0.0/20            trust;g' /etc/postgresql/9.4/main/pg_hba.conf

# dbのセキュリティを高めるためにidentdをインストール
sudo apt-get install -y pidentd
sudo systemctl enable pidentd
sudo systemctl start pidentd
sudo systemctl stop postgresql

# レプリケーション設定
sudo sed -i -e "s/#listen_addresses[\ ]*=[\ ]*'localhost'/listen_addresses = '*'        /g" /etc/postgresql/9.4/main/postgresql.conf
sudo sed -i -e "s/#hot_standby[\ ]*=[\ ]*off/hot_standby = on /g" /etc/postgresql/9.4/main/postgresql.conf
sudo sed -i -e "s/#logging_collector[\ ]*=[\ ]*off/logging_collector = on       /g" /etc/postgresql/9.4/main/postgresql.conf
sudo sed -i -e "s/#log_min_duration_statement[\ ]*=[\ ]*-1/log_min_duration_statement = 250       /g" /etc/postgresql/9.4/main/postgresql.conf
sudo sed -i -e "s/#log_checkpoints[\ ]*=[\ ]*off/log_checkpoints = on/g" /etc/postgresql/9.4/main/postgresql.conf
sudo sed -i -e "s/#log_lock_waits[\ ]*=[\ ]*off/log_lock_waits = on/g" /etc/postgresql/9.4/main/postgresql.conf
sudo sed -i -e "s/#wal_level[\ ]*=[\ ]*minimal/wal_level = hot_standby/g" /etc/postgresql/9.4/main/postgresql.conf
sudo sed -i -e "s/#max_wal_senders[\ ]*=[\ ]*0/max_wal_senders = 3/g" /etc/postgresql/9.4/main/postgresql.conf
sudo sed -i -e 's;^#host[\ ]*replication[\ ]*postgres[\ ]*127.0.0.1/32[\ ]*md5;host    replication     postgres        10.146.0.0/20           trust;g' /etc/postgresql/9.4/main/pg_hba.conf
sudo rm -rf /usr/local/var/postgresql/main
sudo -u postgres sh -c "/usr/lib/postgresql/9.4/bin/pg_basebackup -h prd-db001 -D /usr/local/var/postgresql/main -X stream --progress -U postgres -R"
sudo -u postgres sh -c "cat << EOF > /usr/local/var/postgresql/main/recovery.conf
standby_mode = on
primary_conninfo = 'user=postgres host=prd-db001 port=5432'
EOF
"

# postgresql再起動
sudo systemctl start postgresql
