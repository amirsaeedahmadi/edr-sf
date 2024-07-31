#!/bin/bash
# 进程信息采集

#设置运行环境为英文
export LANG=""
export LANGUAGE=""

# 一秒等于多少 jiffies
jiffies=$(getconf CLK_TCK)
# 开机至今经过了多久时间
uptime=$(awk '{print int($1)}' /proc/uptime)
# 当前时间
now=$(date +%s)

while read -r process_id parent_id user cpu_usage mem_usage args; do
    # 进程已销毁、内核线程
    if [ ! -f /proc/"$process_id"/exe ] ; then
        continue
    fi
    if [ ! -f /proc/"$parent_id"/exe ] ; then
        continue
    fi

    process_name=$(basename "$(readlink -f /proc/"$process_id"/exe | awk '{print $1}')")
    parent_name=$(basename "$(readlink -f /proc/"$parent_id"/exe | awk '{print $1}')")
    path=$(readlink -f /proc/"$process_id"/exe)
    args_split=${args#*[[:space:]]} # 取第一个空格背后的字符串
    if [[ $args != "$args_split" ]]; then
        args_split=${args_split//\\/\\\\}   # 将 \ 转义成 \\
        args_split=${args_split//'"'/'\"'}  # 将 " 转义成 \"
        parameter=$args_split
    else
        parameter=""
    fi

    # 是在开机后的什么时间启动的进程
    start_time=$(awk '{print int($22 / jiffies)}' jiffies="$jiffies" /proc/"$process_id"/stat)
    # 计算程序启动时间戳
    start_timestamp=$((now - uptime + start_time))
    # 计算内存占用
    mem_usage=$(cat /proc/"$process_id"/status | grep RSS | awk '{print $2;}') 

    echo "{\"process_name\":\"$process_name\",\"process_id\":$process_id,\
\"parent_name\":\"$parent_name\",\"parent_id\":$parent_id,\"path\":\"$path\",\
\"start_time\":$start_timestamp,\"user\":\"$user\",\"parameter\":\"$parameter\",\
\"cpu_usage\":$cpu_usage,\"mem_usage\":$mem_usage}"

done < <(ps -eo pid,ppid,user,pcpu,pmem,args)

