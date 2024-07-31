#!/bin/bash

###############################################
#脚本说明：启动所有服务后，此脚本被执行
###############################################

#启动后，请求封堵策略需一分钟，可先加载本地保存策略
SCRIPTPATH=$(cd $(dirname $0); pwd -P)
export LD_LIBRARY_PATH=${SCRIPTPATH}/../lib
$SCRIPTPATH/lloader $SCRIPTPATH/../agent_scripts/firewall/bfa_reload.lua