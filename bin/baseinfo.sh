#!/bin/bash
# 终端基础信息采集

# 终端基础信息 采集原理
# operating_system  不同操作系统，不同的采集方式
# version           不同操作系统，不同的采集方式
# cpu_info          通过读取 /proc/cpuinfo 和 /proc/stat 进行采集
# memory_info       通过读取 /proc/meminfo 和 dmidecode 命令进行采集
# disk_info         通过读取 /sys/block/* 和 df 命令进行采集
# network_card      通过 lspci 命令进行采集
# motherboard       通过 dmidecode 命令进行采集

# 根据传入的Shell数组，输出JSON数组
make_json_array() {
    local param=("$@")
    local comma=0
    echo -n "["
    for i in "${param[@]}"; do
        if [ $comma -eq 1 ]; then
            echo -n ","
        else
            comma=1
        fi
        echo -n "${i}"
    done
    echo "]"
}

#设置运行环境为英文
export LANG=""
export LANGUAGE=""

# dmidecode 命令是否存在
type dmidecode >/dev/null 2>&1
existDDC=$?

# lspci 命令是否存在
type lspci >/dev/null 2>&1
existLsPci=$?

# lsb_release 命令是否存在
type lsb_release >/dev/null 2>&1
existLsb=$?

#lsblk命令是否存在
type lsblk >/dev/null 2>&1
exisLsblk=$?

# ################################ operating_system ################################
# ################################ version          ################################

if [ -f /etc/redhat-release ]; then
    # Red Hat Enterprise Linux Server release 7.4 (Maipo) => 7.6
    # CentOS Linux release 7.6.1810 (Core) => 7.6
    # CentOS release 6.5 (Final) => 6.5
    # NeoKylin Linux Desktop release 6.0 => 6.0
    centos_name="CentOS"
    rhel_name="Red Hat Enterprise Linux Server"
    neokylin_name="NeoKylin Linux Desktop"
    sys_os_short="$(awk -F "#" '{print $1}' /etc/redhat-release | grep -Eo "$centos_name|$rhel_name|$neokylin_name")"
    sys_ver=$(awk -F "#" '{print $1}' /etc/redhat-release | grep -Eo '([0-9]|\.)+')
    sys_ver_short=$(echo "$sys_ver" | grep -Eo '[0-9]+\.[0-9]+')
    sys_bit=$(uname -m)
    sys_os="$sys_os_short $sys_ver_short $sys_bit"
elif [ -f /etc/os-release ]; then
    sys_os_short=$(awk -F "=" /^NAME=/'{print $2}' /etc/os-release | sed 's/\"//g')
    sys_ver=$(awk -F "=" /^VERSION_ID=/'{print $2}' /etc/os-release | sed 's/\"//g')
    sys_bit=$(uname -m)
    sys_os="$sys_os_short $sys_ver $sys_bit"
elif [ $existLsb -eq 0 ]; then
    sys_os_short=$(lsb_release -a 2>&1 | awk -F ":" /^Distributor/'{print $2}' | sed 's/\s//g')
    sys_ver=$(lsb_release -a 2>&1 | awk -F ":" /^Release/'{print $2}' | sed 's/\s//g')
    sys_bit=$(uname -m)
    sys_os="$sys_os_short $sys_ver $sys_bit"
else
    sys_os_short="Linux"
    sys_bit=$(uname -m)
    sys_os="$sys_os_short $sys_bit"
fi
# echo "$sys_os"
# echo "$sys_ver"

# ################################ cpu_info ################################

cpu_count=0
cpu_detail_json_array=""
# done < <(xxx) 样例
# Intel(R) Core(TM)2 Duo CPU T7700 @ 2.40GHz
# Intel(R) Pentium(R) CPU G4400 @ 3.30GHz
while read -r line; do
    cpu_model=$line
    if [[ $cpu_model == *Intel* && $cpu_model == *@* ]]; then
        # 从 CPU 名字中截取
        cpu_frequency=$(echo "$cpu_model" | awk -F ' @ ' '{print $NF}')
    elif ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq >/dev/null 2>&1; then
        # 从文件中读取
        cpu_frequency=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq | awk 'BEGIN {max = 0} {if ($1 + 0 > max + 0) max = $1 fi} END {printf "%.2fGHz", max / 1000000}')
    else
        # 读不到，置空
        cpu_frequency=""
    fi
    cpu_detail_json_one="{\\\\\\\"model\\\\\\\":\\\\\\\"$cpu_model\\\\\\\",\\\\\\\"frequency\\\\\\\":\\\\\\\"$cpu_frequency\\\\\\\"}"
    cpu_detail_json_array[$cpu_count]=$cpu_detail_json_one
    ((cpu_count++))
done < <(grep -E "physical id|model name" /proc/cpuinfo | grep -o "[^ ]\+\( \+[^ ]\+\)*" | sed 'N;s/\n//g' | sort | uniq -c | awk -F ':|physical id' '{print $2}' | tr -s "[:space:]")
cpu_info=$(make_json_array "${cpu_detail_json_array[@]}")
# echo "$cpu_info"

# ################################ memory_info ################################

if [ $existDDC -ne 0 ]; then
    memory_list="[]"
else
    memory_count=0
    memory_detail_json_array=""
    # done < <(xxx) 样例
    # Kingston
    while read -r line; do
        memory_detail_json_one="\\\\\\\"$line\\\\\\\""
        memory_detail_json_array[$memory_count]=$memory_detail_json_one
        ((memory_count++))
    done < <(dmidecode -t 17 | grep "Manufacturer" | grep -Ev "Not|NO|Dimm" | awk '{print $NF}')
    # memory_list 样例
    # ["Kingston", "Kingston", ...]
    memory_list=$(make_json_array "${memory_detail_json_array[@]}")
