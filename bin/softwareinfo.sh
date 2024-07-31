#!/bin/bash
# 软件信息采集

SCRIPTPATH=$(cd $(dirname $0);pwd -P)

#设置运行环境为英文
export LANG=""
export LANGUAGE=""

# rpm 命令是否存在
rpm -qa >/dev/null 2>&1
existRpm=$?

# dpkg 命令是否存在
type dpkg-query >/dev/null 2>&1
existDpkg=$?

## 获得 ini 文件所有的 sections 名称（注意：不同 sections 之间要有空白换行）
## list_ini_sections "filename.ini"
list_ini_sections() {
    local inifile="$1"
    if [ ! -f "$inifile" ]; then
        echo ""
    else
        sed -n '/\[*\]/p' "${inifile}" | grep -v '^#'| tr -d []
    fi
}

## 在 ini 文件中，根据 section 和 key 获得对应 value 值（注意：value 不能有等号）
## get_ini_value "filename.ini" "section" "key"
get_ini_value() {
    local inifile="$1"
    local section="$2"
    local key="$3"
    if [ ! -f "$inifile" ]; then
        echo ""
    else
        sed -n '/\['"$section"'\]/,/^$/p' "$inifile" | grep -Ev '\[|\]|^$' | awk -F '=' '$1 == "'"$key"'" {print $2}'
    fi
}

clear_while_variables() {
    rpm_name=""
    exe=""
    software_name=""
    software_type=""
    version_cmd=""
    version=""
    company=""
    install_time=0
    install_path=""
    host_type=1
    record_id=""
}
iinifile="$SCRIPTPATH/../config/software.ini"

while read -r section; do

    clear_while_variables

    # 先尝试通过 rpm 命令获取 version 和 install_time
    if [[ $existRpm == 0 ]]; then
        rpm_name=$(get_ini_value "$iinifile" "$section" rpm_name)
        if [[ $rpm_name != "" ]]; then
            read -r version install_time < <(rpm -qa --queryformat "%{NAME} %{VERSION} %{INSTALLTIME}\n" | grep "$rpm_name" | awk '$1 == "'"$rpm_name"'" {print $2,$3}')
        fi
    fi

    if [[ $existDpkg == 0 ]]; then
        dpkg_name=$(get_ini_value "$iinifile" "$section" dpkg_name)
        if [[ $dpkg_name != "" ]]; then
            read -r version < <(dpkg-query -W -f='${Version}\n' "$dpkg_name" 2>/dev/null)
        fi
    fi

    # 白名单获取软件、版本
    exe=$(get_ini_value "$iinifile" "$section" exe)
    if ls $exe > /dev/null 2>&1; then
        install_path=$(ls $exe | tail -1)
    fi
    if [[ $version == "" && $install_path != "" ]]; then
        version_cmd=$(get_ini_value "$iinifile" "$section" version_cmd)
        version=$(eval "$version_cmd")
    fi

    # 无法获得 version 则说明没有此软件
    if [[ $version == "" ]]; then
        continue
    fi

    # 无法获得 install_time 则默认置 0
    if [[ $install_time == "" ]]; then
        install_time=0
    fi

    software_name=$(get_ini_value "$iinifile" "$section" software_name)
    software_type=$(get_ini_value "$iinifile" "$section" software_type)
    company=$(get_ini_value "$iinifile" "$section" company)
    host_type=1
    record_id=$(echo -n "$software_name""$version" | md5sum | cut -d ' ' -f1)
    data_md5=$(echo -n "$software_type""$company""$install_time""$install_path" | md5sum | cut -d ' ' -f1)

    echo "{\"software_name\":\"$software_name\",\"software_type\":$software_type,\
\"version\":\"$version\",\"company\":\"$company\",\"install_time\":$install_time,\
\"install_path\":\"$install_path\",\"host_type\":$host_type,\"record_id\":\"$record_id\", \"data_md5\":\"$data_md5\"}"

done < <(list_ini_sections "$iinifile")

# EDR 特殊处理
clear_while_variables

software_name="Endpoint Secure Agent"
software_type=3
company="Sangfor Technologies Inc."
host_type=1
install_path=$(dirname "$SCRIPTPATH") # /sangfor/edr/agent
install_time=$(stat -c %Z "$install_path"/bin/edr_agent)
main_version=$(grep -Eo "[0-9]*\.[0-9]*\.[0-9]*" "$install_path"/config/agent_cfg.json | head -1) # 3.2.17
plus_version=$(grep -Eo "EN|EN_B|R1|R1_B|_B" "$install_path"/config/agent_cfg.json | head -1) # 3.2.17
version="${main_version}${plus_version}"
record_id=$(echo -n "$software_name""$version" | md5sum | cut -d ' ' -f1)
data_md5=$(echo -n "$software_type""$company""$install_time""$install_path" | md5sum | cut -d ' ' -f1)

echo "{\"software_name\":\"$software_name\",\"software_type\":$software_type,\
\"version\":\"$version\",\"company\":\"$company\",\"install_time\":$install_time,\
\"install_path\":\"$install_path\",\"host_type\":$host_type,\"record_id\":\"$record_id\", \"data_md5\":\"$data_md5\"}"
