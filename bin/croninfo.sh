#!/bin/bash
# 计划任务信息采集

#设置运行环境为英文
export LANG=""
export LANGUAGE=""

# 传入文件路径，输出文件内的计划任务
# param1 文件路径
# param2 每行任务的参数个数，一般 /var/spool/cron/crontabs/ 下的为 6，其它为 7
# 样例：
# * * * * * /root/test.sh (param2 == 6)
# * * * * * root /root/test.sh (param2 == 7)
prase_file() {
    if [[ $# != 2 || ! -f $1 ]]; then
        return
    fi
    local scheduler_name; scheduler_name=$(basename "$1")
    local creat_time; creat_time=$(stat -c %Y "$1")
    local param_num=$2
    while read -r param1 param2 param3 param4 param5 param6 param7; do
        # 仅对前三位做正则校验，后两位（月份、周几）可以混输英文过于复杂
        local reg='^([0-9,\*/-]+)$' # 匹配「数字」、「,」、「*」、「/」、「-」
        if [[ ! $param1 =~ $reg || ! $param2 =~ $reg || ! $param3 =~ $reg ]]; then
            continue
        fi
        local user=""
        local command=""
        if [[ $param_num == 6 ]]; then # 6 的含义参考函数注释
            user=$scheduler_name
            if [[ $param7 == "" ]]; then
                command=$param6
            else
                command=$param6" "$param7
            fi
        else
            user=$param6
            command=$param7
        fi
        command=${command//\\/\\\\}   # 将 \ 转义成 \\
        command=${command//'"'/'\"'}  # 将 " 转义成 \"
        local runtime="$param1 $param2 $param3 $param4 $param5"
        echo "{\"scheduler_name\":\"$scheduler_name\",\
\"scheduler_state\":$scheduler_state,\"command\":\"$command\",\
\"user\":\"$user\",\"runtime\":\"$runtime\",\"creat_time\":$creat_time}"
    done < "$1"
}

# 传入目录路径，遍历文件，用 prase_file 解析
# param1 目录路径
# param2 每行任务的参数个数，一般 /var/spool/cron/* 下的为 6，其它为 7
foreach_dir() {
    if [[ $# != 2 ]]; then
        return
    fi
    if ! ls "$1"/* >/dev/null 2>&1; then
        return
    fi
    while read -r file; do
        if [ -f "$file" ]; then
            prase_file "$file" "$2"
        fi
    done < <(ls -1 -d "$1"/*)
}

# 若进程 cron 或 crond 存在，则说明计划是启用状态
scheduler_state=0
if pidof cron >/dev/null 2>&1; then
    scheduler_state=1
fi
if pidof crond >/dev/null 2>&1; then
    scheduler_state=1
fi

# 计划任务位置 1：/etc/cron.d/*
foreach_dir "/etc/cron.d" 7

# 计划任务位置 2：/etc/crontab
prase_file "/etc/crontab" 7

# 计划任务位置 3：/var/spool/cron/crontabs/*
foreach_dir "/var/spool/cron/crontabs" 6

# 计划任务位置 4：/var/spool/cron/*
foreach_dir "/var/spool/cron" 6
