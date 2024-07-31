#!/bin/bash
# 2020/5/5
# Yuan Jianpeng

limit=5
agent_root=$(cd $(dirname $0)/..; pwd -P)
def_mp=$agent_root/var/cgroup/cpu
edr_sub=edr_agent
cfs_period=1000000
cfs_quota=50000
cgroup_mp=""

get_cgroup_dir() {
	if [ -n "$cgroup_mp" ]; then
		if [[ $cgroup_mp =~ $def_mp ]]
		then
			return 1
		fi
		
		return 0
	fi

	while read line ; do
		f2=$(echo "$line" | awk -F " - " '{print $2}')
		fs=$(echo "$f2" | cut -d ' ' -f 1)
		[ "$fs" == "cgroup" ] || continue
		echo "$f2" | cut -d ' ' -f 3 | grep -w cpu >/dev/null || continue
		cgroup_mp=$(echo "$line" | cut -d ' ' -f 5)
		return 0
	done < /proc/self/mountinfo

	cgroup_mp="$def_mp"
	return 1
}

check_cgroup_set() {
	get_cgroup_dir

	pfile="$cgroup_mp/$edr_sub/cgroup.procs"

	[ ! -f "$pfile" ] && exit 1 
	[ -z "`cat $pfile`" ] && exit 1
    
	exit 0
}

while getopts "cl:d" optname ; do
	case "$optname" in
	c) check_cgroup_set ;;
	l) limit="$OPTARG" ;;
	d) get_cgroup_dir; echo -e "$cgroup_mp/$edr_sub\c"; exit 0 ;;
	?) exit 1 ;;
	*) echo "invalid argument $optname" >&2 ; exit 1 ;;
	esac
done

shift $((OPTIND-1))

if [ -n "$1" ] && [ -d "/proc/$1/" ] ; then 
   echo "process with pid $1" >&2
else
   echo "no process with pid $1" >&2
   exit 1
fi

pid=$1

[ -n "$1" ] && cfs_quota=$((10000*limit))
[ $cfs_quota -ge 10000 ] || exit 1

mount_v1 () {
	get_cgroup_dir
	if [ $? == 0 ] ; then
		return 0
	fi
	
	mkdir -p "$cgroup_mp"
	mount -t cgroup -o rw,cpu none "$cgroup_mp" 
	if [ $? -ne 0 ] ; then
		echo "warning: mount cgroup failed" >&2
		return 1
	fi
			

	echo "mount cgroup v1"
	return 0
}

mount_v2 () {
	get_cgroup_dir
	if [ $? == 0 ] ; then
		return 0
	fi
	
	mkdir -p "$cgroup_mp"
	mount -t cgroup -o cpu,cpuacct none "$cgroup_mp" 
	if [ $? -ne 0 ] ; then
		echo "warning: mount cgroup failed" >&2
		return 1
    fi

	echo "mount cgroup v2"
	return 0
}

wr () { [ -f "$1" ] && echo "$2" > "$1" ; }

set_v1 () {
	cdir="$cgroup_mp/$edr_sub"
	mkdir -p "$cdir"
	wr "$cdir/cpu.cfs_period_us" $cfs_period &&
	wr "$cdir/cpu.cfs_quota_us" $cfs_quota &&
	wr "$cdir/cgroup.procs" "$pid" 
	if [ $? -ne 0 ] ; then
		echo "warning: set cgroup failed" >&2
		return 1
	fi
	echo "limit $pid via cgroup v1"
}

mount_v1 || mount_v2 || exit 1
set_v1 || exit 1