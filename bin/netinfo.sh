#!/bin/bash
# 连接信息采集

#设置运行环境为英文
export LANG=""
export LANGUAGE=""

while read -r param1 param2 param3; do
    local_ip=${param1%:*}     # 从右向左截取第一个:前的字符串
    local_port=${param1##*:}  # 从左向右截取最后一个:后的字符串
    remote_ip=${param2%:*}    # 从右向左截取第一个:前的字符串
    remote_port=${param2##*:} # 从左向右截取最后一个:后的字符串

    # 根据「,pid=」和「,fd=」进行切割，取第一个出现的。如果为空则以「,」进行切割
    process_id=""
    process_id=$(echo "$param3" | awk -F ',pid=|,fd=' '{print $2}')
    if [ -z "$process_id" ]; then
        process_id=$(echo "$param3" | awk -F ',' '{print $2}')
    fi
    process_name=$(echo "$param3" | awk -F '"' '{print $2}')

    protocol=$(ss state established -putan | sed 1d | grep $process_id | grep $param1 | grep $param2 | awk '{print $1}')

    echo "{\"local_ip\":\"$local_ip\",\"local_port\":$local_port,\
\"remote_ip\":\"$remote_ip\",\"remote_port\":$remote_port,\
\"process_name\":\"$process_name\",\"process_id\":$process_id,\"protocol\":\"$protocol\"}"
done < <(ss state established -putan | sed 1d | awk '{print $4, $5, $6, $1}')
