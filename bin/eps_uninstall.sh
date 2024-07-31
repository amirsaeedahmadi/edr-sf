#!/bin/bash

SCRIPTPATH=$(cd $(dirname $0); pwd -P)
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$SCRIPTPATH/../lib

#安装目录如果是我们默认创建的，会有这个文件标志，此时应该删除我们创建的目录
if [ -f ${SCRIPTPATH}/../default_dir_flag ]; then
	default_dir_flag=1
else
	default_dir_flag=0
fi

echo "start uninstall eps agent"
if [ ! -f $SCRIPTPATH/eps_services ]; then
	echo "$SCRIPTPATH/eps_services is not exist or not a file";
	exit 1
fi

function pidof_edr_agent()
{
	local ipid=`pidof $SCRIPTPATH/edr_agent`
	echo "$ipid"
}

function pidof_ipc()
{
	local ipid=`pidof $SCRIPTPATH/ipc_proxy`
	echo "$ipid"
}

function pidof_sfupdate()
{
	local ipid=`pidof $SCRIPTPATH/sfupdate`
	echo "$ipid"
}

function pidof_fget()
{
	local ipid=`pidof $SCRIPTPATH/fget`
	echo "$ipid"
}

function wait_ipc_start()
{
	for (( i=0; i<15; i++)); do
		sleep 1
		local ipid=`pidof_ipc`
		if [ -n "$ipid" ]; then
			return 0
		fi
	done
	return 1
}

function wait_service_stop()
{
	for (( i=0; i<3; i++)); do
		#停服务
		$SCRIPTPATH/eps_services stop uninstall
		edr_status=`$SCRIPTPATH/eps_services status`
		if [[ $edr_status == *"edr stopped"* ]]; then
			echo "edr sevice stop success."
			return 0
		else
			sleep 1
			$SCRIPTPATH/eps_services stop uninstall
		fi
	done

	return 1
}

function delete_p2p_iptables()
{
	local edr_input_iptables=`iptables -nvL | grep FGET_FIREWALL_LAYER |grep -v grep| wc -l`
	if [ $edr_input_iptables -eq 0 ]; then
		echo "not exist FGET_FIREWALL_LAYER"
		return 0
	fi

	iptables -D INPUT -j FGET_FIREWALL_LAYER > /dev/null 2>&1
	iptables -F FGET_FIREWALL_LAYER > /dev/null 2>&1
	iptables -X FGET_FIREWALL_LAYER > /dev/null 2>&1
	
	return 0
}

function get_osname()
{
    local osname=""
    
    grep centos /proc/version > /dev/null 2>&1 && osname=centos
    grep ubuntu /proc/version > /dev/null 2>&1 && osname=ubuntu
    
    if [ -n "${osname}" ]; then
        echo ${osname}
        return 0
    else
        return 1
    fi
}

# 删除掉自保护驱动
function delete_sfesp()
{
    local osname=`get_osname`
    
    if [ "x${osname}" == "xcentos" ]; then
        rm -f /etc/sysconfig/modules/sfesp.modules
    elif [ "x${osname}" == "xubuntu" ]; then
        rm -f /lib/modules/`uname -r`/kernel/drivers/char/sfesp.ko
        sed -i '/sfesp/d' /etc/modules
        depmod
    else
        echo "The current system is not supported."
        return 0
    fi
    
    rmmod sfesp
}

function kill_exec()
{
	local uAgentPID=""
	local moudle_name="${1}"

	uAgentPID=`ps -ef |grep -v grep|  grep ${moudle_name} | awk '{printf FS $2}'`
	if [ "${uAgentPID}" != "" ];then
		kill -9 ${uAgentPID} 2>&1 > /dev/null
		if [ $? -ne 0 ];then
			echo "kill ${moudle_name} pid(${uAgentPID}) failed"
			return 1
		else
			echo "kill ${moudle_name} pid(${uAgentPID}) successfully"
			return 0
		fi
	fi
	return 0
}


# 先停止服务，避免edr发额外的信息给mgr，导致mgr判断错误
$SCRIPTPATH/eps_services mask 20edr_agent
agent_pid=`pidof_edr_agent`
if [ -z "$agent_pid" ]; then
    # 停edr_agent进程，上报卸载状态
    kill "$agent_pid" 2>/dev/null
fi
echo "stop edr_agent process for avoiding extra agent ipc msg"

# 停止edr服务
echo "start stop eps_services"
$SCRIPTPATH/eps_services mask
$SCRIPTPATH/eps_services stop

#检测edr 服务是否停掉，停止服务失败恢复原有状态
if wait_service_stop; then	
	echo "edr service stop success."
