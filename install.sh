#!/bin/bash
## v0.7
#                                USER VARIABLES                                   #
###################################################################################
# Enter custom seed here or leave empty for random
SEED=""
# Change version to the one you want
VERSION="1.16.5"

# Plugins (make sure they match your version)
# Combine in one var to loop through, seperated by space
#DYNMAP="http://dynmap.us/builds/dynmap/Dynmap-3.0-beta-10-spigot.jar"
DYNMAP="http://dynmap.us/builds/dynmap/Dynmap-3.1-spigot.jar"
PLUGINS="$DYNMAP"
###################################################################################

echo -e "\n\n\nATTENTION: THIS SCRIPT USES APT TO GET ITS DEPENDENCIES!\nRUN IT ON UBUNTU/DEBIAN OR REWRITE THE DEPENDENCIES INSTALL TO SUITE YOUR DISTRIBUTION.\n\n\n"
sleep 10

_step_counter=0
step() {
	_step_counter=$(( _step_counter + 1 ))
	printf '\n\033[1;36m%d) %s\033[0m\n' $_step_counter "$@" >&2  # bold cyan
}
# fixed vars
MCDIR=$(pwd)
PLUGINDIR=$MCDIR/plugins
IMAGE="itzg/minecraft-server"

# Dependencies
step 'Checking Dependencies'
DEPENDENCIES="docker docker-compose zip"
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
TYPE=SPIGOT
VERSION=$VERSION
MOTD="Minecraft $VERSION"
EOF
if [[ $SEED != "" ]]; then
  echo "SEED=$SEED" >> ./mc.env
fi

# Ask user if a webserver with dynmap should be set up
echo -e "Do you have set up a valid DNS record to this machines public IP adress and want a browser map of your minecraft world?"
select nginxyn in Yes No
do
  case $nginxyn in
      Yes) echo -e "Creating docker-compose with nginx..."
      	NGINXINSTALL="TRUE"
        ;;
      No) echo -e "Ok, run this script again and choose yes if you decide otherwise... \nCreating docker compose without nginx..."
        break
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

if [ $NGINXINSTALL == "TRUE" ], then
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
fi

# Create minecraft container, so nginx doesnt fail
step 'Initializing minecraft'
docker-compose up -d --force-recreate minecraft

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
      Yes) echo -e "Backups will be saved in ../mc-backups)" 
        ./backup.sh
        ;;
      No) echo -e "Ok, run backup.sh if you change your mind"
        exit
        ;;
  esac
done
