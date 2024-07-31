#!/bin/bash
PARAM_ERROR=1
SCAN_TYPE_ERROR=2

#操作系统类型
OS_WINDOWS=0
OS_LINUX=1
OS_UNKNOWN=2
OS_MAC=3

SCRIPTPATH=$(cd $(dirname $0); pwd -P)
NMAP_BINARY=$SCRIPTPATH/nmap
TAG_PATH=$SCRIPTPATH/../config/nmap_work_tag
LOG_DIR=$SCRIPTPATH/../var/log/host_find_script
LOG_FILE=$LOG_DIR/work_`date +'%Y%m%d000000'`.log
MGR_PATH="/sf/edr/manager"
AGT_PATH="/sangfor/edr/agent"
AGT_PATH_NEW="/sf/edr/agent"

g_result_num=0

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

#根据nmap猜测os的功能判断操作系统函数
function os_guess(){
	while read line
	do
		echo $line | grep -i "windows" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			echo $OS_WINDOWS
			return 0
		fi
		
		echo $line | grep -i "linux" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			echo $OS_LINUX
			return 0
		fi

		echo $line | grep -i "Darwin" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			echo $OS_MAC
			return 0
		fi
	done < <(echo "$*" | awk -F '[:,]' '{for(i=2;i<=NF;i++){print $i}}')
	echo $OS_UNKNOWN
	return 1
}

#设置对应ip的操作系统类型
#示例: set_os 192.168.1.1 0(设置192.168.1.1的操作系统为Windows)
function set_os(){
	for((i=0;i<g_result_num;i++));
	do
		if [ "${g_ip[${i}]}" == "$1" ];then
			g_os[$i]=$2
			return 0
		fi
	done
	return 1
}

#对无法准确判断操作系统类型的ip再次进行os探测
function do_os_scan(){
	local os=$OS_UNKNOWN
	while read line
	do
		#获取ip
		echo $line | grep "Nmap scan report for" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			local ip=`echo $line | awk -F '[ ]+' '{print $5}'`
			continue
		fi
		#根据nmap猜测os的功能判断操作系统
		echo $line | grep "Aggressive OS guesses" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			local os=`os_guess $line`
			continue
		fi
		#判断操作系统
		echo $line | grep "OS details" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			echo $line | grep -i "linux" 2>&1 1>/dev/null
			if [ $? -eq 0 ];then
				local os=$OS_LINUX
				continue
			fi
			
			echo $line | grep -i "windows" 2>&1 1>/dev/null
			if [ $? -eq 0 ];then
				local os=$OS_WINDOWS
				continue
			fi
			local os=$OS_UNKNOWN
			continue
		fi
		#设置对应ip的操作系统类型
		echo $line | grep "^[ \t]*$" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			if [ "x$ip" != "x" ];then
				set_os $ip $os
				local ip=""
				local os=$OS_UNKNOWN
			fi
		fi
	done < <($NMAP_BINARY -O --osscan-guess $*)
}

#检查os探测结果，如果存在无法判断的则进行进一步的os探测
function os_check(){
	local need_os_scan_ip=""
	for((i=0;i<g_result_num;i++));
	do
		if [ ${g_os[$i]} -ne $OS_LINUX -a ${g_os[$i]} -ne $OS_WINDOWS ];then
			local need_os_scan_ip="${need_os_scan_ip} ${g_ip[$i]}"
		fi
	done
	
	if [ "x$need_os_scan_ip" == "x" ];then
		return 0
	fi
	
	do_os_scan $need_os_scan_ip
	return 0
}

