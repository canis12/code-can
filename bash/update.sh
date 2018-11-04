#!/bin/bash

function timestamp() {
  while IFS= read -r line; do
    echo [$(date +"%F %T.%N")] $line
  done
}
# redirect the stdout/stderr to screen AND log file
LOG="/var/log/usr/file.log"
DIR=$(mktemp -d)
if [ ${#DIR} == 19 ]; then
  mkfifo ${DIR}/$$-err ${DIR}/$$-out
  # to merge stdout/stderr to log file AND screen
  ( exec tee -a ${LOG} < ${DIR}/$$-out ) &
  ( exec tee -a ${LOG} < ${DIR}/$$-err >&2 ) &
  # redirect stdout/stderr
  exec 1> >( timestamp ${DIR}/$$-out > ${DIR}/$$-out )
  exec 2> >( timestamp ${DIR}/$$-err > ${DIR}/$$-err )
  
  START=$(date +%s)
  echo ">>>START OF OUTPUT<<<"
  
  # check network access, ping gateway
  VAR=0
  time ping -c 5 '192.168.36.1'
  while [ $? != 0 ]; do
    ((VAR++))
    if [ $VAR == 12 ]; then
      exit 1
    fi
    time sleep 300
    time ping -c 5 '192.168.36.1'
  done
  # ping google to check internet access and dns
  NUM=0
  time ping -c 5 'www.google.com'
  while [ $? != 0 ]; do
    ((NUM++))
    if [ $VAR == 12 ]; then
      exit 1
    fi
    time sleep 300
    time ping -c 5 'www.google.com'
  done
  
  # update root DNS server list
  time wget -O ${DIR}/root.hints "https://www.internic.net/domain/named.root"
  FILE1=$(openssl dgst ${DIR}/root.hints)
  FILE2=$(openssl dgst /var/lib/unbound/root.hints)
  if [ ${FILE1:(-64)} != ${FILE2:(-64)} ]; then
    time cp ${DIR}/root.hints /var/lib/unbound/root.hints
  fi
  time rm ${DIR}/root.hints
  
  # update pihole
  time /usr/local/bin/pihole -g
  time /usr/local/bin/pihole -up
  
  # update repositories, software and clear orphaned packages
  time apt-get update
  time apt-get upgrade -y
  time apt-get autoclean
  time apt-get autoremove -y
  time deborphan | xargs apt-get -y remove --purge
  
  echo ">>>END OF OUTPUT<<<"
  END=$(date +%s)
  
  # calculate time taken
  SECONDS=$(echo "$END - $START" | bc)
  if [ $SECONDS > 3600 ]; then
    let "hours=SECONDS/3600"
    let "minutes=(SECONDS%3600)/60"
    let "seconds=(SECONDS%3600)%60"
    echo "Completed in $hours hour(s), $minutes minute(s) and $seconds second(s)" 
  elif [ $SECONDS > 60 ]; then
    let "minutes=(SECONDS%3600)/60"
    let "seconds=(SECONDS%3600)%60"
    echo "Completed in $minutes minute(s) and $seconds second(s)"
  else
    echo "Completed in $SECONDS seconds"
  fi
  
  # remove temporary directory
  rm ${DIR}/$$-err ${DIR}/$$-out
  rm -R ${DIR}
  exit 0
fi
exit 1