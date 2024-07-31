#!/bin/bash

###############################################
#脚本说明：执行此脚本还原用户iptables策略
###############################################

SCRIPTPATH=$(cd $(dirname $0); pwd -P)

function restore_iptables()
{
	if [ -e $SCRIPTPATH/../config/iptables.old ]; then
		iptables -t filter -F
		iptables -t filter -X
		iptables-restore < $SCRIPTPATH/../config/iptables.old
		rm -f $SCRIPTPATH/../config/iptables.old
		#此处是为了微隔离策略与账号爆破黑名单策略共存兼容问题添加的代码,详情见TD92579@wrj
		export LD_LIBRARY_PATH=$SCRIPTPATH/../lib
		$SCRIPTPATH/lloader $SCRIPTPATH/../agent_scripts/firewall/bfa_reload.lua
	fi
	
#	if [ -e $SCRIPTPATH/../config/ip6tables.old ]; then
#		ip6tables -t filter -F
#		ip6tables -t filter -X
#		ip6tables-restore < $SCRIPTPATH/../config/ip6tables.old
#		rm -f $SCRIPTPATH/../config/ip6tables.old
#	fi
}

restore_iptables