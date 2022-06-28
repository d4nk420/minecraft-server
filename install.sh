#!/bin/bash
## v1.19
#                                USER VARIABLES                                   #
###################################################################################
# Enter custom seed here or leave empty for random
SEED=""
# Change version to the one you want
VERSION="1.19"

# Plugins (make sure they match your version)
# Combine in one var to loop through, seperated by space
#DYNMAP="https://dynmap.us/builds/dynmap/Dynmap-3.1-spigot.jar"
FABRIC_API="https://media.forgecdn.net/files/3358/619/fabric-api-0.36.0%2B1.17.jar"
DYNMAP="https://dynmap.us/builds/dynmap/Dynmap-3.2-beta-2-fabric-1.17.jar"
VOICECHAT="https://media.forgecdn.net/files/3377/99/voicechat-fabric-1.17-1.4.5.jar"
PLUGINS="$FABRIC_API $DYNMAP $VOICECHAT"
###################################################################################

if [ `whoami` != 'root' ]
  then
    echo "You must be root to run this."
    exit 1
fi

echo -e "\n\n\nATTENTION: THIS SCRIPT USES APT TO GET ITS DEPENDENCIES!\nRUN IT ON UBUNTU/DEBIAN OR REWRITE THE DEPENDENCIES INSTALL TO SUITE YOUR DISTRIBUTION.\n\n\n"
sleep 2
echo -e "##########################################################################"
echo -e "#                                                                        #"
echo -e "#       Welcome to this guided minecraft docker installation.            #"
echo -e "#                                                                        #"
echo -e "##########################################################################"
sleep 1

_step_counter=0
step() {
	_step_counter=$(( _step_counter + 1 ))
	printf '\n\033[1;36m%d) %s\033[0m\n' $_step_counter "$@" >&2  # bold cyan
}
# fixed vars
MCDIR=$(pwd)
PLUGINDIR=$MCDIR/mods
IMAGE="itzg/minecraft-server"

# Dependencies
step 'Checking Dependencies'
DEPENDENCIES="docker docker-compose zip wget"
for _DEP in $DEPENDENCIES; do
  if ! command -v $_DEP; then
    echo "$_DEP not installed, installing..."
    apt install -y $_DEP 
  else
  	echo "$_DEP already installed, skipping."
  fi
done

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
TYPE=FABRIC
VERSION=$VERSION
MOTD="Minecraft $VERSION"
EOF
if [[ $SEED != "" ]]; then
  echo "SEED=$SEED" >> ./mc.env
fi
echo -e "done...\n"

# Ask user if a webserver with dynmap should be set up
step 'Webserver Setup'
NGINXINSTALL=0
echo -e "Do you have set up a valid DNS record to this machines public IP adress and want a browser map of your minecraft world?"
select nginxyn in Yes No
do
  case $nginxyn in
      Yes) echo -e "Creating docker-compose with nginx...\n"
      	NGINXINSTALL=1
	break
        ;;
      No) echo -e "Ok, run this script again and choose yes if you decide otherwise... \nCreating docker compose without nginx...\n"
	break
        ;;
      *) echo "Invalid Input. Choose Yes (1) or No (2)"
	;;
  esac
done

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
    restart: always
EOF
echo -e "done...\n"

# domain, certbot and nginx config stuff
if [ $NGINXINSTALL -eq 1 ]; then
	step 'Adding nginx and certbot to config'
	cat >> ./docker-compose.yml << EOF
  certbot:
    container_name: certbot
    image: certbot/certbot
    volumes:
      - ./data/certbot/conf:/etc/letsencrypt
      - ./data/certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait \$\${!}; done;'"
    restart: always
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
    restart: always
EOF
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

	# Create minecraft container, so nginx doesnt fail
	step 'Initializing minecraft'
	docker-compose up -d --force-recreate minecraft

	# Initialize nginx and request cert for the given domain
	step 'Starting secure webserver'
	./init-letsencrypt.sh $EMAIL $DOMAINS
fi

step 'Starting all the docker containers' 
docker-compose up -d

# Optional Map backup
step 'Backup'
echo "Do you want daily backups of your minecraft world?"
select yn in Yes No
do
  case $yn in
      Yes) echo -e "Backups will be saved in ../mc-backups)" 
        ./backup.sh
	exit 0
        ;;
      No) echo -e "Ok, run backup.sh if you change your mind"
        exit 0
        ;;
      *) echo -e "Please choose Yes (1) or No (2)."
  esac
done
