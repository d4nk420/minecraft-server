#!/bin/bash

DATE=$(date +"%d-%m-%Y")
FILENAME="minecraft-wrld-$DATE.tar.gz"
BACKUPDIR=../mc-backups
MCDIR=$(pwd)
CRONFILE="/etc/cron.d/minecraft-backup"

echo -e "Creating Backup directory..."
mkdir -p $BACKUPDIR
cd $BACKUPDIR
BACKUPFULLPATH=$(pwd)
echo -e "Installing cron..."
cat > $CRONFILE << EOF
0 4 \* \* \* tar -czf $BACKUPFULLPATH/$FILENAME $MCDIR/world*
EOF

echo -e "Making first backup..."
tar -czf $BACKUPDIR/$FILENAME $MCDIR/world*
