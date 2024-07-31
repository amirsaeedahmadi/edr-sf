#!/bin/bash
# singleton exec
[ "${EDR_FLOCKER}" != "$0" ] && exec env EDR_FLOCKER="$0" flock -eno "$0.lock" "$0" "$@" || :

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
SCRIPTPATH=$(cd $(dirname $0); pwd -P)
export LD_LIBRARY_PATH=$SCRIPTPATH/../lib

MACHINE_PLAT=$(uname -m)

#如果开启asan内存检测
if [ -f ${SCRIPTPATH}/../lib/libasan.so ];then
    [ ! -d ${SCRIPTPATH}/../var/log/asan ] && mkdir -p ${SCRIPTPATH}/../var/log/asan
    export ASAN_OPTIONS=log_path=$SCRIPTPATH/../var/log/asan/asan.log
fi

#检测被调用的json文件是否单例运行
count1=`ps -ef | grep "clear_timeout_flux_log" | grep -v grep | wc -l`
if [ $count1 -gt 0 ]; then
	echo "Instance is running, $count1, exit!"
	exit 1
fi

#检测是否正在部署mgr
DEPLOY_FILE=/tmp/manager_deploy_flag
if [  -f $DEPLOY_FILE ]; then
	echo "manager is deploying exit!"
	exit 1
fi

black_box_file="/etc/cron.d/eps_blackbox"

#开启系统core，指定目录/data/dump，此处只用来测试，发布后，需要将其删除!!!
###############################################################################
core_switch="CI_SWITCH_FLAG"  #流水线开关，若流水线有相关设置，会修改为CI_SWITCH_ON
if [[ ${core_switch} == "CI_SWITCH_ON" ]];then
     SET_ULIMITED_PARAM="*               soft    core            -1"
     grep "${SET_ULIMITED_PARAM}" /etc/security/limits.conf
     if [ $? -ne 0 ]; then
         echo "${SET_ULIMITED_PARAM}" >> /etc/security/limits.conf
     fi

     grep "/data/dump/core-(%e)-%t-%p" /proc/sys/kernel/core_pattern
     if [ $? -ne 0 ]; then
         mkdir -p /data/dump
         echo "/data/dump/core-(%e)-%t-%p" > /proc/sys/kernel/core_pattern
     fi

     core_uses_pid=`cat /proc/sys/kernel/core_uses_pid`
     if [ "X$core_uses_pid" != "X1" ]; then
         echo "1" > /proc/sys/kernel/core_uses_pid
     fi
fi

# 2022-10-09, 这两个目录如果不赋755权限会导致nginx无法访问json文件，导致终端无法安装（arm银河麒麟MGR）
[ -d /sf/edr/manager/packages ] && chmod -R 755 /sf/edr/manager/packages
[ -d /ac/dc/ldb/bin/web/download/packages ] && chmod -R 755 /ac/dc/ldb/bin/web/download/packages
[ -d /data/download ] && chattr -R -i /data/download/ && chmod -R 755 /data/download

# 清理 /data/dump 目录下多余的 core 文件
function clean_coredump()
{
	# 前置条件：core_pattern 设置为 "/data/dump/core-(%e)-%t-%p"
	grep "/data/dump/core-(%e)-%t-%p" /proc/sys/kernel/core_pattern
	if [ $? -ne 0 ]; then
		return
	fi

	cd /data/dump
	if [ $? -ne 0 ]; then
		return
	fi

	# 每个进程最多保留最近的 5 个 core 文件
	local core_max=5
	local core_cmd=''
	local file_cmd=''
	local core_cnt=0
	local core_files=`ls -r`

	for file in $core_files; do
		file_cmd=`echo $file | grep -o '(.*)'`
		if [ -z "$file_cmd" ]; then
			continue
		fi

		if [ "$file_cmd" != "$core_cmd" ]; then
			core_cmd=$file_cmd
			core_cnt=1
		else
			let core_cnt+=1
			if [ $core_cnt -gt $core_max ]; then
				rm -f "$file"
			fi
		fi
	done

	cd -
}

clean_coredump
###############################################################################

function exec_php_request()
{
	if [ -f "$SCRIPTPATH/../cfgc_default/$1" ]; then
		retjson=`/ac/dc/ldb/php/ldbr /ac/dc/ldb/bin/web/launch.php $SCRIPTPATH/../cfgc_default/$1 -app >/dev/null 2>&1 &`
	fi
}

