#!/bin/bash
# 端口信息采集

#设置运行环境为英文
export LANG=""
export LANGUAGE=""

while read -r param1 param2 param3; do
    if [[ $param1 == udp* ]]; then
        protocol=0
    else
        protocol=1
    fi
    port=${param2##*:} # 从左向右截取最后一个:后的字符串
    ip=${param2%:*}    # 从右向左截取第一个:前的字符串

    # 替换 * 为常见的 0.0.0.0
    ip=${ip//"*"/"0.0.0.0"}

    # 根据 " 进行切割，取第一个被包裹的
    process=$(echo "$param3" | awk -F '"' '{print $2}')
    echo "{\"port\":$port,\"protocol\":$protocol,\"bind_ip\":\"$ip\",\"process\":\"$process\"}"
done < <(ss -putan | grep -E 'LISTEN|UNCONN' | awk '{print $1, $5, $7}')