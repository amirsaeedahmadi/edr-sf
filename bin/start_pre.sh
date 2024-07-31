#!/bin/bash

###############################################
#脚本说明：启动所有服务前，此脚本被执行
###############################################

SCRIPTPATH=$(cd $(dirname $0); pwd -P)



# 删除「通过ABS停止服务」标记
if [ -e "$SCRIPTPATH"/../config/abs_stop_flag ]; then
	rm -f "$SCRIPTPATH"/../config/abs_stop_flag
fi
