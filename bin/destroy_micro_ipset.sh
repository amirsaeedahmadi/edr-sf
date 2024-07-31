#!/bin/bash

while read -r line; do
    ipset_name=$(echo $line | awk '{print $NF}')
    ipset destroy $ipset_name
done < <(ipset list | grep run_)



