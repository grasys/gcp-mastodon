#!/bin/bash

# redis-serverをinstall
sudo apt-get install -y redis-server redis-tools

# redis config修正
sudo sed -i -e 's/^bind[\ ]127.0.0.1/bind 0.0.0.0/g' /etc/redis/redis.conf
sudo sed -i -e 's/^#\smaxmemory\s.*$/maxmemory 2GB/g' /etc/redis/redis.conf

# 念のため再起動
sudo systemctl restart redis-server

