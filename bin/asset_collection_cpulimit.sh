#!/bin/bash
#通过检查采集进程是否启动来控制cpu
# [ "${EDR_ASSET_COLLECTOR_FLOCKER}" != "$0" ] && exec env EDR_ASSET_COLLECTOR_FLOCKER="$0" flock -eno "$0" "$0" "$@" || :

CURRENT_INSTALL_PATH=  #安装脚本位置
CPU_LIMIT_PATH=
AGNET_LIB_PATH=
AGENT_COLLECTION_PATH=
CPU_LIMIT_RATIO=20
AGENT_NAME=SFEAssetCollect
CPULIMIT_NAME=cpulimit
SCRIPT_SLEEP_TIME=3
CURRENT_PROCESS_ID=

function get_install_path()
{
    local ret=0
    local path=$(cd $(dirname $0); pwd)
    path=$(dirname "${path}")
    
    CURRENT_INSTALL_PATH="${path}/bin"
    if [ ! -d ${path} ];then
        echo "dir not find ${path}"
        ret=1
    else
        ret=0
    fi

    return ${ret}
}

function check_exe_path()
{
    get_install_path
    if [ $? -ne 0 ];then
        return 1
    fi
    
    #检查库路径
    AGNET_LIB_PATH="${CURRENT_INSTALL_PATH}/../lib"
    if [ ! -d ${AGNET_LIB_PATH} ];then
        echo "lib path not find ${AGNET_LIB_PATH}"
        return 1
    fi
  
    #检查cpulimit是否存在
    CPU_LIMIT_PATH="${CURRENT_INSTALL_PATH}/${CPULIMIT_NAME}"
    if [ ! -f ${CPU_LIMIT_PATH} ];then
        echo "cpu limit not find ${CPU_LIMIT_PATH}"
        return 1
    fi
    
    #检查终端采集进程是否存在
    AGENT_COLLECTION_PATH="${CURRENT_INSTALL_PATH}/${AGENT_NAME}"
    if [ ! -f ${AGENT_COLLECTION_PATH} ];then
        echo "cpu limit not find ${AGENT_COLLECTION_PATH}"
        return 1
    fi
    
    return 0
}

#返回1则不存在cpulimit限制
function check_cpulimit_run()
{
    local ps_ret=$(ps aux | grep "${CPULIMIT_NAME}\ --limit=${CPU_LIMIT_RATIO}\ --exe" | grep -v grep | head -n 1)
    if [ $? -ne 0 ];then
        echo "check cpulimit is error"
        return 1
    fi
    
    if [ ! -z "${ps_ret}" ];then
        return 0
    fi
    
    return 1
}

#返回1不存在采集进程
function check_agent_collection_run()
{
    CURRENT_PROCESS_ID=0
    local ps_ret=$(ps aux | grep "${AGENT_COLLECTION_PATH}" | grep -v grep | head -n 1 | awk '{print $2}' | awk '{gsub(/^\s+|\s+$/, "");print}')
    if [ $? -ne 0 ];then
        echo "check ${AGENT_COLLECTION_PATH} is error"
        return 1
    fi
    if [ -z "${ps_ret}" ];then
        return 1
    fi
    
    #判断进程号
    expr ${ps_ret} + 0 >/dev/null
    if [ $? -eq 0 ];then
        CURRENT_PROCESS_ID=${ps_ret}
        return 0
    fi

    return 1
}

function check_use_cpu_limit()
{
    #检查进程是否存在
    check_agent_collection_run
    if [ $? -ne 0 ];then
        return 0
    fi
    
    #检查cpulimit控制进程是否存在
    check_cpulimit_run
    if [ $? -eq 0 ];then
        return 0
    fi
    
    #设置执行cpulimit控制
    if [ ${CURRENT_PROCESS_ID} -ne 0 ];then
        export LD_LIBRARY_PATH=${AGNET_LIB_PATH}
        ${CPU_LIMIT_PATH} --limit=${CPU_LIMIT_RATIO} --pid=${CURRENT_PROCESS_ID} 2>&1 > /dev/null
        if [ $? -ne 0 ];then
            echo "cpu limit error, ${CPU_LIMIT_PATH} --limit=${CPU_LIMIT_RATIO} --pid=${CURRENT_PROCESS_ID}"
        fi
    fi
    
    return 0
}

function run()
{
    #每2秒中检查一次进程是否启动，是否已经启动cpulimit控制
    while true
    do
        check_use_cpu_limit
        sleep ${SCRIPT_SLEEP_TIME}
    done
}

function main()
{
    #设置运行环境为英文
    export LANG=""
    export LANGUAGE=""

    #检查路径，elf是否存在
    check_exe_path
    if [ $? -ne 0 ];then
        exit 1
    fi
    
    #执行检查
    run
    
    exit 0
}
main $@
