#!/bin/bash

# Copyright (c) 2026 Huawei Technologies Co., Ltd.
# openGauss-container is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#          http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

NODES_FILE="$1"
GS_PASSWORD="$2"


if [ ! -f "$NODES_FILE" ]; then
    echo "hostfile NODES_FILE not exists"
    exit 1
fi

NODES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ ! "$line" =~ ^\s*# ]] && [[ -n "$line" ]]; then
        NODES+=("$line")
    fi
done < "$NODES_FILE"


if [ ${#NODES[@]} -eq 0 ]; then
    echo "node is not found"
    exit 1
fi


if [ ! -f ~/.ssh/id_rsa ]; then
    echo "generate rsa..."
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
else
    echo "skip to rsa already exists..."
fi

function expect_createtrust() {
    /usr/bin/expect <<-EOF
        set timeout -1
        spawn ssh-copy-id -o "StrictHostKeyChecking=no" $1
        expect {
                "password:" { send "$2\r"; exp_continue }
                "*$3*" { exit }
        }
        expect eof
EOF
    if [ $? == 0 ]; then
        return 0
    else
        return 1
    fi
}

for node in "${NODES[@]}"; do
    echo "create trust of node: $node"

    expect_createtrust "$node" "$GS_PASSWORD" "config success"

    echo "test trust connection with node $node..."
    timeout 300 ssh -o "StrictHostKeyChecking=no" "$node" "echo 'create trust success.'"
    
    if [ $? -eq 0 ]; then
        echo "$node config success"
    else
        echo "$node config failed"
    fi
done
