#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# author: sunkang16166
# version: 1.0.0
# Copyright Sangfor. All rights reserved
# 用于实现 Berkeley DB 的存储内容解析

import os
import subprocess
import re


def bdb_dump(db_path):
    """bdb_dump 获取 Berkeley DB 的存储内容

    Args:
        db_path (string): [数据库路径]
    Returns:
        [dict]: 用户名及密码信息
    """
    # 获取可执行文件绝对路径
    exe_path = os.path.join(os.path.dirname(__file__), "db_dump")
    # 拼接执行命令
    dump_cmd = "{} -p {}".format(exe_path, db_path)
    user_info = {}

    try:
        child = subprocess.Popen(dump_cmd, stdout=subprocess.PIPE, shell=True)
        stdout = child.stdout.readlines()
    except (TypeError, ValueError, AttributeError):
        return user_info

    is_data = False
    for item in stdout:
        # 过滤信息头
        if item == b"HEADER=END\n":
            is_data = True
            continue
        elif item == b"DATA=END\n":
            is_data = False
            continue
        if is_data:
            item = item.decode()
            # 过滤字符串中开头空格及结尾换行符
            item = re.sub(r"(\\0d+)", r"", item)
            regex = re.compile(r"key:(.+) value:(.+)")
            reg_info = regex.match(item)
            if reg_info:
                key = reg_info.group(1)
                value = reg_info.group(2)
                user_info[key] = value

    return user_info

if __name__ == "__main__":
    db_path = "/etc/vsftpd/vsftpd_login.db"
    user_info = bdb_dump(db_path)
    print(len(user_info))