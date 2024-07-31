#!/bin/bash

PASS_FILE=/etc/passwd
SHAD_FILE=/etc/shadow
SUDO_FILE=/etc/sudoers
GROUP_FILE=/etc/group

LAST_AREA_HAVE_IP=9
LAST_AREA_HAVE_NO_IP=8

#用户权限root、非root
AUTH_ROOT=3
AUTH_NO_ROOT=2

#账户风险:弱密码
WEAK_PASS=2

export LANG=en

#读取/etc/passwd文件
function read_users(){
	local i=0
	while read line
	do
		user_name[$i]=`echo $line | awk -F "[:]" '{print $1}'`
		uid[$i]=`echo $line | awk -F "[:]" '{print $3}'`
		local login_shell=`echo $line | awk -F "[:]" '{print $7}'`
		local passwd_tmp=`echo $line | awk -F "[:]" '{print $2}'`
		#UID为0的账户为root权限账户
		if [ ${uid[$i]} -eq 0 ];then
			is_root[$i]=$AUTH_ROOT
		else
			is_root[$i]=$AUTH_NO_ROOT
		fi
		#登录shell为/sbin/nologin视为禁止登录账户
		if [ "x$login_shell" == "x/sbin/nologin" ] ; then
			user_state[$i]=0
		else
			user_state[$i]=1
		fi
		#密码为空则视为弱密码账户
		if [ "x$passwd_tmp" == "x" ];then
			user_risk[$i]=$WEAK_PASS
		else
			user_risk[$i]=0
		fi
		
		record_id[$i]=`echo -n ${user_name[$i]} | md5sum | awk -F "[ ]" '{print $1}'`
		
		local i=`expr $i + 1`
	done < $PASS_FILE
	user_num=$i
}

#读取/etc/shadow文件，需要执行read_users函数
function read_shadow(){
	local i=0
	while read line
	do
		local name=`echo $line | awk -F "[:]" '{print $1}'`
		local pass=`echo $line | awk -F "[:]" '{print $2}'`
		local last_mod=`echo $line | awk -F "[:]" '{print $3}'`
		local pass_expire=`echo $line | awk -F "[:]" '{print $5}'`
		
		#获取对应用户在user_name数组中的位置，如果该条数据没找到则丢弃数据
		local location=-1
		if [ "x${user_name[$i]}" == "x${name}" ];then
			local location=${i}
		else
			for((j=0;j<$user_num;j++));
			do
				if [ "x${user_name[$j]}" == "x$name" ];then
					local location=${j}
				fi
			done
			if [ $location -eq -1 ];then
				local i=`expr $i + 1`
				continue
			fi
		fi
		
		pass_life[$location]=$pass_expire
		pwd_mod_time[$location]=$last_mod
		pass_cry[$location]=$pass
		#如果密码为空视为弱密码账户
		if [[ "x$pass" == "x" && ${user_risk[$location]} -lt 5 ]];then
			user_risk[$location]=$WEAK_PASS
		fi
		#用户密码为*或!!视为账户禁用
		if [[ "x$pass" == "x*" || "x$pass" == "x!!" ]];then
			user_state[$i]=0
		fi
		
		local i=`expr $i + 1`
	done < $SHAD_FILE
}

#获取所有用户最后一次登录的时间
function read_last(){
	while read line
	do
		local area_num=`echo $line | awk -F '[ \t]+' '{print NF}'`
		local name=`echo "$line" | awk -F "[ \t]+" '{print $1}'`
		case $area_num in
		$LAST_AREA_HAVE_IP)
				local format_time=`echo "$line" | awk -F '[ \t]+' '{print $4,$5,$6,$7,$8,$9}'`
		;;
		$LAST_AREA_HAVE_NO_IP)
				local format_time=`echo "$line" | awk -F '[ \t]+' '{print $3,$4,$5,$6,$7,$8}'`
		;;
		*)
			continue
		esac
		local timestamp=`date -d "$format_time" +%s`
		for ((i=0;i<user_num;i++));
		do
			if [ "x${user_name[$i]}" == "x$name" ];then
				last_login_time[$i]=$timestamp
				break
			fi
		done
	done < <(lastlog)
}

#标记指定用户为root权限用户
function change_root_right(){
	for ((u_no=0;u_no<$user_num;u_no++));
	do
		if [ "x${user_name[$u_no]}" == "x$1" ];then
			is_root[$u_no]=$AUTH_ROOT
			break
		fi
		
	done
}

