#!/bin/bash
# Used to dump runtime arguments and env, and start Delve
cd /lyrebird
export LOGFILE=/tmp/logname
echo `env` > $LOGFILE-env
echo "$@" >> $LOGFILE-arguments
tee -a $LOGFILE-stdin | dlv --listen=:35759 --log-dest=$LOGFILE-dlv --headless=true debug /lyrebird/cmd/lyrebird 2>&1 | tee -a $LOGFILE-stdout
