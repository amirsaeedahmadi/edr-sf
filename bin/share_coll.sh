#!/bin/bash

SMB_CONF="/etc/samba/smb.conf"
NFS_CONF="/etc/exports"

STATE_ON=1
STATE_OFF=0

export LANG=en

function check_samba(){
	if [ ! -f $SMB_CONF ];then
		return 1
	fi
	return 0
}


function samba_coll(){
	local shared_name=""
	local shared_state=$STATE_ON
	while read line
	do
		#空行直接忽略
		echo "$line" | grep -E "^[ \t]*#|^[ \t]*$" > /dev/null 2>&1
		if [ $? -eq 0 ];then
			continue
		fi
		#共享名格式 [edr_package]
		echo "$line" | grep "^[ \t]*\[.*\][ \t]*$" > /dev/null 2>&1
		if [ $? -eq 0 ];then
			#先将上一轮存储的共享路径信息输出
			if [ "x$shared_name" != "x" ];then
				echo "${shared_name};${shared_path};${shared_state};${shared_comment};"
			fi
			local shared_name=""
			local shared_path=""
			local shared_state=$STATE_ON
			local shared_comment=""
			
			local shared_name; shared_name=$(echo "$line" | cut -d '[' -f2 | cut -d ']' -f1)
			#排除特殊的共享名
			if [[ "$shared_name" == "global" || "$shared_name" == "homes" || "$shared_name" == "printers" || "$shared_name" == "print$" ]];then
				local shared_name=""
			fi
			continue
		fi
		#获取路径
		echo "$line" | grep "^[ \t]*path[ \t]*=[ \t]*.*$" > /dev/null 2>&1
		if [ $? -eq 0 ];then
			local shared_path=${line#*=}
			continue
		fi
		#获取启用状态
		echo "$line" | grep "^[ \t]*available[ \t]*=[ \t]*.*$" > /dev/null 2>&1
		if [ $? -eq 0 ];then
			echo "$line" | grep yes > /dev/null 2>&1
			if [ $? -eq 0 ];then
				local shared_state=$STATE_ON
			else
				local shared_state=$STATE_OFF
			fi
			continue
		fi
		#获取共享描述
		echo "$line" | grep "^[ \t]*comment[ \t]*=[ \t]*.*$" > /dev/null 2>&1
		if [ $? -eq 0 ];then
			local shared_comment=${line#*=}
			continue
		fi
	done < $SMB_CONF
	#输出最后一轮共享信息
	if [ "x$shared_name" != "x" ];then
		echo "${shared_name};${shared_path};${shared_state};${shared_comment};"
	fi
}

function nfs_coll(){
	while read line
	do
		#空行直接忽略
		echo "$line" | grep -E "^[ \t]*#|^[ \t]*$" > /dev/null 2>&1
		if [ $? -eq 0 ];then
			continue
		fi
		#nfs共享方式没有共享名,直接取路径最后一节作为共享名
		local shared_path; shared_path=$(echo "$line" | awk -F '[ \t]' '{print $1}')
		local shared_name; shared_name=$(basename "$shared_path")
		echo "${shared_name};${shared_path};$STATE_ON"
	done < $NFS_CONF
	return 0
}

function check_nfs(){
	if [ ! -f $NFS_CONF ];then
		return 1
	fi
	return 0
}
check_samba
if [ $? -eq 0 ];then
	samba_coll
fi
check_nfs
if [ $? -eq 0 ];then
	nfs_coll
fi