function add_public_key()
{
	if [ -f "$SCRIPTPATH/../config/default/$1" ] && [ ! -f "/ac/etc/$1" ]; then
		cp $SCRIPTPATH/../config/default/$1 /ac/etc/$1
	fi
}

function add_ssh_key()
{
	if [ -f "$SCRIPTPATH/../config/default/$1" ] && [ ! -f "/root/.ssh/$1" ]; then
		cp $SCRIPTPATH/../config/default/$1 "/root/.ssh/"
		cat "/root/.ssh/id_rsa.pub" >> "/root/.ssh/$1" || rm -f "/root/.ssh/$1"
	fi
}

function add_hisroty_log()
{
	if [ -f "$SCRIPTPATH/../cfgc_default/$1" ] && [ -f "/etc/profile" ] && [ ! -f "/ac/etc/$1" ]; then
		cat /etc/profile | grep cleanup_history >/dev/null
		if [ $? -ne 0 ]; then
			cat $SCRIPTPATH/../cfgc_default/$1 >> /etc/profile
			result=`source /etc/profile`
			if [ XX"$result" == XX ]; then
				mv $SCRIPTPATH/../cfgc_default/$1 /ac/etc/$1
			fi
		fi
		cat /etc/profile | grep "chmod 777 \"\${FULLPATH}\" 2>/dev/null" >/dev/null
		if [ $? -ne 0 ]; then
			echo "chmod 777 \"\${FULLPATH}\" 2>/dev/null" >> /etc/profile
			`source /etc/profile`
		fi
	fi
}

function set_ulimit_n()
{
	cat /etc/profile | grep "ulimit -n 4096" >/dev/null
	if [ $? -ne 0 ]; then
		echo "ulimit -n 4096" >> /etc/profile
		source /etc/profile
	fi
}

function add_user()
{
	id sfuser
	if [ $? -ne 0 ]; then
		groupadd -g 3454 sfuser
		useradd -u 3454 -g sfuser -s /sbin/nologin sfuser
	fi
}

function edit_chown_sfuser()
{
	local golog1="/sf/edr/manager/log/resp_dispose"
	if [ ! -e ${golog1} ]; then 
		mkdir -p ${golog1}; chown sfuser ${golog1} -R
		kill `pidof sferespdisposeaosvr` >/dev/null 2>&1
		kill `pidof sferespdisposedaosvr` >/dev/null 2>&1
	fi
    
    local golog2="/data/temp/ctm_rules"
	if [ ! -e ${golog2} ]; then 
		mkdir -p ${golog2}; chown sfuser ${golog2} -R
	fi
    
	local golog3="/sf/edr/manager/log/resp_ctm"
	if [ ! -e ${golog3} ]; then 
		mkdir -p ${golog3}; chown sfuser ${golog3} -R
		kill `pidof sfectmruleaosvr` >/dev/null 2>&1
		kill `pidof sfectmruledaosvr` >/dev/null 2>&1
	fi

	local golog4="/sf/edr/manager/log/adv_threats"
	if [ ! -e ${golog4} ]; then 
		mkdir -p ${golog4}; chown sfuser ${golog4} -R
		kill `pidof uesadvancedthreatsdaemon` >/dev/null 2>&1
		kill `pidof uesadvancedthreatsaosvr` >/dev/null 2>&1
		kill `pidof uesadvancedthreatsdaosvr` >/dev/null 2>&1
	fi

	chown sfuser /sf/edr/manager/var/.key_config/ -R
	chown sfuser /sf/edr/manager/config
	chown sfuser /sf/edr/manager/config/.secret -R
	chown sfuser /sf/edr/manager/config/.key_and_salt_dir -R
	chown sfuser /sf/edr/manager/bin/configs -R				# go配置文件目录
	chown sfuser /sf/edr/manager/bin/api -R					# go api目录
	chown sfuser /sf/edr/manager/config/log                 # 日志配置目录
}

