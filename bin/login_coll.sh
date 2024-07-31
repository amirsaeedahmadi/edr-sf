#!/bin/bash

PASS_FILE=/etc/passwd
LOGIN_TMP_FILE=/tmp/login_temp_data
LOGIN_FAILED_TMP_FILE=/tmp/login_failed_temp_data
LOGIN_STORE_FILE=/tmp/login_tmp
LOGIN_FAILED_FILE=/var/log/btmp
NORMAL_AREA_NUM=15
LOGIN_SUCCESS=1
LOGIN_FAILED=0
MAX_RECORD_NUM=20000
MERGE_LIM=10
DAY_SEC=86400
HOUR_SEC=3600
MIN_SEC=60


export LANG=en

#使用自带获取日志命令
SCRIPTPATH=$(cd $(dirname $0); pwd -P)
NEW_LAST_CMD=${SCRIPTPATH}/newlast

#last日志读取函数
function last_log_read(){
#############################################
#last输出的日志分为以下几种，对应的字段数量在登录ip为空时数量-1
#仍在登录			11  -1
#完整正常日志		15  -1
#reboot				16
#异常下线			11  -1
#文件末尾信息		7
#############################################
	local area_num=`echo $* | awk -F '[ ]+' '{print NF}'`
	#排除日志的空行以及最后的注脚
	if (( $area_num <= 7 ));then
		return 1
	fi
	
	g_type=`echo $* | awk -F '[ ]+' '{print $2}'`
	#去除系统重启日志
	if [ "x$g_type" == "xsystem" ];then
		return 1
	fi
	
	g_user_name=`echo $* | awk -F '[ ]+' '{print $1}'`
	
	if [[ $area_num -eq 10 || $area_num -eq 14 ]];then
		g_ip=""
		local format_time=`echo $* | awk -F '[ ]+' '{print $3,$4,$5,$6,$7}'`
		g_login_time=`date -d "$format_time" +%s`
		case $area_num in
			14)
				local format_time=`echo $* | awk -F '[ ]+' '{print $9,$10,$11,$12,$13}'`
				g_logout_time=`date -d "$format_time" +%s`
			;;
			*)
				g_logout_time=""
			;;
		esac
	else
		g_ip=`echo $* | awk -F '[ ]+' '{print $3}'`
		format_time=`echo $* | awk -F '[ ]+' '{print $4,$5,$6,$7,$8}'`
		g_login_time=`date -d "$format_time" +%s`
		case $area_num in
			15)
				local format_time=`echo $* | awk -F '[ ]+' '{print $10,$11,$12,$13,$14}'`
				g_logout_time=`date -d "$format_time" +%s`
			;;
			*)
				g_logout_time=""
			;;
		esac
	fi
	return 0
}

#部分系统没有last指令没有-F选项，所以提供一个对last指令数据进行解析的函数(不使用last -F选项会使时间精度下降)
#########################################################
#正常情况(登入登出)				10			-1(本地登录没有ip)
#仍在登录						10			-1(本地登录没有ip)
#异常退出(关机、下线)			10			-1(本地登录没有ip)
#系统重启						11
#文件末尾信息					7
#########################################################
function last_log_read_lower(){
	local area_num=`echo $* | awk -F '[ ]+' '{print NF}'`
	#排除空行以及最后的注脚
	if (( $area_num <= 7 ));then
		return 1
	fi
	
	g_type=`echo $* | awk -F '[ ]+' '{print $2}'`
	#去除系统重启日志
	if [ "x$g_type" == "xsystem" ];then
		return 1
	fi
	
	if(( $area_num == 9 ));then
		g_ip=""
		local format_time=`echo $* | awk -F '[ ]+' '{print $3,$4,$5,$6}'`
		local during_time=`echo $* | awk -F '[ ]+' '{print $9}'`
	elif (( $area_num == 10 ));then
		g_ip=`echo $* | awk -F '[ ]+' '{print $3}'`
		local format_time=`echo $* | awk -F '[ ]+' '{print $4,$5,$6,$7}'`
		local during_time=`echo $* | awk -F '[ ]+' '{print $10}'`
	else
		return 1
	fi
	
	g_user_name=`echo $* | awk -F '[ ]+' '{print $1}'`
	g_login_time=`date -d "$format_time" +%s`
	analyse_during_time "$during_time"
	if [ $? -ne 0 ];then
		g_logout_time=""
		return 0
	fi
	g_logout_time=`expr $g_login_time + $g_during_time`
	
	return 0
}

#解析last指令传回的登录持续时间
function analyse_during_time(){
	if [ "x$1" == "xin" ];then
		return 1
	fi
	local area_num=`echo "$1" | awk -F '[()+:]' '{print NF}'`
	if (( $area_num == 5 ));then
		local days=`echo "$1" | awk -F '[()+:]' '{print $2}'`
		local hours=`echo "$1" | awk -F '[()+:]' '{print $3}'`
		local minutes=`echo "$1" | awk -F '[()+:]' '{print $4}'`
		g_during_time=`expr $days \* $DAY_SEC + $hours \* $HOUR_SEC + $minutes \* $MIN_SEC`
	elif (( $area_num == 4 ));then
		local hours=`echo "$1" | awk -F '[()+:]' '{print $2}'`
		local minutes=`echo "$1" | awk -F '[()+:]' '{print $3}'`
		g_during_time=`expr $hours \* $HOUR_SEC + $minutes \* $MIN_SEC`
	else
		return 1
	fi
	return 0
}