else
	echo "edr service stop failed."
    $SCRIPTPATH/eps_services unmask 20edr_agent
	exit 1
fi

# kill asset_collection module's related shell script, binary
kill_exec "edr/agent/bin/SFEAssetCollect"
kill_exec "edr/agent/bin/login_coll.sh"
kill_exec "edr/agent/bin/newlast"
kill_exec "edr/agent/bin/nmap_work.sh"
kill_exec "edr/agent/bin/user_coll.sh"
kill_exec "edr/agent/bin/baseinfo.sh"
kill_exec "edr/agent/bin/netinfo.sh"
kill_exec "edr/agent/bin/portinfo.sh"
kill_exec "edr/agent/bin/procinfo.sh"
kill_exec "edr/agent/bin/croninfo.sh"
kill_exec "edr/agent/bin/service_coll.sh"
kill_exec "edr/agent/bin/share_coll.sh"
kill_exec "edr/agent/bin/softwareinfo.sh"

# 判断 ipc_proxy 是否存在，不存在则需要手动拉起 ipc_proxy
ipc_pid=`pidof_ipc`
if [ -z "$ipc_pid" ]; then
	# 手动将拉起 ipc_proxy
	$SCRIPTPATH/ipc_proxy &
	# 等待 ipc_proxy 启动完成再进行下一步操作
	if wait_ipc_start; then
		echo "ipc_proxy start success"
	else
		echo "ipc_proxy start failed"
	fi
fi

sleep 3
#----向mgr发送删除配置中心agent信息
$SCRIPTPATH/lloader $SCRIPTPATH/uninstall_agent_ipc.l >/dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "send uninstall agent msg to mgr failed by ipc";
fi

# 禁用状态下卸载，ipc_proxy被手动拉起，无法被 eps_services stop，需要手动 kill
ipc_pid=`pidof_ipc`
if [ -n "$ipc_pid" ]; then
	kill "$ipc_pid" 2>/dev/null
fi

# 卸载过程中正在升级，需要手动kill sfupdate
sfupdate_pid=`pidof_sfupdate`
if [ -n "$sfupdate_pid" ]; then
	kill "$sfupdate_pid" 2>/dev/null
fi

# 卸载过程中杀fget进程
fget_pid=`pidof_fget`
if [ -n "$fget_pid" ]; then
	kill "$fget_pid" 2>/dev/null
fi

echo "start clean file"
rm -f /etc/cron.d/edr_agent

#----流量可视配置文件清理/ac/etc/flux_view.conf
rm -f /ac/etc/flux_view.conf

#----僵尸网络清理
rm -f /etc/sfguard.conf

#----杀毒进程临时解压文件残留清理
rm -rf /tmp/sangforunzip/    # 旧版解压目录
for i in `ls -d /tmp/.[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]/sangforunzip 2>/dev/null` # 3.5.16之后新版解压目录
do
    dir=`dirname $i`
    rm -rf $dir
done

#还原sudo，sudo的目录应该有个叫sudo_sfback的备份
sudo_path=$(which sudo)
if [ -n "$sudo_path" ]; then
	if [ -f ${sudo_path}_sfback ]; then
		cp -af ${sudo_path}_sfback ${sudo_path} || echo "Recover ${sudo_path} fail!! You can restore sudo with ${sudo_path}_sfback manual."
	fi
fi

# 校验是否有备份的agnetid文件
if [ -f "$SCRIPTPATH/../config/machineid" ]; then
	mkdir -p /usr/share/sf
	cp -f "$SCRIPTPATH/../config/machineid" /usr/share/sf/machineid
fi

if [ -d $SCRIPTPATH/../ ]; then
	cd $SCRIPTPATH/../
	if [ $? -ne 0 ]; then
		echo "cd $SCRIPTPATH/../ failed";
		exit 1
	fi
	if [[ "$SCRIPTPATH/../" =~ "/sangfor/edr/agent" ]] \
		|| [[ "$SCRIPTPATH/../" =~ "/sf/edr/agent" ]]; then
    	rm -rf ./*
		if [ $? -ne 0 ]; then
			echo "rm $SCRIPTPATH/../ failed";
			exit 1
		fi
	else
		echo "check sangfor dir failed";
		exit 1
	fi
fi

#删除禁用标记
if [ -f /run/edr_forbidden ]; then
	rm -f /run/edr_forbidden
fi

#安装目录如果是我们默认创建的，会有这个文件标志，此时应该删除我们创建的目录
if [ $default_dir_flag == 1 ]; then
	rm -rf ${SCRIPTPATH}/../
fi

delete_p2p_iptables
delete_sfesp

echo "edr agent uninstall success!!"

exit 0