function check_system_others()
{
	source /etc/os-release
	case $ID in
	kylin)
		# 2022-11-01，银河麒麟x86环境由于openssl版本较高，与原有的wkhtmltopdf工具不匹配，因此包内多放一份更高版本的wkhtmltopdf
		if [ "${MACHINE_PLAT}" = "x86_64" ] && [ -f /sf/edr/manager/bin/pdfmaker/bin/linux/wkhtmltox/bin/wkhtmltopdf_kylin ]; then
			echo "This system requires newer wkhtmltopdf, cover."
			cp -rf /sf/edr/manager/bin/pdfmaker/bin/linux/wkhtmltox/bin/wkhtmltopdf_kylin /sf/edr/manager/bin/pdfmaker/bin/linux/wkhtmltox/bin/wkhtmltopdf
			rm -f /sf/edr/manager/bin/pdfmaker/bin/linux/wkhtmltox/bin/wkhtmltopdf_kylin
		fi
		;;
	uos)
		;;
	UOS)
		;;
	*)
		# 2022-10-27，因适配麒麟server引入了libnsl.so.1，但会导致mgr在ubuntu环境功能异常，在此特殊处理
		echo "This system does not need libnsl.so.1 from pkg, delete."
		[ -f /sf/edr/manager/lib/libnsl.so.1 ] && rm -rf /sf/edr/manager/lib/libnsl.so.1
		;;
	esac
}

# 各个系统的特殊处理
check_system_others

if [ -d "$SCRIPTPATH/../packages/manager" ]; then
	if [ ! -d "/ac/etc/fluxconfig" ] ; then
		mkdir /ac/etc/fluxconfig
	fi

	# 创建 sfuser 用户
	add_user
	edit_chown_sfuser

	#建立内存磁盘,流量日志缓存目录
	count=`mount | grep /data/flux_log_cache | grep tmpfs | wc -l`
	if [ $count -eq 0 ]; then
		mkdir -p /data/flux_log_cache
		mount -t tmpfs -o size=300m tmpfs /data/flux_log_cache
	fi
fi

#创建实时日志目录
count=`mount | grep /log/rtlog | grep tmpfs | wc -l`
if [ $count -eq 0 ]; then
	mkdir /var/log/rtlog
	mount -t tmpfs -o size=60m tmpfs /var/log/rtlog
fi

$SCRIPTPATH/eps_services_ctrl </dev/null >/dev/null 2>&1 &
$SCRIPTPATH/abs_monitor </dev/null >/dev/null 2>&1 &