fi
memory_size=$(grep -E "^MemTotal" /proc/meminfo | awk '{printf "%d GB", 1 + $(NF-1) / 1024 / 1024}') # 向上取整
memory_info="{\\\\\\\"model\\\\\\\":$memory_list,\\\\\\\"size\\\\\\\":\\\\\\\"$memory_size\\\\\\\"}"
# echo "$memory_info"

# ################################ disk_info ################################

disk_count=0
disk_detail_json_array=""
# done < <(xxx) 样例
# /sys/block/sda
# /sys/block/hdb
# /sys/block/vdc
while read -r line; do
    disk_dir=$line
	disk_device=$(echo $line | awk -F "/" '{print $NF}')
    disk_size=$(awk '{printf "%.2f GB", $1 / 1024 / 1024 / 2}' "$disk_dir"/size)

	#获取磁盘类型 先读取model文件,如果model文件不存在,在读取/device/wwid文件
    if [ -f "$disk_dir"/model ]; then
        disk_model=$(cat "$disk_dir"/model)
    elif [ -f "$disk_dir"/device/wwid ]; then
    	disk_model=$(cat "$disk_dir"/device/wwid | awk '{print $2}')
    else
        disk_model=""
    fi
	
	#如果磁盘型号没有获取成功 使用lsblk命令获取
	if [ ! -n "$disk_model" ]; then
		if [ $exisLsblk -eq 0 ]; then
			disk_model=`lsblk -dno MODEL /dev/$disk_device`
		fi
    fi

	#获取磁盘序列号 先读/sys/block/[shv]d*/device/wwid文件
    if [ -f "$disk_dir"/device/wwid ]; then
        disk_serial=$(cat "$disk_dir"/device/wwid | awk '{print $3}')
    else 
        disk_serial=""
    fi
	
	#如果文件获取失败  使用lsblk命令
	if [ ! -n "$disk_serial" ]; then
		if [ $exisLsblk -eq 0 ]; then
			disk_serial=`lsblk --nodeps -no serial /dev/$disk_device`
		fi
    fi

    disk_detail_json_one="{\\\\\\\"model\\\\\\\":\\\\\\\"$disk_model\\\\\\\",\\\\\\\"serialnumber\\\\\\\":\\\\\\\"$disk_serial\\\\\\\",\\\\\\\"size\\\\\\\":\\\\\\\"$disk_size\\\\\\\"}"
    disk_detail_json_array[$disk_count]=$disk_detail_json_one
    ((disk_count++))
done < <(ls -1d /sys/block/[shv]d*)
disk_list=$(make_json_array "${disk_detail_json_array[@]}")

space_utilization=$(df -P -B 1 | sed 1d | grep ^/dev/ | awk 'BEGIN{size = 0; used = 0;}{size += $2; used += $3;}END{printf "%.4f", used / size}')

part_count=0
part_detail_json_array=""
# done < <(xxx) 样例
# /dev/mapper/centos-root   17811456    1443552 16367904    9%  /
# /dev/vda1                 1038336     259388  778948      25% /boot
while read -r file_sys part_name part_size part_used; do
    if [[ $file_sys != /dev/* ]]; then
        continue
    fi
    part_detail_json_one="{\\\\\\\"name\\\\\\\":\\\\\\\"$part_name\\\\\\\",\\\\\\\"size\\\\\\\":$part_size,\\\\\\\"used\\\\\\\":$part_used}"
    part_detail_json_array[$part_count]=$part_detail_json_one
    ((part_count++))
done < <(df -P -B 1 | sed 1d | awk '{print $1, $6, $2, $3}')
part_list=$(make_json_array "${part_detail_json_array[@]}")

disk_info="{\\\\\\\"disk\\\\\\\":$disk_list,\\\\\\\"utilization\\\\\\\":\\\\\\\"$space_utilization\\\\\\\",\\\\\\\"partition\\\\\\\":$part_list}"

# echo "$disk_info"

# ################################ network_card ################################

if [ $existLsPci -ne 0 ]; then
    network_card="[]"
else
    nic_count=0
    nic_detail_json_array=""
    # done < <(xxx) 样例
    # Red Hat, Inc. Virtio network device
    while read -r line; do
        nic_detail_json_one="\\\\\\\"$line\\\\\\\""
        nic_detail_json_array[$nic_count]=$nic_detail_json_one
        ((nic_count++))
    done < <(lspci | grep Ethernet | awk -F ': ' '{print $2}')
    network_card=$(make_json_array "${nic_detail_json_array[@]}")
fi
# echo "$network_card"

# ################################ motherboard ################################
if [ $existDDC -ne 0 ]; then
    motherboard_model="\\\\\\\"\\\\\\\""
	motherboard_serial="\\\\\\\"\\\\\\\""
else
    # motherboard 样例
    # H110M-S2-CF
	  motherboard_product=$(dmidecode -s system-product-name)
	  motherboard_manufacturer=$(dmidecode -s system-manufacturer)
    motherboard_serial="\\\\\\\"$(dmidecode -s system-serial-number)\\\\\\\""
fi
motherboard="{\\\\\\\"model\\\\\\\":\\\\\\\"$motherboard_manufacturer ($motherboard_product)\\\\\\\",\\\\\\\"serialnumber\\\\\\\":$motherboard_serial}"
# echo "$motherboard"

echo "{\"name\":\"$sys_os\",\
\"version\":\"$sys_ver\",\"cpu_info\":\"$cpu_info\",\
\"memory_info\":\"$memory_info\",\"disk_info\":\"$disk_info\",\
\"net_card\":\"$network_card\",\"motherboard\":\"$motherboard\"}"
