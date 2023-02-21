#!/usr/bin/env python3
# -*- coding:utf-8 -*-
#############################################################################
# Copyright (c) 2023 Huawei Technologies Co.,Ltd.
#
# openGauss is licensed under Mulan PSL v2.
# You can use this software according to the terms
# and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#
#          http://license.coscl.org.cn/MulanPSL2
#
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS,
# WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.
# ----------------------------------------------------------------------------
# Description  :  create a xml config file of db cluster
#############################################################################
import os
import argparse

class GenerateXML:
    """
    generate xml config file with cm.
    input: primary and standby host ips and host names.
    output: xml config file.
    usage: python3 generatexml.py --primary-host=172.0.0.1 --standby-host=172.0.0.2,172.0.0.3 --primary-hostname=host1 --standby-hostname=host2,host3
    """

    def __init__(self):
        self.cluster_config_file = "/home/omm/cluster.xml"
        self.apppath = os.environ.get("GAUSSHOME")
        self.logpath = os.environ.get("GAUSSLOG")
        self.tmppath = os.environ.get("PGHOST")
        self.toolpath = os.environ.get("GPHOME")
        self.datanodepath = "/opengauss/cluster/datanode/dn1"
        self.cmpath = "/opengauss/cluster/cm"


    def parse_args(self):
        parser = argparse.ArgumentParser(description="""
        code check pull request parameters.""")
        parser.add_argument('--primary-host', type=str, required=True, help='primary hosts.')
        parser.add_argument('--standby-host', type=str, required=True, help='standby hosts.')
        parser.add_argument('--primary-hostname', type=str, required=True, help='standby host name.')
        parser.add_argument('--standby-hostname', type=str, required=True, help='standby host names.')
        return parser.parse_args()

    def start(self):
        params = self.parse_args()
        primary_host = params.primary_host
        standby_hosts = params.standby_host.split(",")
        primary_hostname = params.primary_hostname
        standby_hostname = params.standby_hostname.split(",")
        xmlstr = self.generate_xml(primary_host, standby_hosts, primary_hostname, standby_hostname)
        with open(self.cluster_config_file, "w+") as fd:
            fd.write(xmlstr)
        

    def generate_xml(self, primary_host, standby_hosts, primary_hostname, standby_hostname):
        hostarr = [primary_host] + standby_hosts
        hostarrstr = ",".join(hostarr)

        hostnamearr = [primary_hostname] + standby_hostname
        hostnamearrstr = ",".join(hostnamearr)
        datanodes = [self.datanodepath]
        for name in standby_hostname:
            datanodes.append(name)
            datanodes.append(self.datanodepath)
        datanodestr = ",".join(datanodes)

        xml_string = """<?xml version="1.0" encoding="UTF-8"?>
<ROOT>
  <CLUSTER>
    <PARAM name="clusterName" value="gauss"/>
    <PARAM name="nodeNames" value="{hostnamelists}"/>
    <PARAM name="gaussdbAppPath" value="{apppath}"/>
    <PARAM name="gaussdbLogPath" value="{logpath}" />
    <PARAM name="tmpMppdbPath" value="{tmppath}"/>
    <PARAM name="gaussdbToolPath" value="{toolpath}"/>
    <PARAM name="corePath" value="/opengauss/cluster/corefile"/>
    <PARAM name="backIp1s" value="{hostlists}"/>
    <PARAM name="clusterType" value="single-inst"/>
  </CLUSTER>
  <DEVICELIST>
    <DEVICE sn="10000001">
        <PARAM name="name" value="{primaryhostname}"/>
        <PARAM name="backIp1" value="{primaryhost}"/>
        <PARAM name="sshIp1" value="{primaryhost}"/>
        <PARAM name="azName" value="AZ1"/>
        <PARAM name="azPriority" value="1"/>
		<PARAM name="cmsNum" value="1"/> 
        <PARAM name="cmServerPortBase" value="20000"/> 
        <PARAM name="cmServerListenIp1" value="{hostlists}"/> 
        <PARAM name="cmServerHaIp1" value="{hostlists}"/> 
        <PARAM name="cmServerlevel" value="1"/> 
        <PARAM name="cmServerRelation" value="{hostnamelists}"/> 
        <PARAM name="cmDir" value="{cmdir}"/> 
        <PARAM name="dataNum" value="1"/>
        <PARAM name="dataPortBase" value="5432"/>
        <PARAM name="dataPortStandby" value="5432"/>
        <PARAM name="dataPortDummyStandby" value="5432"/>
        <PARAM name="dataNode1" value="{dataNode1}"/>
    </DEVICE>
        """.format(hostlists=hostarrstr, apppath=self.apppath, logpath=self.logpath, tmppath=self.tmppath,
    toolpath=self.toolpath, hostnamelists=hostnamearrstr, primaryhostname=primary_hostname, primaryhost=primary_host,
    cmdir=self.cmpath, dataNode1=datanodestr)
	
        for idx,host in enumerate(standby_hosts):
            s_str = """
        <DEVICE sn="{snid}">
            <PARAM name="name" value="{hostname}"/>
            <PARAM name="backIp1" value="{host}"/>
            <PARAM name="sshIp1" value="{host}"/>
            <PARAM name="azName" value="AZ1"/>
            <PARAM name="azPriority" value="1"/>
            <PARAM name="cmDir" value="{cmdir}"/> 
        </DEVICE>
        """.format(snid=10000002 + idx, hostname=standby_hostname[idx], host=host, cmdir=self.cmpath)
            xml_string += s_str

        xml_string += """
    </DEVICELIST>
    </ROOT>
            """
        return xml_string

if __name__ == '__main__':
    req = GenerateXML()
    req.start()