#开机启动服务
if [ -d /run ]; then
	FIRST_RUN=/run/eps_first_run${SCRIPTPATH//\//_}
else
	FIRST_RUN=/var/log/rtlog/eps_first_run${SCRIPTPATH//\//_}
fi
if [ ! -f $FIRST_RUN ]; then
	#恢复被停止的服务
	if [ "`ls -A $SCRIPTPATH/../services_stopped 2>/dev/null`" != "" ]; then
		mv -f $SCRIPTPATH/../services_stopped/* $SCRIPTPATH/../services/
	fi
	touch $FIRST_RUN
	# 若没有「通过ABS停止服务」标记，则开机启动服务
	if [ ! -e "$SCRIPTPATH"/../config/abs_stop_flag ]; then
		$SCRIPTPATH/eps_services_ctrl start
	fi
	exit 0
fi

$SCRIPTPATH/eps_services status
if [ $? -ne 0 ] ; then
	$SCRIPTPATH/eps_services_ctrl restart
fi

managedc_flag=`ls $SCRIPTPATH/../packages/ -al | wc -l`
if [ $managedc_flag -gt 8 ] && [ -d "$SCRIPTPATH/../packages/manager" ]; then
	#每小时检查超时流量日志并删除
	time_now=`date +%M`
	echo "time now is : "$time_now
	if [ "$time_now" -eq "30" ]; then
		echo "auto clear timeout flux_log"
		exec_php_request "clear_timeout_flux_log.js"
	fi

	#检测是否存在黑盒日志文件
	if [ ! -f $black_box_file ]; then
		echo "* * * * * root $SCRIPTPATH/blackbox.sh  >/dev/null 2>&1" >/etc/cron.d/eps_blackbox
	fi

	#增加restfulapi public key
	add_public_key "token.pub"

	#增加CSSP ssh私钥
	add_ssh_key "authorized_keys2"

	#增加history日志
	add_hisroty_log "history.txt"

	#拷贝fping
	if [ -f "$SCRIPTPATH/fping" ]; then
		mv $SCRIPTPATH/fping* /usr/bin/.
	fi

	#安装nmap
	if [ -d "$SCRIPTPATH/../tool/nmap" ];then
		if [ -d "$SCRIPTPATH/../tool/nmap/bin" ];then
			chmod a+x $SCRIPTPATH/../tool/nmap/bin/*
			mv $SCRIPTPATH/../tool/nmap/bin/* $SCRIPTPATH
		fi

		if [ -d "$SCRIPTPATH/../tool/nmap/lib" ];then
			chmod a+x $SCRIPTPATH/../tool/nmap/lib/*
			mv $SCRIPTPATH/../tool/nmap/lib/* /usr/lib/
		fi
		
		if [ -d "$SCRIPTPATH/../tool/nmap/x86_64-linux-gnu" ];then
			chmod a+x $SCRIPTPATH/../tool/nmap/x86_64-linux-gnu/*
			mv $SCRIPTPATH/../tool/nmap/x86_64-linux-gnu/* /usr/lib/x86_64-linux-gnu/
		fi
		
		if [ -d "$SCRIPTPATH/../tool/nmap/share" ];then
			tar xzvf $SCRIPTPATH/../tool/nmap/share/nmap.tar.gz -C /usr/share/
		fi
		rm $SCRIPTPATH/../tool/nmap -rf
	fi
	#安装sshpass
	if [ -d "$SCRIPTPATH/../tool/sshpass" ];then
	   chmod a+x $SCRIPTPATH/../tool/sshpass/*
	   mv $SCRIPTPATH/../tool/sshpass/* $SCRIPTPATH
       rm -f "$SCRIPTPATH/../tool/sshpass"
	fi
	#安装ntpdate
	if [ -d "$SCRIPTPATH/../tool/ntp" ];then
	   chmod a+x $SCRIPTPATH/../tool/ntp/*
	   mv $SCRIPTPATH/../tool/ntp/* $SCRIPTPATH
       rm -rf "$SCRIPTPATH/../tool/ntp"
	fi
	#安装mongo tool
	cascade_dir="/data/cascade"
	if [ ! -d "$cascade_dir" ];then
	    mkdir $cascade_dir
	fi
	
	if [ ! -f "$SCRIPTPATH/../lib/libssl.so.10" ];then
		 ln -s $SCRIPTPATH/../lib/libssl.so $SCRIPTPATH/../lib/libssl.so.10
	fi

	if [ ! -f "$SCRIPTPATH/../lib/libcrypto.so.10" ];then
		 ln -s $SCRIPTPATH/../lib/libcrypto.so $SCRIPTPATH/../lib/libcrypto.so.10
	fi
    

    if [ ! -f "$SCRIPTPATH/../lib/libfreetype.so" ] || [ ! -f "$SCRIPTPATH/../lib/libfreetype.so.6" ]; then
        ln -s $SCRIPTPATH/../lib/libfreetype.so.6.17.1 $SCRIPTPATH/../lib/libfreetype.so
        ln -s $SCRIPTPATH/../lib/libfreetype.so.6.17.1 $SCRIPTPATH/../lib/libfreetype.so.6
    fi
    
    if [ ! -f "$SCRIPTPATH/../lib/libjpeg.so" ] || [ ! -f "$SCRIPTPATH/../lib/libjpeg.so.9" ]; then
        ln -s $SCRIPTPATH/../lib/libjpeg.so.9.3.0 $SCRIPTPATH/../lib/libjpeg.so.9
        ln -s $SCRIPTPATH/../lib/libjpeg.so.9.3.0 $SCRIPTPATH/../lib/libjpeg.so
    fi
    
	if [ ! -f "$SCRIPTPATH/../lib/libpng16.so" ] || [ ! -f "$SCRIPTPATH/../lib/libpng16.so.16" ] || [ ! -f "$SCRIPTPATH/../lib/libpng.so" ]; then
		ln -s $SCRIPTPATH/../lib/libpng16.so.16.37.0 $SCRIPTPATH/../lib/libpng16.so > /dev/null 2>&1
		ln -s $SCRIPTPATH/../lib/libpng16.so.16.37.0 $SCRIPTPATH/../lib/libpng16.so.16 > /dev/null 2>&1
		ln -s $SCRIPTPATH/../lib/libpng16.so $SCRIPTPATH/../lib/libpng.so > /dev/null 2>&1
	fi

	# 2022-0927，适配arm架构银河麒麟v10 server环境，需要拷贝这两个文件到系统路径
	if [ "${MACHINE_PLAT}" = "aarch64" ]; then
		if [ ! -f /usr/lib64/libpng12.so.0 ]; then
			\cp $SCRIPTPATH/../lib/libpng12.so.0 /usr/lib64/ > /dev/null 2>&1
		fi

		if [ ! -f /usr/lib64/libjpeg.so.9 ]; then
			\cp $SCRIPTPATH/../lib/libjpeg.so.9 /usr/lib64/ > /dev/null 2>&1
		fi
	fi

	# 设置操作系统打开文件数为4096
	set_ulimit_n
fi

exit 0

