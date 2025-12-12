#!/bin/bash

echo -n "Enter full path of SQL file to restore: "
read SQL_FILE
echo -n "Enter log file name to create (example: restore.log): "
read LOG_FILE

LOG_FILE_PATH="$(pwd)/$LOG_FILE"

MYSQL_USER="beyondsquare"

DB_NAME="bsquare_2021newmis"

echo -n "Enter MySQL password for user '$MYSQL_USER': "

read -s MYSQL_PWD

echo ""
echo "--------------------------------------------------"
echo "Starting Execution of: $SQL_FILE"
echo "Logging output to   : $LOG_FILE_PATH"
echo "Database            : $DB_NAME"
echo "--------------------------------------------------"

script -q -c "mysql -u '$MYSQL_USER' -p'$MYSQL_PWD' $DB_NAME" $LOG_FILE_PATH <<EOF
tee $LOG_FILE_PATH;
source $SQL_FILE;
notee;
exit
EOF

echo ""
echo "--------------------------------------------------"
echo "Execution completed!"
echo "--------------------------------------------------"

tail -500 "$LOG_FILE_PATH"