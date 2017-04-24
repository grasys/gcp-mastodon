#!/bin/bash

# Production-guidに従い、依存関係をインストール
sudo apt-get update
sudo apt-get install -y imagemagick ffmpeg libpq-dev libxml2-dev libxslt1-dev nodejs file git curl
curl -sL https://deb.nodesource.com/setup_4.x | sudo bash -
sudo apt-get -y install nodejs
sudo npm install -g yarn

# rbenvをインストール
sudo useradd -m -s /bin/bash mastodon
sudo apt-get install -y bzip2 gcc build-essential libreadline-dev
export MASTODON_HOME=/home/mastodon
sudo -u mastodon sh -c "echo \"export PATH=$MASTODON_HOME/.rbenv/bin:$MASTODON_HOME/.rbenv/shims:$PATH\" >> $MASTODON_HOME/.bash_profile"
sudo -u mastodon sh -c "cd $MASTODON_HOME && git clone https://github.com/rbenv/rbenv.git $MASTODON_HOME/.rbenv"
sudo -u mastodon sh -c "cd $MASTODON_HOME && $MASTODON_HOME/.rbenv/bin/rbenv init"
sudo -u mastodon sh -c "cd $MASTODON_HOME && git clone https://github.com/rbenv/ruby-build.git $MASTODON_HOME/.rbenv/plugins/ruby-build"
sudo -u mastodon sh -c "cd $MASTODON_HOME && $MASTODON_HOME/.rbenv/bin/rbenv install 2.4.1"
sudo -u mastodon sh -c "cd $MASTODON_HOME && $MASTODON_HOME/.rbenv/bin/rbenv global 2.4.1"

# mastodonのセットアップ
sudo -u mastodon sh -c "cd $MASTODON_HOME && git clone https://github.com/tootsuite/mastodon.git live"
export MASTODON_TAG=`sudo -u mastodon sh -c "cd $MASTODON_HOME/live && git tag | tail -n 1"`
sudo -u mastodon sh -c "cd $MASTODON_HOME/live && git checkout $MASTODON_TAG"
sudo -u mastodon sh -c "cd $MASTODON_HOME/live && $MASTODON_HOME/.rbenv/shims/gem install bundler"
sudo -u mastodon sh -c "cd $MASTODON_HOME/live && $MASTODON_HOME/.rbenv/shims/bundle install --deployment --without development test"
sudo -u mastodon sh -c "cd $MASTODON_HOME/live && HOME=$MASTODON_HOME yarn install"

# pgpool2をインストール
sudo apt-get install -y pgpool2

# pgpool2の設定
sudo sed -i -e "s/#backend_hostname0[\ ]*=[\ ]*'host1'/backend_hostname0 = 'prd-db001'/g" /etc/pgpool2/pgpool.conf
sudo sed -i -e "s/#backend_port0[\ ]*=[\ ]*5432/backend_port0 = 5432/g" /etc/pgpool2/pgpool.conf
sudo sed -i -e "s/#backend_weight0[\ ]*=[\ ]*1/backend_weight0 = 1/g" /etc/pgpool2/pgpool.conf
sudo sed -i -e "s;#backend_data_directory0[\ ]*=[\ ]*'/data';backend_data_directory0 = '/usr/local/var/postgresql/main';g" /etc/pgpool2/pgpool.conf
sudo sed -i -e "s/#backend_flag0[\ ]*=[\ ]*'ALLOW_TO_FAILOVER'/backend_flag0 = 'ALLOW_TO_FAILOVER'/g" /etc/pgpool2/pgpool.conf
#sudo sed -i -e "s/#backend_hostname1[\ ]*=[\ ]*'host2'/backend_hostname1 = 'prd-db002'/g" /etc/pgpool2/pgpool.conf
#sudo sed -i -e "s/#backend_port1[\ ]*=[\ ]*5433/backend_port1 = 5432/g" /etc/pgpool2/pgpool.conf
#sudo sed -i -e "s/#backend_weight1[\ ]*=[\ ]*1/backend_weight1 = 1/g" /etc/pgpool2/pgpool.conf
#sudo sed -i -e "s;#backend_data_directory1[\ ]*=[\ ]*'/data1';backend_data_directory1 = '/usr/local/var/postgresql/main';g" /etc/pgpool2/pgpool.conf
#sudo sed -i -e "s/#backend_flag1[\ ]*=[\ ]*'ALLOW_TO_FAILOVER'/backend_flag1 = 'ALLOW_TO_FAILOVER'/g" /etc/pgpool2/pgpool.conf
sudo sed -i -e "s/enable_pool_hba[\ ]*=[\ ]*off/enable_pool_hba = on/g" /etc/pgpool2/pgpool.conf
sudo sed -i -e "s/pool_passwd[\ ]*=[\ ]*'pool_passwd'/pool_passwd = ''/g" /etc/pgpool2/pgpool.conf

