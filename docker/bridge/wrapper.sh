#!/bin/bash
# Remove statefile (might contain incompatible key)
rm -f /var/lib/tor/pt_state/drivel_*
# Used to dump runtime arguments and env
export LOGFILE=/tmp/logname
echo `env` > $LOGFILE-env
echo "$@" >> $LOGFILE-arguments
tee -a $LOGFILE-stdin | /usr/bin/lyrebird --enableLogging --logLevel INFO 2>&1 | tee -a $LOGFILE-stdout
