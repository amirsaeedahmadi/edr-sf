#!/bin/bash
export LANG=en
MSG_CONFIG_NOT_EXIST="no such config"
MSG_CONFIG_NO_VALID="get config fail"
MSG_CONFIG_NOT_NUM="not a number"

#####################
# 返回值约定
# 0 : 成功找到配置             输出配置值
# 1 : 配置文件存在但未配置     输出默认值、无默认值不输出
# 2 : 配置文件不存在           输出默认值、无默认值不输出
# 3 : 此系统不需检测           输出空，针对ufw firewalld等不一定每个系统都有的检测项 
# 4 : 出错                     输出错误原因
#####################

STATUS_SUCCESS=0
STATUS_NOT_CONFIG=1
STATUS_NO_CONFIG_FILE=2
STATUS_NOT_NEED_TO_CHECK=3
STATUS_ERROR=4

#
#   问题纪要 
#   1、该有而不存在的配置文件 等同为 该项未配置  存在默认值输出默认值  否则不输出 如 /etc/login.defs 不存在认为 密码使用周期未配置（返回默认值0）
#   2、默认值不确定 是否上报未配置状态  如口令更换周期等


################################
# 显示结果函数
function show() {
    echo "$@"
}

#################################################################################
#检测输入多个参数是否都为数字
#返回 0 不是数字 1 全是数字
function check_int() {
    if [ $# -lt 1 ] ;then
        return 0
    fi
    local arg
    for arg in $@;do 
        if ! grep -e '^[[:digit:]][[:digit:]]*$' -e '^-[[:digit:]][[:digit:]]*$'  <<< "$arg" >> /dev/null ;then
             return 0
        fi
    done
    return 1
}

#################################################################################
#用service或systemctl命令检查系统上的服务是否正常运行
function service_check() {
    local serv_check=`service $1 status|grep -Eoi "running|Active: active|pid.*[[:digit:]]+.*running|正在运行" 2>/dev/null`
    if [ ! -z "$serv_check" ];then
        echo $serv_check && return 0
    fi
    
    local sysctl_check=`systemctl status $1|grep -Eoi "Active: active" 2>/dev/null`
    if [ ! -z "$sysctl_check" ];then
        echo $sysctl_check && return 0
    fi
    
    return 0
}

#################################################################################
#用ss或netstat命令检查系统上的端口监听情况
function port_check() {
    local ss_check=`ss -lntp | grep -w :$1 2>/dev/null`
    if [ ! -z "$ss_check" ];then
        echo $ss_check && return 0
    fi
    
    local netstat_check=`netstat -lntp | grep -w :$1 2>/dev/null`
    if [ ! -z "$netstat_check" ];then
        echo $netstat_check && return 0
    fi
    
    return 0
}

#################################################################################
# 判断操作系统是属于哪个系列，如果是ubuntu，则输出1，否则输出0
function is_ubuntu() {
    local sys_info=""
    # ubuntu系统
    sys_info=`cat /proc/version | tr 'a-z' 'A-Z' | grep UBUNTU`
    if [ ! -z "${sys_info}" ]; then
        echo 1
        return 0
    fi

    echo 0
    return 0
}

# 判断linux系统类型，目前支持centos,fedora,red-hat,centos,ubuntu,debian，都不匹配时返回空
function os_detect(){
    local detect_time=1
    local sys_type=""
    local sys_detect=""
    for index in $(seq $detect_time); do
        if [ -e "/etc/redhat-release" ]; then
            #centos系统
            sys_detect=`cat /etc/redhat-release | grep -i "centos"`
            if [ ! -z "${sys_detect}" ]; then
                sys_type='centos'
                break;
            fi
            
            #fedora系统
            sys_detect=`cat /etc/redhat-release | grep -i "fedora"`
            if [ ! -z "${sys_detect}" ]; then
                sys_type='fedora'
                break;
            fi
            
            #red-hat系统
            sys_detect=`cat /etc/redhat-release | grep -i "^red hat"`
            if [ ! -z "${sys_detect}" ]; then
                sys_type='redhat'
                break;
            fi
        else
            #ubuntu系统
            sys_detect=`cat /proc/version | grep -i "ubuntu"`
            if [ ! -z "${sys_detect}" ]; then
                sys_type='ubuntu'
                break;
            fi
            
            #debian系统
            sys_detect=`cat /proc/version | grep -i "debian"`
            if [ ! -z "${sys_detect}" ]; then
                sys_type='debian'
                break;
            fi
        fi    
    done
    echo $sys_type
    return 0
}

####################################
# 1.2.1.pam_cracklib配置项检测
function get_pwd_pam_cracklib() {
    local ALL_PATH=("/usr/lib" "/usr/lib64" "/usr/local/lib" "/usr/local/lib64" "/lib" "/lib64")
    for path in ${ALL_PATH[@]}; do
        if [ -d "${path}" ]; then
            local line_count=`find "${path}" -name pam_cracklib.so | wc -l`
            local line_count1=`find "${path}" -name pam_pwquality.so | wc -l`
            if [ $line_count -gt 0 -o $line_count1 -gt 0 ]; then
                echo 1;
                return ${STATUS_SUCCESS};
            fi
        fi
    done
    
    echo 0;
    return ${STATUS_SUCCESS};
}

####################################
# 获取密码最长使用周期
function get_pwd_max_usecycle() {
    local default_value=99999
    local pass_max_days     # 密码最长有效期
    #获取值
    if [ -f /etc/login.defs ];then
        pass_max_days=`grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{ if ($1=="PASS_MAX_DAYS"){print $2}}'`
    fi
    [[ -z "${pass_max_days}" ]] && show ${default_value} && return ${STATUS_SUCCESS}
    check_int $pass_max_days
    [[ $? -eq 1 ]] && show "${pass_max_days}" && return ${STATUS_SUCCESS}
    
    # 取不到返回默认值
    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 获取密码最短更换周期
function get_pwd_min_changecycle() {
    local default_value=0
    local pass_min_days     # 密码最短更换周期
    #获取值
    if [ -f /etc/login.defs ];then
        pass_min_days=`grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{ if ($1=="PASS_MIN_DAYS"){print $2}}'`
    fi
    [[ -z "${pass_min_days}" ]] && show ${default_value} && return ${STATUS_SUCCESS}
    check_int $pass_min_days
    [[ $? -eq 1 ]] && show "${pass_min_days}" && return ${STATUS_SUCCESS}
    
    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 获取密码距失效提示天数
function get_pwd_failprompt_days() {
    local default_value=0
    local pass_warn_age=    # 密码据到期警告天数
    #获取值
    if [ -f /etc/login.defs ];then
        pass_warn_age=`grep "^PASS_WARN_AGE" /etc/login.defs | awk '{ if ($1=="PASS_WARN_AGE"){print $2}}'`
    fi
    [[ -z "${pass_warn_age}" ]] && show ${default_value} && return ${STATUS_SUCCESS}
    check_int $pass_warn_age
    [[ $? -eq 1 ]] && show "${pass_warn_age}" && return ${STATUS_SUCCESS}
    
    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 检查密码不应该是前5次使用过的密码
function get_pwd_history_cnt(){
    local default_value=0
    local pwd_history_cnt  # 密码历史记录的次数
    # 根据不同的平台，查询不同的文件记录
    local sys_type=$(os_detect)
    if [ "$sys_type" == "ubuntu" -o "$sys_type" == "debian" ]; then
        pwd_history_cnt=`cat /etc/pam.d/common-password|grep "^password"|grep unix.so|grep remember|\
        awk -F 'remember=' '{print $2}'|awk '{print $1}'`
    else
        pwd_history_cnt=`cat /etc/pam.d/system-auth|grep "^password"|grep unix.so|grep remember|\
        awk -F 'remember=' '{print $2}'|awk '{print $1}'`
    fi
    [[ -z "${pwd_history_cnt}" ]] && show ${default_value} && return ${STATUS_SUCCESS}
    check_int $pwd_history_cnt
    [[ $? -eq 1 ]] && show "${pwd_history_cnt}" && return ${STATUS_SUCCESS}
    
    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 获取pam_cracklib配置的位置
function echo_pam_cracklib_file() {
    local pam_cracklib_locations
    if [ -f "/etc/pam.d/common-password" ];then 
        pam_cracklib_locations="/etc/pam.d/common-password"
    elif [ -f "/etc/pam.d/system-auth" ];then
        pam_cracklib_locations="/etc/pam.d/system-auth"
    elif [ -f "/etc/pam.d/passwd" ];then
        pam_cracklib_locations="/etc/pam.d/passwd"
    fi
    show ${pam_cracklib_locations}
}


####################################
# 最少大写字母数 
function get_pwd_min_uppletter() {
    local default_value=0
    local pam_cracklib_locations
    pam_cracklib_locations=`echo_pam_cracklib_file`
    [[ -z "${pam_cracklib_locations}" ]] && show ${default_value} && return ${STATUS_NO_CONFIG_FILE}
    local cracklib_ucredit
    cracklib_ucredit=`cat $pam_cracklib_locations |grep password | grep requisite| grep pam_cracklib.so | grep -v ^# |\
        awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="ucredit") print $(i+1)} '`          # 密码需最少大写字母数
    
    #两种pam模块都要检测，防止混用分开检测
    if [ -z "${cracklib_ucredit}" ];then
        cracklib_ucredit=`cat $pam_cracklib_locations |grep password | grep requisite| grep pam_pwquality.so | grep -v ^# |\
            awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="ucredit") print $(i+1)} '`          # 密码需最少大写字母数    
    fi

    [[ -z "${cracklib_ucredit}" ]] && show ${default_value} && return ${STATUS_SUCCESS}
    check_int $cracklib_ucredit
    [[ $? -eq 1 ]] && show "${cracklib_ucredit}" && return ${STATUS_SUCCESS}
    
    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 最少小写字母数 
function get_pwd_min_lowletter() {
    local default_value=0
    local pam_cracklib_locations
    pam_cracklib_locations=`echo_pam_cracklib_file`
    [[ -z "${pam_cracklib_locations}" ]] && show  ${default_value}  && return ${STATUS_NO_CONFIG_FILE}
    
    local cracklib_lcredit=`cat $pam_cracklib_locations |grep password | grep requisite| grep pam_cracklib.so | grep -v ^# |\
        awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="lcredit") print $(i+1)}'`           # 密码需最少小写字母数
    
    if [ -z "${cracklib_lcredit}" ];then
        cracklib_lcredit=`cat $pam_cracklib_locations |grep password | grep requisite| grep pam_pwquality.so | grep -v ^# |\
            awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="lcredit") print $(i+1)}'`
    fi

    [[ -z "${cracklib_lcredit}" ]] && show  ${default_value}  && return ${STATUS_SUCCESS}
    check_int $cracklib_lcredit
    [[ $? -eq 1 ]] && show "${cracklib_lcredit}" && return ${STATUS_SUCCESS}
    
    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 最少字特殊符数  
function get_pwd_min_charcnt() {
    local default_value=0
    local pam_cracklib_locations
    pam_cracklib_locations=`echo_pam_cracklib_file`
    [[ -z "${pam_cracklib_locations}" ]] && show ${default_value} && return ${STATUS_NO_CONFIG_FILE}

    local cracklib_ocredit=`cat $pam_cracklib_locations |grep password | grep requisite| grep pam_cracklib.so | grep -v ^# |\
            awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="ocredit") print $(i+1)}'`          # 密码需最少字符数
    
    if [ -z "${cracklib_ocredit}" ];then
        cracklib_ocredit=`cat $pam_cracklib_locations |grep password | grep requisite| grep pam_pwquality.so | grep -v ^# |\
                awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="ocredit") print $(i+1)}'` 
    fi

    [[ -z "${cracklib_ocredit}" ]] && show ${default_value} && return ${STATUS_SUCCESS}
    check_int $cracklib_ocredit
    [[ $? -eq 1 ]] && show "${cracklib_ocredit}" && return ${STATUS_SUCCESS}

    show  ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 最少数字数
function get_pwd_min_digitcnt() {
    local default_value=0
    local pam_cracklib_locations
    pam_cracklib_locations=`echo_pam_cracklib_file`
    [[ -z "${pam_cracklib_locations}" ]] && show ${default_value} && return ${STATUS_NO_CONFIG_FILE}

    local cracklib_dcredit=`cat $pam_cracklib_locations |grep password | grep requisite| grep pam_cracklib.so | grep -v ^# |\
        awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="dcredit") print $(i+1)}'`          # 密码需最少数字数
    
    if [ -z "${cracklib_dcredit}" ];then
        cracklib_dcredit=`cat $pam_cracklib_locations |grep password | grep requisite| grep pam_pwquality.so | grep -v ^# |\
            awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="dcredit") print $(i+1)}'` 
    fi

    [[ -z "${cracklib_dcredit}" ]] && show ${default_value} && return ${STATUS_SUCCESS}
    check_int $cracklib_dcredit
    [[ $? -eq 1 ]] && show "${cracklib_dcredit}" && return ${STATUS_SUCCESS}

    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 1.2登录锁定配置项检测
function get_login_fail() {
    local ALL_PATH=("/usr/lib" "/usr/lib64" "/usr/local/lib" "/usr/local/lib64" "/lib" "/lib64")
    for path in ${ALL_PATH[@]}; do
        if [ -d "${path}" ]; then
            local line_count=`find "${path}" -name pam_tally2.so -o -name pam_faillock.so | wc -l`
            if [ $line_count -gt 0 ]; then
                echo 1;
                return ${STATUS_SUCCESS};
            fi
        fi
    done

    echo 0;
    return ${STATUS_SUCCESS};
}

####################################
# 普通用户触发锁定次数
function get_login_lock_cnt() {
	local default_value=999999
	local deny_times                  # 失败尝试次数
	local pam_tally_locations="/etc/pam.d/sshd /etc/pam.d/system-auth /etc/pam.d/common-auth /etc/pam.d/password-auth"
	local file
	for file in ${pam_tally_locations};do
		if [ -f ${file} ];then
			deny_times=`cat ${file} | grep -w auth | grep -w 'required\|requisite'| grep 'pam_faillock\|pam_tally' | grep -v ^# | \
				awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="deny") print $(i+1)} ' | grep "^[[:digit:]]*$"`
			if [ ! -z "${deny_times}" ]; then
                break;
            fi
        fi
    done

    [[ -z "${deny_times}" ]] && show ${default_value} && return ${STATUS_SUCCESS}

    check_int ${deny_times}
    [[ $? -eq 1 ]] && show "${deny_times}" && return ${STATUS_SUCCESS}

    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 普通用户锁定时间
function get_login_lock_time() {
	local default_value=0
	local unlock_time                 # 超过失败尝试次数锁定时间
	local pam_tally_locations="/etc/pam.d/sshd /etc/pam.d/system-auth /etc/pam.d/common-auth /etc/pam.d/password-auth"
	local file
	for file in ${pam_tally_locations};do
		if [ -f ${file} ];then
			unlock_time=`cat ${file} | grep -w auth | grep -w 'required\|requisite'| grep 'pam_faillock\|pam_tally' | grep -v ^# | \
				awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="unlock_time") print $(i+1)} ' | grep "^[[:digit:]]*$"`
			if [ ! -z "${unlock_time}" ]; then
                break;
            fi
        fi
    done
    [[ -z "${unlock_time}" ]] && show ${default_value} && return ${STATUS_SUCCESS}

    check_int ${unlock_time}
    [[ $? -eq 1 ]] && show "${unlock_time}" && return ${STATUS_SUCCESS}

    show ${default_value}
    return ${STATUS_SUCCESS}
}


####################################
# Root用户触发锁定次数
function get_login_root_lockcnt() {
	local default_value=999999
	local deny_root_times             # root失败尝试次数
	local pam_tally_locations="/etc/pam.d/sshd /etc/pam.d/system-auth /etc/pam.d/common-auth /etc/pam.d/password-auth"
	local file
	for file in ${pam_tally_locations};do
		if [ -f ${file} ];then
			deny_root_times=`cat ${file} | grep -w auth | grep -w 'required\|requisite'| grep 'pam_faillock\|pam_tally' | grep -v ^# | \
				awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="deny") print $(i+1)} ' | grep "^[[:digit:]]*$"`
			if [ ! -z "${deny_root_times}" ]; then
                break;
            fi
        fi
    done
    [[ -z "${deny_root_times}" ]] && show ${default_value} && return ${STATUS_SUCCESS}

    check_int ${deny_root_times}
    [[ $? -eq 1 ]] && show "${deny_root_times}" && return ${STATUS_SUCCESS}

    show ${default_value}
    return ${STATUS_SUCCESS}
}


####################################
# Root用户锁定时间
function get_login_root_locktime() {
	local default_value=0
	local root_unlock_time            # root超过失败尝试锁定时间
	local pam_tally_locations="/etc/pam.d/sshd /etc/pam.d/system-auth /etc/pam.d/common-auth /etc/pam.d/password-auth"
	local file
	for file in ${pam_tally_locations};do
		if [ -f ${file} ];then
			root_unlock_time=`cat ${file} | grep -w auth | grep -w 'required\|requisite'| grep 'pam_faillock\|pam_tally' | grep -v ^# | \
				awk -F '[= ]+' '{for(i=1;i<=NF;i++) if($i=="root_unlock_time") print $(i+1)} ' | grep "^[[:digit:]]*$"`
			if [ ! -z "${root_unlock_time}" ]; then
                break;
            fi
        fi
    done
    [[ -z "${root_unlock_time}" ]] && show ${default_value} && return ${STATUS_SUCCESS}

    check_int ${root_unlock_time}
    [[ $? -eq 1 ]] && show "${root_unlock_time}" && return ${STATUS_SUCCESS}

    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# 检查登录连接的超时配置
function get_login_connect_overtime() {
    local default_value=0
    local login_overtime            # 用户登录连接的超时断开时间
    if [ -f /etc/profile ];then
        login_overtime=`cat /etc/profile|grep "^TMOUT=" -n|awk -F '=' '{print $2}'`
    fi
    [[ -z "${login_overtime}" ]] && show ${default_value} && return ${STATUS_SUCCESS}

    check_int ${login_overtime}
    [[ $? -eq 1 ]] && show "${login_overtime}" && return ${STATUS_SUCCESS}

    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# root权限用户
function get_auth_root_user() {
    local super_users
    local config
    #在/etc/passwd中检测是否存在除root以外管理员账户
    if [ -f /etc/passwd ];then
        for item in `cat /etc/passwd | grep ":0:" | grep -E -v '^#|^root:|^(\+:\*)?:0:0:::' | awk -F ':' '{ print $1 }'`; do
            if [ -z "${super_users}" ]; then
                super_users="${item}"
            else
                super_users="${super_users}|${item}"
            fi
        done
        config="exist"
    fi
    #在/etc/sudoers中检测是否存在除root以外管理员账户
    if [ -f /etc/sudoers ];then
        for item in `cat /etc/sudoers | grep 'ALL=' | grep -v '%'| grep -v '#'| awk -F ' ' '{ print $1 }'`; do
            if [ -z "${super_users}" ] && [ "${item}" != "root" ]; then
                super_users="${item}"
            elif [ "${item}" != "root" ]; then
                super_users="${super_users}|${item}"
            fi
        done
        config="exist"
    fi
    
    #不存在配置文件
    if [ -z "${config}" ]; then
        return ${STATUS_NO_CONFIG_FILE}
    fi
    
    show ${super_users}
    return ${STATUS_SUCCESS}
    
}

####################################
# wheel组用户
function get_auth_wheel_group() {
    local wheel_group_user
    if [ -f /etc/group ];then
        wheel_group_user=`cat /etc/group | grep wheel |grep  '^[^#]'|awk -F ':' '{print $4}' | sed ':label;N;s/\n/,/;b label'`
        show ${wheel_group_user[@]} && return ${STATUS_SUCCESS}
    fi
    return ${STATUS_NO_CONFIG_FILE}
}

####################################
# 相同ID用户
function get_auth_same_iduser() {
    local same_uid_user
    if [ -f /etc/passwd ];then
        local resultstr="";
        same_uid_user=`grep -v '^#' /etc/passwd | cut -d ':' -f3 | sort | uniq -d | sed ':label;N;s/\n/,/;b label'`
        for userid in `echo ${same_uid_user} | awk -F',' '{ for (i=1; i<=NF; ++i) { print $i } }'`; do
            local tempstr=""
            for readline in `cat /etc/passwd`; do
                local myusername=`echo "${readline}" | awk -F':' '{ print $1 }'`
                local myuserid=`echo "${readline}" | awk -F':' '{ print $3 }'`
                if [ "x${myuserid}" != "x${userid}" ]; then
                    continue;
                fi

                if [ -z "${tempstr}" ]; then
                    tempstr="${myusername}"
                else
                    tempstr="${tempstr},${myusername}"
                fi
            done

            if [ -z "${resultstr}" ]; then
                resultstr="${tempstr}"
            else
                resultstr="${resultstr}|${tempstr}"
            fi
        done
        show ${resultstr} && return ${STATUS_SUCCESS}
    fi
    return ${STATUS_NO_CONFIG_FILE}
}

####################################
# 空密码用户
function get_aces_blank_pwd() {
    local blank_pwd_user="";
    while read -r readline; do
        if [ -z "${readline}" ]; then
            continue;
        fi

        local username=`echo "${readline}" | awk -F':' '{ print $1 }'`
        if [ -z "${username}" ]; then
            continue;
        fi

        local status=`passwd -S ${username} 2>/dev/null | awk '{ print $2 }'`
        if [ "x${status}" == "xNP" ]; then
            if [ -z "${blank_pwd_user}" ]; then
                blank_pwd_user="${username}"
            else
                blank_pwd_user="${blank_pwd_user}|${username}"
            fi
        fi
    done < /etc/passwd

    show ${blank_pwd_user}
    return ${STATUS_SUCCESS}
}

####################################
# 检测ssh是否开启
function get_ssh_status() {
    local status_on=1
    local status_off=0

    local serv_check=$(service_check "sshd")
    local ssh_check
    if [ -z "$serv_check" ];then
        ssh_check=$(service_check "ssh")
        if [ -z "$ssh_check" ];then
            show ${status_off}
            return ${STATUS_SUCCESS}
        fi
    fi
    show ${status_on}
    return ${STATUS_SUCCESS}
}

####################################
# ssh使用协议版本，如果没有配置，默认是版本2
function get_ssh_protocol_version() {
    local default_version=2

    if [ ! -f /etc/ssh/sshd_config ];then
        return ${STATUS_NO_CONFIG_FILE}
    fi
    local ssh_protocol=`grep -i "^Protocol" /etc/ssh/sshd_config | awk '{print $2}'`
    if [ -z ${ssh_protocol} ];then
        show ${default_version}
        return ${STATUS_SUCCESS}
    fi
    check_int $ssh_protocol
    [[ $? -eq 1 ]] && show "${ssh_protocol}" && return ${STATUS_SUCCESS}

    show ${default_version}
    return ${STATUS_SUCCESS}
}


####################################
# ssh使用端口   
function get_ssh_port() {
    local default_value=22
    if [ ! -f /etc/ssh/sshd_config ];then
        return ${STATUS_NO_CONFIG_FILE}
    fi
    local ssh_port=`grep -i "^Port" /etc/ssh/sshd_config | awk '{print $2}'`
    if [ -z ${ssh_port} ];then
        show ${default_value}
        return ${STATUS_SUCCESS}
    fi
    check_int $ssh_port
    [[ $? -eq 1 ]] && show "${ssh_port}" && return ${STATUS_SUCCESS}

    # 如果配置的值不合法，ssh会使用默认值
    show ${default_value}
    return ${STATUS_SUCCESS}
}

####################################
# ssh最大允许登陆次数，默认值为6
function get_ssh_max_auth_tries() {
    local default_auth_tries=6

    if [ ! -f /etc/ssh/sshd_config ];then
        return ${STATUS_NO_CONFIG_FILE}
    fi
    local ssh_max_auth_tries=`grep "MaxAuthTries" /etc/ssh/sshd_config | grep -v ^# | awk '{ printf $2}'`
    if [ -z ${ssh_max_auth_tries} ];then
        show ${default_auth_tries}
        return ${STATUS_SUCCESS}
    fi
    check_int $ssh_max_auth_tries
    [[ $? -eq 1 ]] && show "${ssh_max_auth_tries}" && return ${STATUS_SUCCESS}

    # 配置的值不合法时，也返回默认值，参考官方文档
    show ${default_auth_tries}
    return ${STATUS_SUCCESS}
}

####################################
# ssh是否允许root登录，没有配置，默认允许root登录
function get_ssh_root_login() {
    local auth_yes=1  # 启用返回
    local auth_no=0   # 未开启返回

    # 根据不同的平台，设置不同的默认值
    local default_value=1
    local isubuntu=`is_ubuntu`
    if [ $isubuntu -eq 1 ]; then
        default_value=0
    fi

    if [ ! -f /etc/ssh/sshd_config ];then
        return ${STATUS_NO_CONFIG_FILE}
    fi
    local ssh_permit_root=`grep -i "^PermitRootLogin" /etc/ssh/sshd_config | awk 'NR==1{print $2}'`
    [[ -z "${ssh_permit_root}" ]] && show ${default_value} && return ${STATUS_SUCCESS}
    [[ "${ssh_permit_root}" == "yes" ]] && show  ${auth_yes} && return ${STATUS_SUCCESS}
    show ${auth_no} 
    return ${STATUS_SUCCESS}
} 

####################################
# ssh是否启用RSA认证登录，默认是启用的
function get_ssh_auth_rsa() {
    local auth_yes=1  # 启用返回
    local auth_no=0  #未开启返回
    if [ ! -f /etc/ssh/sshd_config ];then
        return ${STATUS_NO_CONFIG_FILE}
    fi
    local ssh_rsa_auth=`grep -i "^RSAAuthentication"  /etc/ssh/sshd_config | awk 'NR==1{print $2}'`            #开启RSA秘钥验证
    [[ -z "${ssh_rsa_auth}" ]] && show ${auth_yes}  && return ${STATUS_SUCCESS}
    [[ "${ssh_rsa_auth}" == "no" ]] && show ${auth_no}  && return ${STATUS_SUCCESS}
    show ${auth_yes}
    return ${STATUS_SUCCESS}
}


####################################
# ssh是否启用公钥认证登录，默认是启用的，只实用于版本2以上协议
function get_ssh_auth_pubkey() {
    local auth_yes=1  # 启用返回
    local auth_no=0  #未开启返回
    if [ ! -f /etc/ssh/sshd_config ];then
        return ${STATUS_NO_CONFIG_FILE}
    fi
    local ssh_pub_auth=`grep -i "^PubkeyAuthentication"  /etc/ssh/sshd_config | awk 'NR==1{print $2}'`            #开启公钥验证
    [[ -z "${ssh_pub_auth}" ]] && show ${auth_yes} && return ${STATUS_SUCCESS}
    [[ "${ssh_pub_auth}" == "no" ]] && show ${auth_no} && return ${STATUS_SUCCESS}
    show ${auth_yes}
    return ${STATUS_SUCCESS}
}

####################################
# ssh是否设置允许登录用户
function get_ssh_allow_users() {
    # 以下两个检测项，满足一项即可
    
    # 检测项1：ssh配置的允许登录用户
    if [ ! -f /etc/ssh/sshd_config ];then
        return ${STATUS_NO_CONFIG_FILE}
    fi
    local ssh_all_allowusers=`grep -i "^AllowUsers" /etc/ssh/sshd_config | awk '{ for (i=2;i<=NF;i++) print $i}' |\
    sed ':label;N;s/\n/,/;b label'`
    [[ ! -z "${ssh_all_allowusers}" ]] && show ${ssh_all_allowusers} && return ${STATUS_SUCCESS}
    
    # 检测项2: pamd设置的sshd的允许登录用户
    if [ -f /etc/pam.d/sshd ];then
        local pamd_ssh_restrict=`cat /etc/pam.d/sshd | grep auth | grep required | grep pam_listfile.so | grep item=user | grep sense=allow \
        | grep -v ^# | awk -F 'file=' '{print $2}'|awk -F ' ' '{print $1}'`
        if [ ! -z "${pamd_ssh_restrict}" ];then
            ssh_all_allowusers=`cat "${pamd_ssh_restrict}"`
        fi
    fi
    [[ ! -z "${ssh_all_allowusers}" ]] && show ${ssh_all_allowusers} && return ${STATUS_SUCCESS}
    
    show ${ssh_all_allowusers}
    return ${STATUS_NOT_CONFIG}
}

####################################
# 检查telnet服务和HTTP开启情况：
# 0表示合规，1表示不合规
function get_telnet_http_not_exist() {
    local status_off=0
    local status_on=1
    # 检查telnet默认服务
    if [ -f /etc/xinetd.d/telnet ];then
        local telnet_check=`cat /etc/xinetd.d/telnet|grep -i "^disable=no"`
        if [ ! -z "$telnet_check" ];then
            show ${status_on}
            return ${STATUS_SUCCESS}
        fi
    fi
    
    # 检查telnet端口状态
    local telnet_port=$(port_check "23")
    if [ ! -z "$telnet_port" ];then
        show ${status_on}
        return ${STATUS_SUCCESS}
    fi
    
    # 检查HTTP端口状态
    local http_port=$(port_check "80")
    if [ ! -z "$http_port" ];then
        show ${status_on}
        return ${STATUS_SUCCESS}
    fi
    
    #两者都未开启，则检测通过
    show ${status_off}
    return ${STATUS_SUCCESS}
}

####################################
# 过滤系统中已禁用和已锁定的用户，返回系统当前可用的用户
function get_available_user(){
    local current_users=""
    local ret=""
    if [ -f /etc/passwd ] && [ -f /etc/shadow ];then
        current_users=$(cat /etc/shadow|awk -F: '{if($2!~/^\!/)print $1}' && cat /etc/passwd|grep -v "nologin"|awk -F: '{print $1}')
    elif [ -f /etc/passwd ] && [ ! -f /etc/shadow ];then
        current_users=$(cat /etc/passwd|grep -v "nologin"|awk -F: '{print $1}')
    elif [ -f /etc/shadow ] && [ ! -f /etc/passwd ];then
        current_users=$(cat /etc/shadow|awk -F: '{if($2!~/^\!/)print $1}')
    else
        current_users=""
    fi
    ret=$(echo "$current_users" | sort | uniq -d)
    
    echo "$ret"
    return ${STATUS_SUCCESS}
}

####################################
# 检查Linux默认账户是否存在
function get_default_accounts(){
    local default_accounts
    local used_default_accounts
    local current_users=$(get_available_user)
    local filter
    local ret
    if [ -f /etc/passwd ];then
        default_accounts="adm|lp|sync|shutdown|halt|mail|uucp|operator|games|gopher"
        local used_default_accounts=`cat /etc/passwd | grep -Ewo "${default_accounts}" | uniq`
    else
        show ${used_default_accounts} && return ${STATUS_NOT_CONFIG}
    fi
    if [ ! -z "$current_users" ];then
        filter="$current_users\n$used_default_accounts"
        ret=`echo -e "$filter" | sort | uniq -d`
    else
        ret=${used_default_accounts}
    fi
    
    show ${ret}
    return ${STATUS_SUCCESS}
}

####################################
# 检查超过半年未登录的账户
function get_long_time_no_login_accounts(){
    local half_year=183     #检测时间:半年183天
    local expired_accounts=`lastlog -b ${half_year}|awk 'NR!=1{print $1}'| sort `
    local current_users=$(get_available_user)
    local filter=""
    local ret=""
    if [ ! -z "$current_users" ];then
        filter="$current_users\n$expired_accounts"
        ret=`echo -e "$filter" | sort | uniq -d`
    else
        ret=${expired_accounts}
    fi
    
    show ${ret}
    return ${STATUS_SUCCESS}
}

####################################
# 检查：开启强制访问系统对敏感数据和操作权限进行标记
function get_sensitive_objects_mark(){
    local status_on=1                    # 开启强制访问控制
    local status_off=0                   # 未开启强制访问控制
    if [ -f /etc/selinux/config ];then   
        local selinux_check=`cat /etc/selinux/config | grep -i "^SELINUX=enforcing"` # 检查selinux
        if [ ! -z "$selinux_check" ];then
            show ${status_on}
            return ${STATUS_SUCCESS}
        fi
    elif [ -d /etc/apparmor.d/ ];then
        local aa_check=$(service_check "apparmor") # 检查apparmor
        if [ ! -z "$aa_check" ];then
            show ${status_on}
            return ${STATUS_SUCCESS}
        fi
    fi

    show ${status_off}
    return ${STATUS_SUCCESS}
}

####################################
# 日志守护进程是否正常
function get_audit_log_daemon() {
    local status_on=1
    local status_err=0
    local syslog_daemon=`ps ax | egrep -w "syslogd" | grep -v "grep"`      # syslog日志系统
    local rsyslog_daemon=`ps ax | egrep -w "rsyslogd" | grep -v "grep"`    # rsyslog日志系统
    if [ -z "${syslog_daemon}" ] && [ -z "${rsyslog_daemon}" ];then
        show ${status_err}  # 不正常
    else
        show ${status_on}   # 正常
    fi
    return ${STATUS_SUCCESS}
}

####################################
# 审计日志服务是否正常
function get_audit_log_service() {
    local status_on=1
    local status_err=0
    local audit_log=$(service_check "auditd")                       # 审计服务的运行状态
    if [ -z "$audit_log" ];then
        show ${status_err}  # 不正常
    else
        show ${status_on}   # 正常
    fi
    return ${STATUS_SUCCESS}
}

####################################
# 应用日志服务是否正常
function get_app_log_service() {
    local status_on=1
    local status_err=0
    local app_syslog=$(service_check "syslog")      # 检查syslog日志服务
    local app_rsyslog=$(service_check "rsyslog")    # 检查rsyslog日志服务
    if [ -z "$app_syslog" ] && [ -z "$app_rsyslog" ];then
        show ${status_err}  # 不正常
    else
        show ${status_on}   # 正常
    fi
    return ${STATUS_SUCCESS}
}

####################################
# 检测安全日志、审计日志内容是否正常
function get_audit_log_content() {
    local default_log
    local audit_check=0
    local log_check=0
    local check_result
    local logcfg_bak
    local check_path
    
    # 检查syslog或rsyslog中的安全日志是否正常写入(优先检查rsyslog)
    if [ -f /etc/rsyslog.conf ];then
        default_log="rsyslog"
        # 检查是否有配置备份文件
        logcfg_bak=`cat /etc/rsyslog.conf | grep '$IncludeConfig' | awk '{print $2}'`
        if [ ! -z "$logcfg_bak" ];then
            check_path=("/etc/rsyslog.conf" "$logcfg_bak")
        else
            check_path=("/etc/rsyslog.conf")
        fi
    elif [ -f /etc/syslog.conf ];then
        default_log="syslog"
        check_path=("/etc/syslog.conf")
    else
        check_result="rsyslog syslog"
        show ${check_result}
        return ${STATUS_NOT_CONFIG_FILE}
    fi
    
    #auth.* /var/file;authpriv.* /var/file 这种形式的配置检测
    for path in ${check_path[@]}; do
        local check=`grep -Er '^auth\.|^authpriv\.' $path|grep ';'| grep -v '#'`
        if [ ! -z "${check}" ];then
            local check_fir=`echo "${check}"|awk -F ';' '{print $1}'|grep -E '^auth\.|^authpriv\.'|awk '{print $2}'`
            local check_sec=`echo "${check}"|awk -F ';' '{print $2}'|grep -E '^auth\.|^authpriv\.'|awk '{print $2}'`
            if ([ ! -z "${check_fir}" ] && [ -f "${check_fir}" ]) || ([ ! -z "${check_sec}" ] && [ -f "${check_sec}" ]);then
                log_check=1
                break
            fi
        else
            local auth_check=`grep -Er '^auth\.' $path|grep -v 'authpriv\.'|awk '{print $2}'| grep -v '#'| grep -v ';'`
            local authpriv_check=`grep -Er '^authpriv\.' $path|grep -v 'auth\.'|awk '{print $2}'| grep -v '#'| grep -v ';'`
            local com_check=`grep -Er '^auth,authpriv\.|^authpriv,auth\.' $path| grep -v '#'| grep -v ';'|awk '{print $2}'`
            if ([ ! -z "${auth_check}" ] && [ -f "${auth_check}" ]) || (([ ! -z "${authpriv_check}" ] && [ -f "${authpriv_check}" ]) || ([ ! -z "${com_check}" ] && [ -f "${com_check}" ]));then
                log_check=1
                break
            fi
        fi
    done
    
    # 检测结果写入check_result
    if [ $log_check -eq 1 ];then          # 安全日志内容合规
        check_result=""
    elif [ $log_check -eq 0 ];then        # 不合规
        check_result="$default_log"
    else                                                                 
        check_result="error happened"
        return ${STATUS_ERROR}
    fi

    # 检查auditd是否正常写日志
    if [ -f /etc/audit/auditd.conf ];then
        local audit_content=`cat /etc/audit/auditd.conf|grep -E "^[[:blank:]]*write_logs.*yes|^[[:blank:]]*log_format.*RAW"`
        if [ ! -z "${audit_content}" ];then
            audit_check=1
        fi
    fi
    # 检测结果写入check_result
    if [ $audit_check -eq 0 ];then
        if [ -z "${check_result}" ];then
            check_result="auditd"
        else
            check_result="${check_result} auditd"
        fi
    fi
    show ${check_result}
    return ${STATUS_SUCCESS}
}

####################################
# 检测超过半年的日志
function get_overtime_log() {
    local check_result
    local current_time=`date +%s`       # 当前时间戳
    local half_year=15811200            # 半年的unix时间戳长度：183*24*60*60=15811200

    # 检查/var/log/audit/audit.log日志时间是否超过半年
    if [ -f /var/log/audit/audit.log ];then
        local subtraction=0
        local log_start_time=`head -n 1 /var/log/audit/audit.log | grep -o "audit([0-9]*" | awk -F '(' '{print $2}'`
        if [ ! -z $log_start_time ];then
            subtraction=`expr $current_time - $log_start_time`
        fi
        if [ $subtraction -gt $half_year ]; then
            check_result="/var/log/audit/audit.log"
        fi
    fi

    # 检查/var/log/secure日志时间是否超过半年
    local secure_log_time=`find /var/log/ -name secure-* | grep -o "[0-9]*" | sort -n | head -n 1`   # 查找secure日志的最早时间
    if [ ! -z $secure_log_time ]; then
        local log_start_time=`date -d $secure_log_time +%s`
        local subtraction=`expr $current_time - $log_start_time`
        if [ $subtraction -gt $half_year ]; then
            if [ -z "${check_result}" ]; then
                check_result="/var/log/secure*.log"
            else
                check_result="${check_result} /var/log/secure*.log"
            fi
        fi
    fi

    show ${check_result}
    return ${STATUS_SUCCESS}
}

####################################
# 检测应配置日志服务器
function get_log_backup() {
    local syslog_backup
    local rsyslog_backup
    local backup_ip

    if [ -f /etc/syslog.conf ];then         # 检测syslog是否有配置日志服务器
        syslog_backup=`cat /etc/syslog.conf | grep -o -E ".*\..*[[:space:]]@@*[0-9a-zA-Z.]+" | grep -v "#"`
        backup_ip=`echo "${syslog_backup}" | grep -o -E "@[0-9a-zA-Z.]+" | uniq | sed 's/@//g'`
    elif [ -f /etc/rsyslog.conf ];then      # 检测rsyslog是否有配置日志服务器
        rsyslog_backup=`cat /etc/rsyslog.conf | grep -o -E ".*\..*[[:space:]]@@*[0-9a-zA-Z.]+" | grep -v "#"`
        backup_ip=`echo "${rsyslog_backup}" | grep -o -E "@[0-9a-zA-Z.]+" | uniq | sed 's/@//g'
`
    fi

    show ${backup_ip}
    return ${STATUS_SUCCESS}
}

####################################
# 防火墙 iptables
function get_firewall_iptables() {
    local is_chain_output_ok=0
    local is_chain_input_ok=0
    local is_chain_forward_ok=0

    local status_on=1
    local status_off=0
    #分别判断三条链是否存在规则
    local res=`iptables -L -n -v | grep -A 2 "Chain" | grep -A 2 "OUTPUT" | grep -v "^Chain" | grep -v "^$" |grep -v "pkts"`
    if [ -z "${res}" ];then res=`iptables -L -n -v | grep  "Chain" | grep "OUTPUT" | grep  "DROP"`;fi
    if [ ! -z "${res}"  ];then    is_chain_output_ok=1 ;    fi
    res=`iptables -L -n -v | grep -A 2 "Chain" | grep -A 2 "INPUT" | grep -v "^Chain" | grep -v "^$" |grep -v "pkts"`
    if [ -z "${res}" ];then res=`iptables -L -n -v | grep  "Chain" | grep "INPUT" | grep  "DROP"`;fi
    if [ ! -z "${res}" ];then    is_chain_input_ok=1 ;    fi
    res=`iptables -L -n -v | grep -A 2 "Chain" | grep -A 2 "FORWARD" | grep -v "^Chain" | grep -v "^$" |grep -v "pkts"`
    if [ -z "${res}" ];then res=`iptables -L -n -v | grep  "Chain" | grep "FORWARD" | grep  "DROP"`;fi
    if [ ! -z "${res}" ];then    is_chain_forward_ok=1 ;    fi

    if [ ${is_chain_input_ok} == 0  -a ${is_chain_output_ok} == 0 -a ${is_chain_forward_ok} == 0 ];then
        show ${status_off};
        return ${STATUS_SUCCESS}
    fi
    show ${status_on};
    return ${STATUS_SUCCESS}
}

####################################
# 防火墙 ufw
function get_firewall_ufw() {
    local status_on=1
    local status_off=0

    if [ -f /etc/ufw/ufw.conf ];then
        ufw status | grep "inactive" >/dev/null
        if [ $? -eq 0 ];then   # 若找到inactive字样 grep返回0 说明未开启
            show ${status_off}
        else
            show ${status_on}
        fi
        return ${STATUS_SUCCESS}
    else
        show ${status_off}
        return ${STATUS_SUCCESS}
    fi
}


####################################
# 防火墙 firewalld
function get_firewall_firewalld() {
    local status_on=1
    local status_off=0

    if [ -f /etc/firewalld/firewalld.conf ];then
        local run=`$(service_check "firewalld.service")`
        if [ ! -z "$run" ];then   
            show ${status_on}
        else
            show ${status_off}
        fi
        return ${STATUS_SUCCESS}
    else
        show ${status_off}
        return ${STATUS_SUCCESS}
    fi
}

####################################
# 默认共享检测
function get_default_sharing() {
    local check_status=1
    # Linux的默认共享检测 默认符合
    show ${check_status}
    return ${STATUS_SUCCESS}
}

####################################
# FTP服务检测
function get_ftp_service() {
    local ftp_on=1      #ftp服务开启
    local ftp_off=0     #ftp服务关闭
    local vsftp_check=$(service_check "vsftpd")                                     # vsftp服务检测
    local ftp_port=$(port_check "21")                                               # ftp默认端口检测
    # 两种检测条件有一个不满足时，认为ftp服务开启
    if [ ! -z "$vsftp_check" ] || [ ! -z "$ftp_port" ]; then
        show ${ftp_on}
        return ${STATUS_SUCCESS}
    else
        show ${ftp_off}
        return ${STATUS_SUCCESS}
    fi
}

####################################
# 风险性服务检测
function get_risky_services() {
    local risky_list=("postfix" "cups" "rpcbind")
    local check_status=0
    local check_result=""
    for service in ${risky_list[@]};do
        # 实时运行进程检测
        local proc_check=`ps ax | grep -wi ${service} | grep -v "grep"`
        # 系统已安装服务检测
        local service_check=`systemctl status ${service} | grep -i "Loaded: loaded"`
        if [ ! -z "$proc_check" ] || [ ! -z "$service_check" ];then
            if [ -z "$check_result" ]; then
                check_result="${service}"
            else
                check_result="${check_result}|${service}"
            fi
        fi
    done

    show ${check_result}
    return ${STATUS_SUCCESS}
}

####################################
# 风险性端口检测
function get_risky_ports() {
    show ""
    return ${STATUS_SUCCESS}
}

####################################
# 检测hosts是否配置IP接入限制
function get_hosts_access_restrict() {
    # 检查etc/hosts的allow和deny配置
    if [ -f /etc/hosts.allow ] && [ -f /etc/hosts.deny ];then
        local allow=`cat /etc/hosts.allow|grep sshd|grep allow|grep -v '#'`
        local deny=`cat /etc/hosts.deny |grep sshd:all:deny|grep -v '#'`
        if [ ! -z "${allow}" ] && [ ! -z "${deny}" ];then   
            show ${allow}
            return ${STATUS_SUCCESS}
        fi
    fi

    show ""
    return ${STATUS_SUCCESS}
}

####################################
# 检测iptables是否配置ssh接入限制
function get_iptables_access_restrict() {
    local check_result
    local ssh_port=$(get_ssh_port)
    local iptables_check_file="/tmp/iptables_blscan.txt"
    
    if [ ! -f /etc/ssh/sshd_config ];then
        return ${STATUS_NO_CONFIG_FILE}
    fi  
    
    # 输出iptables中的ssh策略到iptables_check_file中，然后检查
    iptables -L | awk '{if(/dpt:ssh/||/dpt:'$ssh_port'/){print}}' > $iptables_check_file
    if [ $? -eq 0 ];then
        while read output
        do
            local check_source=$(echo $output |awk '{print $4}'| grep -v 'anywhere')
            if [ ! -z "${check_source}" ]; then   # 检查source列不为anywhere，则说明有对源IP做限制
                check_result="${check_result} ${check_source}"
                break
            fi
        done < "${iptables_check_file}"
    fi
    rm -rf "${iptables_check_file}"
    
    show ${check_result}
    return ${STATUS_SUCCESS}
}

####################################
# 检测agent端的病毒库版本
function get_virusdb_info() {
    local check_result=""
    local cfg_path=`dirname $0`"/../config/agent_cfg.json"

    if [ ! -z $cfg_path ] && [ -f $cfg_path ];then                    # 获取病毒库版本号
        check_result=`cat $cfg_path | grep -Eo '"virusdbs": "[[:digit:]]*"' | grep -Eo '[[:digit:]]+'`
    fi

    show ${check_result}                        
    return ${STATUS_SUCCESS}
}

if [ $# -ne 1 ]; then
    echo "error param, $#"
    exit 1;
fi

shell_out=`$1`
echo $?
echo $shell_out