#根据输入参数进行终端发现
function do_host_find_task(){
	if [ "$3" == "null" ];then
		local cmd_line="$NMAP_BINARY $2 -O --osscan-guess $1"
	else
		local cmd_line="$NMAP_BINARY $2 -O --osscan-guess $1 -p $3"
	fi
	local os=$OS_UNKNOWN
	local ip=""
	local mac=""
	while read line
	do
		#获取ip
		echo $line | grep "Nmap scan report for" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			#local ip=`echo $line | awk -F '[ ]+' '{print $5}'`
			local ip=`echo $line | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'`
			continue
		fi
		#获取mac地址
		echo $line | grep "MAC Address" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			local mac=`echo $line | awk -F '[ ]+' '{print $3}'`
			continue
		fi
		#根据nmap猜测os的功能判断操作系统
		echo $line | grep "Aggressive OS guesses" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			local os=`os_guess $line`
			continue
		fi
		#判断操作系统
		echo $line | grep "OS details" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			echo $line | grep -i "linux" 2>&1 1>/dev/null
			if [ $? -eq 0 ];then
				local os=$OS_LINUX
				continue
			fi
			
			echo $line | grep -i "windows" 2>&1 1>/dev/null
			if [ $? -eq 0 ];then
				local os=$OS_WINDOWS
				continue
			fi
			local os=$OS_UNKNOWN
			continue
		fi
		#输出获取的数据到数组
		echo $line | grep "^[ \t]*$" 2>&1 1>/dev/null
		if [ $? -eq 0 ];then
			if [ "x$ip" != "x" ];then
				g_ip[$g_result_num]=$ip
				g_mac[$g_result_num]=$mac
				g_os[$g_result_num]=$os
				g_result_num=$[g_result_num + 1]
				local os=$OS_UNKNOWN
				local ip=""
				local mac=""
			fi
		fi
	done < <($cmd_line)
}

#扫描结果输出
function output_result(){
	
	for((i=0;i<g_result_num;i++));
	do
		echo "${g_os[$i]};${g_ip[$i]};${g_mac[$i]};"
		log "os:${g_os[$i]};ip:${g_ip[$i]};mac:${g_mac[$i]}"
	done
	unset g_os
	unset g_mac
	unset g_ip
	g_result_num=0
}

#启动时先清理之前的残留的进程
function clear_env(){
	while read line
	do
		local pid=`echo $line | awk -F '[ ]+' '{print $2}'`
		log "kill:${line}"
		if [ -d "/proc/$pid" ];then
			kill "$pid"
		fi
		if [ -d "/proc/$pid" ];then
			kill -9 "$pid"
		fi
	done < <(ps -ef | grep nmap | grep edr | grep -v nmap_work.sh | grep -v nmap_cancel.sh | grep -v nmap)
}

#获取安装路径(/home/sangfor/edr/agent中的/home)
function get_install_path(){
	g_install_path=""
	while read line
	do
		if [ "$line" == "sangfor" ];then
			echo $SCRIPTPATH | grep -q "$line/edr"
			[[ $? -eq 0 ]] && return 0
		fi

		if [ "$line" == "sf" ]; then
			echo $SCRIPTPATH | grep -q "$line/edr"
			[[ $? -eq 0 ]] && return 1
		fi

		g_install_path="${g_install_path}/${line}"
	done < <(echo "$SCRIPTPATH" | awk -F '[/]' '{for(i=2;i<=NF;i++){print $i}}')
}

#构建软链接
function build_link(){
	if [[ -d "/sf/edr" ]] || [[ -d "/sangfor/edr" ]];then
		return 0
	fi

	local dir_name=sangfor
	get_install_path
	if [ $? -eq 1 ]; then
		dir_name=sf
	fi

	if [ ! -d "/${dir_name}" ];then
		ln -s ${g_install_path}/${dir_name} /${dir_name}
	fi
	if [ ! -d "/${dir_name}/edr" ];then
		ln -s ${g_install_path}/${dir_name}/edr /${dir_name}/edr
	fi
}

#检查edr安装路径,如果非默认路径需要建立软链接
function check_path(){
	if [[ "$SCRIPTPATH" != "${MGR_PATH}/bin" && "$SCRIPTPATH" != "${AGT_PATH}/bin" \
			&& "$SCRIPTPATH" != "${AGT_PATH_NEW}/bin" ]];then
		build_link
	fi
}

#执行nmap扫描
function work(){
	while read line
	do
		do_host_find_task $line $s_scan_type $s_ports
		os_check
		output_result
	done < <(echo $s_ip_range | awk -F '[,]' '{for(i=1;i<=NF;i++){print $i}}')
}

#初始化日志
init_log
#检查环境中是否已有扫描任务存在,并创建扫描tag
if [ -f $TAG_PATH ];then
	clear_env
fi
echo $$ > $TAG_PATH

#初始化参数
case $# in
	2)
		s_ports="null"
		;;
	3)
		s_ports=$3
		;;
	*)
		echo "param num error"
		exit $PARAM_ERROR
esac
s_ip_range=$1
case $2 in
	0)
		s_scan_type="-sT"
		;;
	1)
		s_scan_type="-sU"
		;;
	*)
		echo "scan type error"
		exit $SCAN_TYPE_ERROR
esac

check_path
work

#任务完成，清理tag
if [ -f "$TAG_PATH" ];then
	rm -f $TAG_PATH
fi

exit 0
