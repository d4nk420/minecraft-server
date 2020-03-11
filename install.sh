#!/bin/bash
## v0.7

_step_counter=0
step() {
	_step_counter=$(( _step_counter + 1 ))
	printf '\n\033[1;36m%d) %s\033[0m\n' $_step_counter "$@" >&2  # bold cyan
}

# Enter custom seed here or leave empty for random
SEED="-2143500864"

MCDIR=$(pwd)
PLUGINDIR=$MCDIR/plugins

VERSION="1.15.2"
IMAGE="itzg/minecraft-server"

# Dependencies
step 'Checking Dependencies'
DEPENDENCIES="docker docker-compose"
for _DEP in $DEPENDENCIES, do
	command -v $_DEP
  if [[ $? -ne 0 ]], then
    echo "$_DEP not installed, installing..."
    apt install -y $_DEP 
  else
  	echo "$_DEP already installed, skipping."
  fi
done

# Plugins (make sure they match your version)
# Combine in one var to loop through
VIVECRAFT="https://github.com/jrbudda/Vivecraft_Spigot_Extensions/releases/download/1.14.3r1/Vivecraft_Spigot_Extensions.1.14.4r6.zip"
DYNMAP="http://dynmap.us/builds/dynmap/Dynmap-3.0-beta-10-spigot.jar"
PLUGINS="$VIVECRAFT $DYNMAP"

# Download Plugins
step 'Downloading Plugins'
mkdir -p $PLUGINDIR
for _PLUGIN in $PLUGINS; do
	wget -nc -nd $_PLUGIN -P $PLUGINDIR
done

# Extract plugins if they are zipped
step 'Extracting Plugins'
unzip -n $PLUGINDIR/*.zip -d $PLUGINDIR

# Build env file for mc container
step 'Creating env file for mc container'
cat > ./mc.env << EOF
EULA=TRUE
TYPE=SPIGOT
VERSION=$VERSION
MOTD="Minecraft $VERSION"
EOF
if [[ $SEED != "" ]]; then
  echo "SEED=$SEED" >> ./mc.env
fi

# Get email and domains
step 'Gathering Information for certbot'
echo -e "Please enter your email address for Let's Encrypt\n"
read -p "Leave blank for unsafe LE registration: " EMAIL
echo -e "Please enter the domains you want to secure, seperated by whitespaces\nMake sure you have valid DNS records to this machine!\nRegistration will fail otherwise"
read -p "Domain(s): " DOMAINS

# Create nginx config
step 'Creating nginx configuration file'
mkdir -p data/nginx
set -- $DOMAINS
cat > data/nginx/$1.conf << EOF
server {
    listen 80;
    server_name $DOMAINS;
    
    location / {
        return 301 https://\$host\$request_uri;
    }    
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}
server {
    listen 443 ssl;
    server_name $DOMAINS;
    ssl_certificate /etc/letsencrypt/live/$1/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$1/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    
    location / {
        proxy_pass http://minecraft:8123; 
    }
}
EOF

# Create docker compose file
step 'Creating docker compose file'
cat > ./docker-compose.yml << EOF
version: '3'
services:
  minecraft:
    container_name: minecraft
    image: $IMAGE
    ports: 
      - "25565:25565"
      - "127.0.0.1:8123:8123"
    volumes:
      - .:/data
    env_file:
      - mc.env
    command: "--noconsole"
  certbot:
    container_name: certbot
    image: certbot/certbot
    volumes:
      - ./data/certbot/conf:/etc/letsencrypt
      - ./data/certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait \$\${!}; done;'"
  nginx:
    container_name: nginx
    image: nginx:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./data/nginx:/etc/nginx/conf.d
      - ./data/certbot/conf:/etc/letsencrypt
      - ./data/certbot/www:/var/www/certbot
    command: "/bin/sh -c 'while :; do sleep 6h & wait \$\${!}; nginx -s reload; done & nginx -g \"daemon off;\"'"
EOF

# Create all containers, so nginx doesnt fail
step 'Initializing all containers'
docker-compose up -d

# Initialize nginx and request cert for the given domain
step 'Starting secure webserver'
./init-letsencrypt.sh $EMAIL $DOMAINS

step 'Making sure everything is running' 
docker-compose up -d

# Optional Map backup
step 'Backup'
echo "Do you want daily backups of your minecraft world?"
select yn in Yes No
do
  case $yn in
      Yes) read -p "Where do you want your backup? (Defaults to /srv/mc-backup): " BACKUPDIR
        ./backup.sh $BACKUPDIR
        ;;
      No) echo -e "Ok, run backup.sh if you change your mind"
        exit
        ;;
  esac
done
