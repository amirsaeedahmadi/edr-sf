#!/bin/bash

###############################################
#脚本说明：停止所有服务后，此脚本被执行
###############################################

SCRIPTPATH=$(cd $(dirname $0); pwd -P)

#停掉服务时，会删除暴破封堵策略
iptables -F eps_input

$SCRIPTPATH/setsyslog -u > /dev/null
if [ $? -ne 0 ]; then
	#这个配置恢复失败不影响卸载，只提示，不结束卸载过程
	echo "recover iptables system log fail, continue ...";
fi

avpid=`pidof $SCRIPTPATH/sfavsrv`
if [ -n "$avpid" ]; then
	kill -9 $avpid
fi

# 采集进程升级的时候需要杀掉
collect_pid=`pidof $SCRIPTPATH/SFEAssetCollect`
if [ -n "$collect_pid" ]; then
	kill -9 $collect_pid
fi

#清除微隔离策略和标记文件以及ipset
$SCRIPTPATH/stop_micro.sh

# 停服务时删除asset_collection端口封堵文件
if [ -f $SCRIPTPATH/../var/portinfo/mi_rule_lite.conf ]; then
	rm -f $SCRIPTPATH/../var/portinfo/mi_rule_lite.conf
fi