#读取登录成功日志
function read_login(){
	#echo "" > $LOGIN_STORE_FILE

	${NEW_LAST_CMD} -wF -$MAX_RECORD_NUM > $LOGIN_TMP_FILE

	local i=0
	while read line
	do
		last_log_read $line

		if [[ $? -ne 0 ]];then
			continue
		fi
		local account_name=$g_user_name
		local source_ip=$g_ip
		local login_type=$g_type
		local login_time=$g_login_time
		local logout_time=$g_logout_time
		local login_result=$LOGIN_SUCCESS
		echo "${account_name};${source_ip};${login_type};${login_time};${logout_time};${login_result}" 
		
		i=`expr $i + 1`
		if (( $i > $MAX_RECORD_NUM ));then
			break
		fi
	done < $LOGIN_TMP_FILE
	record_num=$i
}

function read_active_users(){
	local i=0
	while read line
	do
		g_users[$i]=`echo $line | awk -F "[:]" '{print $1}'`
		local i=`expr $i + 1`
	done < $PASS_FILE
	g_user_num=$i
}

#读取登录失败的日志，由于登录日志的量可能比较多采取写入文件+逐行读取的方式读取失败日志，并且通过队列以一分钟失败10次的规则归并日志
function read_login_failed(){
	for((user_no=0;user_no<$g_user_num;user_no++));
	do
		${NEW_LAST_CMD} -wF -f ${LOGIN_FAILED_FILE} -${MAX_RECORD_NUM} ${g_users[$user_no]} > $LOGIN_FAILED_TMP_FILE
		
		local i=0
		local q_head=0
		local q_tail=-1
		while read line
		do
			last_log_read $line

			if [ $? -ne 0 ];then
				continue
			fi
			
			local new_tail=`expr $q_tail + 1`
			local new_tail=`expr $new_tail % 20`
			
			local account_name[$new_tail]=$g_user_name
			local login_type[$new_tail]=$g_type
			local source_ip[$new_tail]=$g_ip
			local login_time[$new_tail]=$g_login_time
			local login_result[$new_tail]=$LOGIN_FAILED
			
			local q_tail=$new_tail
			local q_len=`expr $q_tail - $q_head + 1`
			if (($q_len < 0));then
				q_len=`expr $q_len + 20`
			fi
			#队列中记录小于10条
			if (($q_len < 10 && $q_len >= 1));then
				#新进入队列一条记录与队头的记录相差60s以上则队头出队
				if ((${login_time[$q_head]} - ${login_time[$q_tail]} > 60 ));then
					echo "${account_name[$q_head]};${source_ip[$q_head]};${login_type[q_head]};${login_time[q_head]};;${login_result[q_head]}" 
				local i=`expr $i + 1`
				local q_head=`expr $q_head + 1`
				local q_head=`expr $q_head % 20`
				fi
			#队列中记录大于10条
			elif (($q_len >= 10));then
				#新记录时间与队头记录时间相差超过60s则执行归并
				if ((${login_time[$q_head]} - ${login_time[$q_tail]} > 60 ));then
					echo "${account_name[$q_head]};${source_ip[$q_head]};${login_type[q_head]};${login_time[q_head]};;${login_result[q_head]}"
					local i=`expr $i + 1`
					local q_head=$q_tail
				elif ((${login_time[$q_head]} - ${login_time[$q_tail]} < 0 ));then
					echo "find time compare error!"
				#与队头记录时间差小于60s的记录可以直接丢弃(视为被归并)
				else
					local q_tail=`expr $q_tail - 1`
					if (( $q_tail < 0 ));then
						local q_tail=`expr $q_tail + 20`
					fi
				fi
			fi
		done < $LOGIN_FAILED_TMP_FILE
		
		#文件读取完成后将剩余数据输入结果文件
		#日志为空直接跳过
		if (($q_head == 0 && $q_tail == -1));then
			continue
		fi
		
		if (($q_tail < $q_head));then
			for((j=$q_head;j<20;j++));
			do
				echo "${account_name[$j]};${source_ip[$j]};${login_type[j]};${login_time[j]};;${login_result[j]}" 
				i=`expr $i + 1`
			done
			
			for((j=0;j<$q_tail;j++));
			do
				echo "${account_name[$j]};${source_ip[$j]};${login_type[j]};${login_time[j]};;${login_result[j]}" 
				i=`expr $i + 1`
			done
		else
			for((j=$q_head;j<=$q_tail;j++));
			do
				echo "${account_name[$j]};${source_ip[$j]};${login_type[j]};${login_time[j]};;${login_result[j]}" 
				i=`expr $i + 1`
			done
		fi
		record_num=`expr $i + $record_num`
	done
}

if [ -f $LOGIN_STORE_FILE ];then
	rm -f "$LOGIN_STORE_FILE"
fi

if [ -f $LOGIN_FAILED_TMP_FILE ];then
	rm -f "$LOGIN_FAILED_TMP_FILE"
fi

if [ -f $LOGIN_TMP_FILE ];then
	rm -f "$LOGIN_TMP_FILE"
fi

read_login
read_active_users
read_login_failed

# last_log_read $1
# echo "${g_user_name};${g_type};${g_ip};${g_login_time};${g_logout_time};"

