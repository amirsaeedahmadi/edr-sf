#!/bin/bash

command=$1

detectedDistro=""

function get_dist_from_etc_file()
{
	regExpLsbFile="/etc/(.*)[-_]"
	#if threre is os-release, we should find specified string that defines os type
	OsRelease="/etc/os-release"
	segName="PRETTY_NAME"
	etcFiles=`ls /etc/*[-_]{release,version} 2>/dev/null`
	for file in $etcFiles; do
		if [[ $file =~ $regExpLsbFile ]]; then
			detectedDistro=${BASH_REMATCH[1]}
			
			if [ "$file" == "$OsRelease" ]
			then
				detectedDistro=`grep $segName $file | cut -d'=' -f2 | sed 's/\"//g'`
				break;
			fi
			
			detectedDistro=`cat $file | head -n1`
			break
		else
			#echo "??? Should not occur: Don't find any etcFiles ???"
			#return "${detectedDistro}"
		break
		fi
	done
}

function get_linux_dist_ver()
{
#
# Shell script which detects the Linux distro it's running on
#
# Returned distro       Version the script was tested on
# ---------------------------------------------------------
# opensuse              openSuSE 11.0 (no lsb_release) and 11.2 (lsb_release)
# fedora                Fedora 12
# centos                CentOS 5.4
# kubuntu               Kubuntu 9.10
# debian                Debian 5.0.3
# arch                  Arch
# slackware             Slackware 13.0.0.0.0
# mandriva              Mandriva 2009.1
# debian		Knoppix 6.2
# linuxmint		Mint 8
#
# 10/02/17 framp at linux-tips-and-tricks dot de

#regExpLsbInfo="Description:[[:space:]]*([^ ]*)"
	regExpLsbInfo="Description:[[:space:]]*(.*)"
	regExpIllInfo="Description:[[:space:]]*[[:alpha:]]*=(.*)"

	if [ `which lsb_release 2>/dev/null` ]; then       # lsb_release available
   		lsbInfo=`lsb_release -d`
   		if [[ $lsbInfo =~ $regExpLsbInfo ]]; then
				local distro=${BASH_REMATCH[1]}
				if [[ $lsbInfo =~ $regExpIllInfo ]]; then
					#may be match NAME="NeoKylin Desktop"
					get_dist_from_etc_file
				else
					detectedDistro=$distro
				fi
   		fi
	else                                               # lsb_release not available
   		get_dist_from_etc_file
	fi

# detectedDistro=`echo $detectedDistro | tr "[:upper:]" "[:lower:]"`

	case $detectedDistro in
		suse) 	detectedDistro="opensuse" ;;
        linux)	detectedDistro="linuxmint" ;;
	esac

 	echo "$detectedDistro"
}

function usage()
{
    echo "now support export function as below"
    echo "get_linux_dist_ver -- get system distro version"
    exit 1
}

case $command in
  (get_linux_dist_ver)
    get_linux_dist_ver $@
    ;;
  (*)
    echo "Error command"
    usage
    ;;
esac