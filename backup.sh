#!/bin/bash

DATE=$(date +"%d-%m-%Y-%H:%M")
FILENAME="minecraft-wrld-$DATE.tar.gz"
BACKUPDIR=../mc-backups
MCDIR=$(pwd)
CRONFILE="/etc/cron.d/minecraft-backup"
BACKUPSCRIPT="mc-backup.sh"

echo -e "Creating Backup directory..."
mkdir -p $BACKUPDIR
cd $BACKUPDIR && BACKUPFULLPATH=$(pwd)
echo -e "Installing cron..."
cat > $CRONFILE << EOF
0 */6 * * * $BACKUPFULLPATH/$BACKUPSCRIPT
EOF

echo -e "Creating backup script"
cat > $BACKUPFULLPATH/$BACKUPSCRIPT << EOF
#!/bin/bash
DATE=\$(date +"%d-%m-%Y-%H:%M")
FILENAME="minecraft-wrld-\$DATE.tar.gz"
BACKUPDIR=$BACKUPFULLPATH
MCDIR=$MCDIR
LIMIT="90"

# Backup
tar -czf \$BACKUPDIR/\$FILENAME \$MCDIR/world*
# Delete files older than \$LIMIT days
find \$BACKUPDIR -name "*.tar.gz" -type f -mtime +\$LIMIT -exec rm -f {} \;
EOF

echo -e "Making executable"
chmod +x $BACKUPFULLPATH/$BACKUPSCRIPT

echo -e "Making first backup..."
$BACKUPFULLPATH/$BACKUPSCRIPT
