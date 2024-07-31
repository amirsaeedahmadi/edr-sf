#!/bin/bash

SCRIPTPATH=$(cd $(dirname $0); pwd -P)
NMAP_WORK_TAG=$SCRIPTPATH/../config/nmap_work_tag
LOG_DIR=$SCRIPTPATH/../var/log/host_find_script
LOG_FILE=$LOG_DIR/cancel_`date +'%Y%m%d000000'`.log
SCRIPT_NAME="nmap_work.sh"
CANCEL_SCRIPT_NAME="nmap_cancel.sh"

#日志函数
function log(){
	echo "[`date +'%F %T'`]:$@" >> ${LOG_FILE}
}

# 日志限制函数
function limit_log(){
	local total_logs="${LOG_DIR}/cancel_*"
	local total_count=`ls -lh ${total_logs} 2>/dev/null | wc -l`

	if [ ${total_count} -gt 5 ]; then
		local delete_log=`ls -lh ${total_logs} | head -n 1 | awk '{ print $NF }'`
		if [ "X${delete_log}" != "X${LOG_FILE}" ]; then
			rm -f ${delete_log}
		fi
	fi
}

#日志初始化
function init_log(){
	if [ ! -d $LOG_DIR ];then
		mkdir -p $LOG_DIR
	fi
	log "log init"
	limit_log
}

function clear_nmap_binary(){
	while read line
	do
		local pid=`echo $line | awk -F '[ ]+' '{print $2}'`
		log "kill:${line}"
		if [ -d "/proc/$pid" ];then
			kill "$pid"
		fi
		if [ -d "/proc/$pid"  ];then
			kill -9 "$pid"
		fi
	done < <(ps -ef | grep nmap | grep edr | grep -v grep | grep -v $SCRIPT_NAME | grep -v $CANCEL_SCRIPT_NAME)
}

function clear_nmap_script(){
	while read line
	do
		local pid=`echo $line | awk -F '[ ]+' '{print $2}'`
		log "kill:${line}"
		if [ -d "/proc/$pid" ];then
			kill "$pid"
		fi
		if [ -d "/proc/$pid"  ];then
			kill -9 "$pid"
		fi
	done < <(ps -ef | grep -v grep | grep $SCRIPT_NAME | grep edr)

}

#初始化日志
init_log
if [ -f $NMAP_WORK_TAG ];then
	clear_nmap_binary
	clear_nmap_script
	if [ -f $NMAP_WORK_TAG ];then
		rm -f "$NMAP_WORK_TAG"
	fi
fi


