#!/bin/bash

###############################################
#脚本说明：执行此脚本备份用户iptables策略
###############################################

SCRIPTPATH=$(cd $(dirname $0); pwd -P)

function save_iptables()
{
	iptables-save -t filter > $SCRIPTPATH/../config/iptables.old
	#ip6tables-save -t filter > $SCRIPTPATH/../config/ip6tables.old
}

save_iptables