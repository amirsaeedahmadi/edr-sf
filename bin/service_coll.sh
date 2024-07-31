#!/bin/bash

#服务状态:停止、启动和暂停
STATUS_STOP=0
STATUS_START=1
STATUS_PAUSE=2


#测试是否存在systemctl指令
command -v systemctl > /dev/null 2>&1
g_systemctl_flag=$?

#设置语言为英文
export LANG=en

#############################################
#获取指令为service --status-all
#获取结果有三种:
#rpc.statd (pid  1396) 正在运行...
#irqbalance (pid 1852) is running...
#[ + ]  acpid
#############################################
function service_method(){
	check_service
	if [ $? -eq 0 ];then
		decode_service_B
	else
		decode_service_A
	fi
}

#判断service --status-all的返回值格式是否为 [ + ]  acpid如果符合格式返回0，不符合格式返回1
function check_service(){
	while read line
	do
		echo "$line" | grep -Eoe "^\[ [?+-] \].+$" > /dev/null 2>&1
		if [ $? -ne 0 ];then
			return 1
		fi
	done < <(service --status-all)
	return 0
}

#该函数适配以下两种格式
#rpc.statd (pid  1396) 正在运行...
#irqbalance (pid 1852) is running...
function decode_service_A(){
	while read line
	do
		local service_name; service_name=$(echo "$line" | awk -F '[ ]+' '{print $1}')
		echo "$line" | grep pid > /dev/null 2>&1
		if [ $? -eq 0 ];then
			echo "${service_name};${STATUS_START}"
			continue
		fi
		#没有pid的情况需要判断服务的状态(0为正在运行,3为已停止)
		service "${service_name}" status > /dev/null 2>&1
		local service_status=$?
		if [ $service_status -eq 3 ];then
			echo "${service_name};${STATUS_STOP}"
		elif [ $service_status -eq 0 ];then
			echo "${service_name};${STATUS_START}"
		fi
	done < <(service --status-all)
}

#该函数适配以下格式
#[ + ]  acpid
function decode_service_B(){
	while read -r status service_name
	do
		if [ "$status" == "+" ];then
			echo "${service_name};${STATUS_START}"
			continue
		fi
		
		if [[ "$status" == "-" || "$status" == "?" ]];then
			service "$service_name" status | grep running > /dev/null 2>&1
			if [ $? -eq 0 ];then
				echo "${service_name};${STATUS_START}"
				continue
			fi
			echo "${service_name};${STATUS_STOP}"
		fi
	done < <(service --status-all 2>&1 | awk -F '[ ]+' '{print $3,$5}')
}

#适配systemctl指令
#systemd-initctl.service                 loaded inactive dead    /dev/initctl Compatibility Daemon
function systemctl_method(){
	systemctl --full >/dev/null 2>&1
	if [ $? -eq 0 ];then
		local cmdline='systemctl list-units --type=service --all --full'
	else
		local cmdline='systemctl list-units --type=service --all'
	fi

	while read -r service_name load_status active_status sub_status
	do
		local service_name=${service_name%.*}      #从右向左截取第一个.前的字符
		#running为正在运行,exited为已暂停,dead为已停止
		if [[ "$sub_status" == "running" || "$sub_status" == "start" ]];then
			echo "${service_name};${STATUS_START}"
		elif [ "$sub_status" == "exited" ];then
			echo "${service_name};${STATUS_PAUSE}"
		elif [[ "$sub_status" == "dead" || "$sub_status" == "failed" ]];then
			echo "${service_name};${STATUS_STOP}"
		fi
		
	done < <($cmdline | sed 's/^[^A-Za-z0-9]*//g' | awk -F '[ ]+' '{print $1,$2,$3,$4}')
}

if [ $g_systemctl_flag -eq 0 ];then
	systemctl_method
else
	service_method
fi

