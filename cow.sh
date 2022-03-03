#!/bin/bash

curl -L https://github.com/docker/compose/releases/download/$(curl -Ls https://www.servercow.de/docker-compose/latest.php)/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf update
sudo dnf install -y docker-ce docker-ce-cli containerd.io git
sudo systemctl enable docker
sudo systemctl start docker

cd /opt/
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized
./generate_config.sh

###########################################----------------------------------------------------------------

sed -i 's/do-ip6: yes/do-ip6: no/g' data/conf/unbound/unbound.conf
sed -i 's/enable_ipv6: true/enable_ipv6: false/g' docker-compose.yml
sed -i 's/- vmail-index-vol-1/- \/home\/userdata\/vmail-index-vol-1/g' docker-compose.yml
sed -i 's/- vmail-vol-1/- \/home\/userdata\/vmail-vol-1/g' docker-compose.yml
sed -i '1 a API_KEY=4D2917-78C8EA-B06D60-69B6B5-FBDBAA' mailcow.conf
sed -i '2 a API_ALLOW_FROM=172.22.1.1,127.0.0.1' mailcow.conf


cd /opt/mailcow-dockerized
cat >docker-compose.override.yml<<EOL

version: '2.1'
services:

    ipv6nat-mailcow:
      image: bash:latest
      restart: "no"
      entrypoint: ["echo", "ipv6nat disabled in compose.override.yml"]

    portainer-mailcow:
      image: portainer/portainer-ce
      volumes:
        - /var/run/docker.sock:/var/run/docker.sock
        - ./data/conf/portainer:/data
      restart: always
      dns:
        - 172.22.1.254
      dns_search: mailcow-network
      networks:
        mailcow-network:
          aliases:
            - portainer

EOL

cat > data/conf/nginx/portainer.conf <<EOL
upstream portainer {
  server portainer-mailcow:9000;
}

map $http_upgrade $connection_upgrade {
  default upgrade;
  '' close;
}

EOL

cat > data/conf/nginx/site.portainer.custom <<EOL
  location /portainer/ {
    proxy_http_version 1.1;
    proxy_set_header Host              $http_host;   # required for docker client's sake
    proxy_set_header X-Real-IP         $remote_addr; # pass on real client's IP
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout                 900;

    proxy_set_header Connection "";
    proxy_buffers 32 4k;
    proxy_pass http://portainer/;
  }

  location /portainer/api/websocket/ {
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_pass http://portainer/api/websocket/;
  }
EOL

cat > data/conf/postfix/extra.cf <<EOL
smtp_address_preference = ipv4
inet_protocols = ipv4
EOL


# should wait here ;))
docker-compose pull
docker-compose up -d
