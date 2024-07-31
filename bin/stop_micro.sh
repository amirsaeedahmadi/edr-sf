#!/bin/bash

###############################################
#脚本说明：停止微隔离服务后，此脚本被执行
###############################################
SCRIPTPATH=$(cd $(dirname $0); pwd -P)
INPUT_CHAIN_NAME="INPUT"
OUTPUT_CHAIN_NAME="OUTPUT"
MICRO_INPUT_CHAIN_NAME="SF_MICRO_ISOLATE"
MICRO_OUTPUT_CHAIN_NAME="SF_MICRO_ISOLATE_OUT"

#测试ipset命令是否存在
which ipset >/dev/null 2>&1
existIPSET=$?

function clear_micro_ipset()
{
	while read -r line; do
    	ipset_name=$(echo $line | awk '{print $NF}')
    	ipset destroy $ipset_name
	done < <(ipset list | grep run_)
}

function clear_sf_micro()
{
	micro_input_chain=`iptables -nvL $1 | grep $2`
    while [ -n "$micro_input_chain" ]; do
        iptables -D $1 -j $2
        if [ $? -ne 0 ]; then
            break
        fi 
		micro_input_chain=`iptables -nvL $1 | grep $2`
	done
}

function clear_micro_iptables()
{
	micro_input_chain=`iptables -nvL $INPUT_CHAIN_NAME | grep $MICRO_INPUT_CHAIN_NAME`
	iptables -F $MICRO_INPUT_CHAIN_NAME
	#判断微隔离入站策略是否存在
	if [ -n "$micro_input_chain" ]; then
		iptables -D $INPUT_CHAIN_NAME -j $MICRO_INPUT_CHAIN_NAME
		clear_sf_micro $INPUT_CHAIN_NAME $MICRO_INPUT_CHAIN_NAME
	fi
	iptables -X $MICRO_INPUT_CHAIN_NAME
	
	micro_output_chain=`iptables -nvL $OUTPUT_CHAIN_NAME | grep $MICRO_OUTPUT_CHAIN_NAME`
	iptables -F $MICRO_OUTPUT_CHAIN_NAME
	#判断微隔离出站策略是否存在
	if [ -n "$micro_output_chain" ]; then
		iptables -D $OUTPUT_CHAIN_NAME -j $MICRO_OUTPUT_CHAIN_NAME	
        clear_sf_micro $OUTPUT_CHAIN_NAME $MICRO_OUTPUT_CHAIN_NAME
	fi
	iptables -X $MICRO_OUTPUT_CHAIN_NAME
}

# 隔离策略生效文件
if [ -e $SCRIPTPATH/../config/policy_effect ]; then
	rm -f $SCRIPTPATH/../config/policy_effect
	clear_micro_iptables
	if [ $existIPSET -eq 0 ]; then
		clear_micro_ipset
	fi
fi