# pgpool2再起動
sudo systemctl restart pgpool2

# RedisクラスタのIPを取得しておく
sudo apt-get install -y jq
export REDIS_IP=`gcloud compute forwarding-rules describe redis-cluster-lb-forwarding-rule --region asia-northeast1 --format json | jq -r .IPAddress`

# mastodonの設定
sudo -u mastodon sh -c "cp $MASTODON_HOME/live/.env.production.sample $MASTODON_HOME/live/.env.production"
sudo -u mastodon sh -c "sed -i -e \"s/REDIS_HOST=redis/REDIS_HOST=$REDIS_IP/g\" $MASTODON_HOME/live/.env.production"
sudo -u mastodon sh -c "sed -i -e \"s/DB_HOST=db/DB_HOST=localhost/g\" $MASTODON_HOME/live/.env.production"
sudo -u mastodon sh -c "sed -i -e \"s/DB_USER=postgres/DB_USER=mastodon/g\" $MASTODON_HOME/live/.env.production"
sudo -u mastodon sh -c "sed -i -e \"s/DB_NAME=postgres/DB_NAME=mastodon_production/g\" $MASTODON_HOME/live/.env.production"
sudo -u mastodon sh -c "sed -i -e \"s/LOCAL_DOMAIN=example.com/LOCAL_DOMAIN=mastodon.grasys.io/g\" $MASTODON_HOME/live/.env.production"
sudo -u mastodon sh -c "sed -i -e \"s/SMTP_SERVER=smtp.mailgun.org/SMTP_SERVER=smtp.sendgrid.net/g\" $MASTODON_HOME/live/.env.production"
sudo -u mastodon sh -c "sed -i -e \"s/SMTP_PORT=587/SMTP_PORT=2525/g\" $MASTODON_HOME/live/.env.production"

export SECRET_KEY_BASE=`sudo -u mastodon sh -c "cd $MASTODON_HOME/live && HOME=$MASTODON_HOME RAILS_ENV=production $MASTODON_HOME/.rbenv/shims/rake secret"`
sudo -u mastodon sh -c "sed -i -e \"s/^[\ ]*#[\ ]config.secret_key[\ ]*=.*$/  config.secret_key = '$SECRET_KEY_BASE'/g\" $MASTODON_HOME/live/config/initializers/devise.rb"

# 念のためDrop
sudo -u mastodon sh -c "cd $MASTODON_HOME/live && HOME=$MASTODON_HOME RAILS_ENV=production DISABLE_DATABASE_ENVIRONMENT_CHECK=0 $MASTODON_HOME/.rbenv/shims/bundle exec rails db:drop:all"
sudo -u mastodon sh -c "cd $MASTODON_HOME/live && HOME=$MASTODON_HOME RAILS_ENV=production $MASTODON_HOME/.rbenv/shims/bundle exec rails db:setup"
sudo -u mastodon sh -c "cd $MASTODON_HOME/live && HOME=$MASTODON_HOME RAILS_ENV=production $MASTODON_HOME/.rbenv/shims/bundle exec rails assets:precompile"

# SystemdのUnitファイルを設置

sudo sh -c "cat << EOF > /etc/systemd/system/mastodon-web.service
[Unit]
Description=mastodon-web
After=network.target

[Service]
Type=simple
User=mastodon
WorkingDirectory=/home/mastodon/live
Environment=\"RAILS_ENV=production\"
Environment=\"SECRET_KEY_BASE=$SECRET_KEY_BASE\"
Environment=\"PORT=3000\"
ExecStart=/home/mastodon/.rbenv/shims/bundle exec puma -C config/puma.rb
TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
EOF
"
sudo sh -c "cat << EOF > /etc/systemd/system/mastodon-sidekiq.service
[Unit]
Description=mastodon-sidekiq
After=network.target

[Service]
Type=simple
User=mastodon
WorkingDirectory=/home/mastodon/live
Environment=\"RAILS_ENV=production\"
Environment=\"SECRET_KEY_BASE=$SECRET_KEY_BASE\"
Environment=\"DB_POOL=5\"
ExecStart=/home/mastodon/.rbenv/shims/bundle exec sidekiq -c 5 -q default -q mailers -q pull -q push
TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
"
sudo sh -c "cat << EOF > /etc/systemd/system/mastodon-streaming.service
[Unit]
Description=mastodon-streaming
After=network.target

[Service]
Type=simple
User=mastodon
WorkingDirectory=/home/mastodon/live
Environment=\"NODE_ENV=production\"
Environment=\"SECRET_KEY_BASE=$SECRET_KEY_BASE\"
Environment=\"PORT=4000\"
ExecStart=/usr/bin/npm run start
TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
"

sudo systemctl enable /etc/systemd/system/mastodon-*.service
sudo systemctl start mastodon-*.service

# nginxのインストール
sudo apt-get install -y nginx

