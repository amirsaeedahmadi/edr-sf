#! /bin/bash

one_day_time=86400
grep_file_path='/data/dbg_log_data/'
current_second=$(date +%s)
oldest_time=$current_second
if [ -d $grep_file_path ]; then
	#get the oldest time
	for file_item in $(ls $grep_file_path)
	do
		path_temp=$grep_file_path$file_item
		if [ -f $path_temp ]; then
			file_modify_second=$(stat -c %Y $path_temp)
			if [ $file_modify_second -lt $oldest_time ]; then
				oldest_time=$file_modify_second
			fi
		fi
	done 

	interval_time=$(expr $oldest_time + $one_day_time)
	#delete last day files
	for file_item in $(ls $grep_file_path)
	do
		path_temp=$grep_file_path$file_item
		if [ -f $path_temp ]; then
			file_modify_second=$(stat -c %Y $path_temp)
			if [ $file_modify_second -lt $interval_time ]; then
				if [ -f $path_temp ]; then
					rm -f $path_temp
				fi
			fi
		fi
	done 
fi