#读取/etc/sudoers获取root权限用户
function read_sudoer(){

#获取sudoer规则(剔除别名定义,空行)
	local sudoer_info=`sed '/^#.*\|^ *$\|^Defaults.*$\|^User_Alias.*$\|^Host_Alias.*$\|^Cmnd_Alias.*$\|^Runas_Alias.*$/d' $SUDO_FILE`
	local info_line_num=`echo "$sudoer_info" | wc -l`
	for((i=1;i<=$info_line_num;i++));
	do
		local name_area[$i-1]=`echo "$sudoer_info" | sed -n "${i}p" | awk -F '[=]' '{print $1}'`
		local cmd_area[$i-1]=`echo "$sudoer_info" | sed -n "${i}p" | awk -F '[=]' '{print $2}'`
	done
#获取sudoers文件内的别名
	local user_alias=`sed -n '/^User_Alias.*$/p' $SUDO_FILE`
	local user_alias_num=`echo "$user_alias" | wc -l`
	for((i=1;i<=$user_alias_num;i++));
	do
		local alias_name[$i-1]=`echo "$user_alias" | awk -F '[ =]+' '{print $2}'`
		local alias_memb[$i-1]=`echo "$user_alias" | awk -F '[ =]+' '{print $3}'`
	done
#获取用户组
	local i=0
	while read line
	do
		local group_name[$i]=`echo $line | awk -F '[:]' '{print $1}'`
		local group_memb[$i]=`echo $line | awk -F '[:]' '{print $4}'`
		local i=`expr $i + 1`
	done < $GROUP_FILE
	local group_num=$i
#获取能够通过sudo提权的用户

	for((i=0;i<$info_line_num;i++));
	do
		local right_target=`echo "${cmd_area[$i]}" | awk -F '[()]+' '{print $2}'`
		#权限目标非root或者ALL权限跳过
		echo "$right_target" | grep -E 'root|ALL' >/dev/null 2>&1
		if [ $? -ne 0 ];then
			continue
		fi
		local ugroup_name=`echo "${name_area[$i]}" | awk -F '[ \t]+' '{print $1}'`
		
		# 授权用户为%wheel代表wheel用户组得到授权
		echo "$ugroup_name" | grep -q "^%.*"
		if [ $? -eq 0 ];then
			for ((j=0;j<$group_num;j++));
			do
				if [ "$ugroup_name" != "%${group_name[$j]}" ];then
					continue
				fi
				change_root_right ${group_name[$j]}
				
				if [ "x${group_memb[$j]}" == "x" ];then
					continue
				fi
				local group_memb_num=`echo "${group_memb[$j]}" | awk -F '[,]' '{print NF}'`
				for ((k=1;k<=$group_memb_num;k++));
				do
					change_root_right `echo "${group_memb[$j]}" | awk -F '[,]' '{print $"'$k'"}'`
				done
			done
			continue
		fi
		
		# 授权用户为ASFD_123这种大写下划线数字混合则为/etc/sudoers文件定义的别名
		echo "$ugroup_name" | grep -q "^[A-Z][A-Z0-9_]*$"
		if [ $? -eq 0 ];then
			for((j=0;j<$user_alias_num;j++));
			do
				if [ "x${alias_name[$j]}" == "x$ugroup_name" ];then
					local alias_memb_num=`echo "$alias_memb" | awk -F '[,]' '{print NF}'`
					for ((k=1;k<=$alias_memb_num;k++));
					do
						change_root_right `echo "$alias_memb" | awk -F '[,]' '{print $"'$k'"}'`
					done
					
				fi
			done
		fi
		
		change_root_right $ugroup_name
	done
}

#读取group文件将root用户组的用户标为root权限
function read_group(){
	while read line
	do
		local group_meb=''
		local group_name=`echo "$line" | awk -F '[:]' '{print $1}'`
		if [ "x$group_name" == "xroot" ];then
			group_meb=`echo "$line" | awk -F '[:]' '{print $4}'`
			break
		fi
	done < $GROUP_FILE
	
	if [ "x$group_meb" == "x" ];then
		return 0
	fi
	
	while read line
	do
		change_root_right "$line"
	done < <(echo "$group_meb" | awk -F '[,]' '{for(i=1;i<=NF;i++){print $i}}')
}

read_users
read_shadow
read_last
read_sudoer
read_group
#read_login

for ((i=0;i<user_num;i++));
do
	echo "NO.${i};${user_name[$i]};${pass_cry[$i]};${is_root[$i]};${uid[$i]};${user_state[$i]};${user_risk[$i]};${pass_life[$i]};${pwd_mod_time[$i]};${last_login_time[$i]};${record_id[$i]}"
done

