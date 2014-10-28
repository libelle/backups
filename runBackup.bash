#!/bin/bash

echo "----------------------------"
#ps -fp $(pgrep -d, -f backups.rb)
export RUNNINGBACKUP_PROCS=`pgrep -f backups.rb | wc -l`
echo Running backup procs var is $RUNNINGBACKUP_PROCS
if [ "$RUNNINGBACKUP_PROCS" -gt "0" ]
then
        echo `date` backups still running. I\'ll let them finish. 
else
        echo `date` Running backups.
	/home/backups/backups.rb -c /etc/backups/backup-config.yaml -b /etc/backups/backup-tasks-all.yaml
fi
echo "----------------------------"
