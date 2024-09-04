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
# Description  : gs_sshexkey is a utility to create SSH trust among nodes in
# a cluster.
#############################################################################

import sys
import warnings

warnings.simplefilter('ignore', DeprecationWarning)
# sys.path.append(sys.path[0] + "/../lib")
import time
import os
import subprocess
import pwd
import grp
import socket
import getpass
import shutil
import secrets
import string
import platform
import gc
from gspylib.common.GaussLog import GaussLog
from gspylib.common.ErrorCode import ErrorCode
from gspylib.threads.parallelTool import parallelTool
from gspylib.common.Common import DefaultValue, ClusterCommand
from gspylib.common.ParameterParsecheck import Parameter
from base_utils.os.env_util import EnvUtil
from base_utils.os.file_util import FileUtil
from base_utils.os.grep_util import GrepUtil
from base_utils.os.password_util import PasswordUtil
from base_utils.os.net_util import NetUtil
from subprocess import PIPE
from base_utils.common.fast_popen import FastPopen

# DefaultValue.doConfigForParamiko()
import paramiko

from gspylib.threads.SshTool import SshTool

HOSTS_MAPPING_FLAG = "#Gauss OM IP Hosts Mapping"
ipHostInfo = ""
#the tmp path
tmp_files = ""
#tmp file name
TMP_TRUST_FILE = "step_preinstall_file.dat"


class PrintOnScreen():
    """
    class about print on screen
    """
    def __init__(self):
        '''
        function : Constructor
        input: NA
        output: NA
        '''
        pass

    def log(self, msg):
        '''
        function : print log
        input: msg: str
        output: NA
        '''
        print(msg)

    def debug(self, msg):
        '''
        function : debug
        input: msg: debug message string
        output: NA
        '''
        pass

    def error(self, msg):
        '''
        function : error
        input: msg: error message string
        output: NA
        '''
        pass

    def logExit(self, msg):
        '''
        function : print log and exit
        input: msg: str
        output: NA
        '''
        print(msg)
        sys.exit(1)


class GaussCreateTrust():
    """
    class about create trust for user
    """
    def __init__(self):
        '''
        function : Constructor
        input: NA
        output: NA
        '''
        self.logger = None
        self.hostFile = ""
        self.hostList = []
        self.passwd = []
        self.hosts_paswd_list = []
        self.logFile = ""
        self.localHost = ""
        self.flag = False
        self.localID = ""
        self.user = pwd.getpwuid(os.getuid()).pw_name
        self.group = grp.getgrgid(os.getgid()).gr_name
        self.incorrectPasswdInfo = ""
        self.failedToAppendInfo = ""
        self.homeDir = os.path.expanduser("~" + self.user)
        self.sshDir = "%s/.ssh" % self.homeDir
        self.authorized_keys_fname = DefaultValue.SSH_AUTHORIZED_KEYS
        self.known_hosts_fname = DefaultValue.SSH_KNOWN_HOSTS
        self.id_rsa_fname = DefaultValue.SSH_PRIVATE_KEY
        self.id_rsa_pub_fname = DefaultValue.SSH_PUBLIC_KEY
        self.skipHostnameSet = False
        self.isKeyboardPassword = False
        # init SshTool
        self.ssh_tool = None
        self.secret_word = ""

    def usage(self):
        """
gs_sshexkey is a utility to create SSH trust among nodes in a cluster.

Usage:
  gs_sshexkey -? | --help
  gs_sshexkey -V | --version
  gs_sshexkey -f HOSTFILE [--skip-hostname-set] [...] [-l LOGFILE]

General options:
  -f                          Host file containing the IP address of nodes.
  -l                          Path of log file.
      --skip-hostname-set     Whether to skip hostname setting. (The default value is set.)
  -?, --help                  Show help information for this utility,
                              and exit the command line mode.
  -V, --version               Show version information.
        """
        print(self.usage.__doc__)

    def parseCommandLine(self):
        """
        function: Check parameter from command line
        input : NA
        output: NA
        """
        paraObj = Parameter()
        paraDict = paraObj.ParameterCommandLine("sshexkey")
        if "helpFlag" in list(paraDict.keys()):
            self.usage()
            sys.exit(0)

        if "hostfile" in list(paraDict.keys()):
            self.hostFile = paraDict.get("hostfile")
        if "logFile" in list(paraDict.keys()):
            self.logFile = paraDict.get("logFile")
        if "skipHostnameSet" in list(paraDict.keys()):
            self.skipHostnameSet = paraDict.get("skipHostnameSet")

    def checkParameter(self):
        """
        function: Check parameter from command line
        input : NA
        output: NA
        """
        # check required parameters
        if self.hostFile == "":
            self.usage()
            GaussLog.exitWithError(ErrorCode.GAUSS_500["GAUSS_50001"] % 'f' + ".")
        if not os.path.exists(self.hostFile):
            GaussLog.exitWithError(ErrorCode.GAUSS_502["GAUSS_50201"] % self.hostFile)
        if not os.path.isabs(self.hostFile):
            GaussLog.exitWithError(ErrorCode.GAUSS_502["GAUSS_50213"] % self.hostFile)

        #read host file to hostList
        self.readHostFile()    
        
        if not self.hostList:
            GaussLog.exitWithError(ErrorCode.GAUSS_500["GAUSS_50004"] % 'f' +
                                   " It cannot be empty.")
       
        #check logfile  
        if self.logFile != "":
            if not os.path.isabs(self.logFile):
                GaussLog.exitWithError(ErrorCode.GAUSS_502["GAUSS_50213"] % self.logFile)

        if not self.passwd:
            self.passwd = self.getUserPasswd()
            self.isKeyboardPassword = True
    
    def readHostFile(self):
        """
        function: read host file to hostList
        input : NA
        output: NA
        """
        inValidIp = []
        try:
            with open(self.hostFile, "r") as f:
                for readLine in f:
                    hostname = readLine.strip().split("\n")[0]
                    if hostname != "" and hostname not in self.hostList:
                        if not NetUtil.isIpValid(hostname):
                            inValidIp.append(hostname)
                            continue
                        self.hostList.append(hostname)
            if len(inValidIp) > 0:
                GaussLog.exitWithError(ErrorCode.GAUSS_506["GAUSS_50603"]
                                       + "The IP list is:%s." % inValidIp)
        except Exception as e:
            raise Exception(ErrorCode.GAUSS_502["GAUSS_50204"] % "host file"
                            + " Error: \n%s" % str(e))

    def getAllHostsName(self, ip):
        """
        function:
          Connect to all nodes ,then get all hostaname by threading
        precondition:
          1.User's password is correct on each node
        postcondition:
           NA
        input: ip
        output:Dictionary ipHostname,key is IP  and value is hostname
        hideninfo:NA
        """

        ipHostname = {}
        try:
            ssh = paramiko.Transport((ip, 22))
        except Exception as e:
            raise Exception(ErrorCode.GAUSS_512["GAUSS_51220"] % ip
                            + " Error: \n%s" % str(e))
        try:
            ssh.connect(username=self.user, password=self.passwd[0])
        except Exception as e:
            ssh.close()
            raise Exception(ErrorCode.GAUSS_503["GAUSS_50306"] % ip)

        check_channel = ssh.open_session()
        cmd = "cd"
        check_channel.exec_command(cmd)
        env_msg = check_channel.recv_stderr(9999).decode().strip()
        while True:
            channel_read = check_channel.recv(9999).decode().strip()
            if len(channel_read) != 0:
                env_msg += str(channel_read)
            else:
                break
        if env_msg != "":
            ipHostname["Node[%s]" % ip] = "Output: [" + env_msg \
                                          + " ] print by /etc/profile or" \
                                            " ~/.bashrc, please check it."
            ssh.close()
            return ipHostname

        channel = ssh.open_session()
        cmd = "hostname"
        channel.exec_command(cmd)
        hostname = channel.recv(9999).decode().strip()
        ipHostname[ip] = hostname
        ssh.close()
        return ipHostname

    def verifyPasswd(self, ssh, pswd=None):
        try:
            ssh.connect(username=self.user, password=pswd)
            return True
        except Exception:
            ssh.close()
            return False

    def parallelGetHosts(self, sshIps):
        parallelResult = {}
        ipHostname = parallelTool.parallelExecute(self.getAllHostsName, sshIps)

        err_msg = ""
        for i in ipHostname:
            for (key, value) in list(i.items()):
                if key.find("Node") >= 0:
                    err_msg += str(i)
                else:
                    parallelResult[key] = value
        if len(err_msg) > 0:
            raise Exception(ErrorCode.GAUSS_518["GAUSS_51808"] % err_msg)
        return parallelResult

    def serialGetHosts(self, sshIps):
        serialResult = {}
        invalidIP = ""
        boolInvalidIp = False
        for sshIp in sshIps:
            isPasswdOK = False
            for pswd in self.passwd:
                try:
                    ssh = paramiko.Transport((sshIp, 22))
                except Exception as e:
                    self.logger.debug(str(e))
                    invalidIP += "Incorrect IP address: %s.\n" % sshIp
                    boolInvalidIp = True
                    break
                finally:
                    if ssh is not None:
                        ssh.close()

                isPasswdOK = self.verifyPasswd(ssh, pswd)
                if isPasswdOK:
                    self.hosts_paswd_list.append([sshIp, pswd])
                    break

            if boolInvalidIp:
                boolInvalidIp = False
                continue

            if not isPasswdOK and self.isKeyboardPassword:
                GaussLog.printMessage("Please enter password for current user[%s] on the "
                                      "node[%s]." % (self.user, sshIp))
                # Try entering the password 3 times interactively
                for i in range(3):
                    try:
                        KeyboardPassword = getpass.getpass()
                        PasswordUtil.checkPasswordVaild(KeyboardPassword)
                        ssh = paramiko.Transport((sshIp, 22))
                        isPasswdOK = self.verifyPasswd(ssh, KeyboardPassword)
                        if isPasswdOK:
                            self.passwd.append(KeyboardPassword)
                            self.hosts_paswd_list.append([sshIp, KeyboardPassword])
                            break
                        else:
                            continue
                    except Exception as e:
                        raise Exception(ErrorCode.GAUSS_512["GAUSS_51220"] % sshIp +
                                        " Error: \n%s" % str(e))
                    finally:
                        del KeyboardPassword
                        gc.collect()
            # if isKeyboardPassword is true, 3 times after the password is
            # also wrong to throw an unusual exit
            if not isPasswdOK:
                raise Exception(ErrorCode.GAUSS_503["GAUSS_50306"] % sshIp)

            cmd = "cd"
            check_channel = ssh.open_session()
            check_channel.exec_command(cmd)
            check_result = check_channel.recv_stderr(9999).decode()
            while True:
                channel_read = check_channel.recv(9999).decode()
                if len(channel_read) != 0:
                    check_result += str(channel_read)
                else:
                    break

            if check_result != "":
                raise Exception(ErrorCode.GAUSS_518["GAUSS_51808"] % check_result +
                                "Please check %s node /etc/profile or ~/.bashrc" % sshIp)
            else:
                cmd = "hostname"
                channel = ssh.open_session()
                channel.exec_command(cmd)
                while True:
                    hostname = channel.recv(9999).decode().strip()
                    if len(hostname) != 0:
                        serialResult[sshIp] = hostname
                    else:
                        break
                ssh.close()

        if invalidIP:
            raise Exception(ErrorCode.GAUSS_511["GAUSS_51101"] % invalidIP.rstrip("\n"))
        return serialResult

    def getAllHosts(self, sshIps):
        """
        function:
          Connect to all nodes ,then get all hostaname
        precondition:
          1.User's password is correct on each node
        postcondition:
           NA
        input: sshIps,username,passwd
        output:Dictionary ipHostname,key is IP  and value is hostname
        hideninfo:NA
        """
        if self.logFile != "":
            if not os.path.exists(tmp_files):
                self.logger.debug("Get hostnames for all nodes.", "addStep")
            else:
                self.logger.debug("Get hostnames for all nodes.")
        if len(self.passwd) == 0:
            self.isKeyboardPassword = True
            GaussLog.printMessage("Please enter password for current user[%s]." % self.user)
            passwd = getpass.getpass()
            self.passwd.append(passwd)
            del passwd
            gc.collect()

        if len(self.passwd) == 1:
            try:
                result = self.parallelGetHosts(sshIps)
            except Exception as e:
                if (self.isKeyboardPassword and str(e).startswith(
                        "[GAUSS-50306] : The password of")):
                    GaussLog.printMessage(
                        "Notice :The password of some nodes is incorrect.")
                    result = self.serialGetHosts(sshIps)
                else:
                    raise Exception(str(e))
        else:
            result = self.serialGetHosts(sshIps)
        if self.logFile != "":
            if not os.path.exists(tmp_files):
                self.logger.debug("Successfully get hostnames for all nodes.", "constant")
            else:
                self.logger.debug("Successfully get hostnames for all nodes.")
        return result

    def writeLocalHosts(self, result):
        """
        function:
         Write hostname and Ip into /etc/hosts when there's not the same one in /etc/hosts file 
        precondition:
          NA
        postcondition:
           NA
        input: Dictionary result,key is IP and value is hostname
        output: NA
        hideninfo:NA
        """
        self._debug("Write local hostname and Ip into /etc/hosts.", "addStep")
        hostIPInfo = ""
        if os.getuid() == 0:
            tmpHostIpName = "./tmp_hostsiphostname_%d" % os.getpid()
            # Check if /etc/hosts exists.
            if not os.path.exists("/etc/hosts"):
                raise Exception(ErrorCode.GAUSS_512["GAUSS_51221"] +
                                " Error: \nThe /etc/hosts does not exist.")
            (status, output) = GrepUtil.getGrepValue("-v", " #Gauss.* IP Hosts Mapping",
                                                     '/etc/hosts')
            result["127.0.0.1"] = "localhost"
            FileUtil.createFile(tmpHostIpName)
            FileUtil.changeMode(DefaultValue.KEY_FILE_MODE, tmpHostIpName)
            FileUtil.writeFile(tmpHostIpName, [output])
            shutil.copyfile(tmpHostIpName, '/etc/hosts')
            FileUtil.removeFile(tmpHostIpName)
            for (key, value) in list(result.items()):
                hostIPInfo += '%s  %s  %s\n' % (key, value, HOSTS_MAPPING_FLAG)
            hostIPInfo = hostIPInfo[:-1]
            ipInfoList = [hostIPInfo]
            FileUtil.writeFile("/etc/hosts", ipInfoList)
        self._debug("Successfully write local hostname and Ip into /etc/hosts.", "constant")

    def writeRemoteHostName(self, ip):
        """
        function:
         Write hostname and Ip into /etc/hosts when there's not the same one
         in /etc/hosts file by threading
        precondition:
          NA
        postcondition:
           NA
        input: ip
        output: NA
        hideninfo:NA
        """
        writeResult = []
        result = {}
        tmpHostIpName = "./tmp_hostsiphostname_%d_%s" % (os.getpid(), ip)
        username = pwd.getpwuid(os.getuid()).pw_name
        global ipHostInfo
        try:
            ssh = paramiko.Transport((ip, 22))
        except Exception as e:
            raise Exception(ErrorCode.GAUSS_511["GAUSS_51107"] + " Error: \n%s" % str(e))
        try:
            ssh.connect(username=username, password=self.passwd[0])
        except Exception as e:
            ssh.close()
            raise Exception(ErrorCode.GAUSS_503["GAUSS_50317"] + " Error: \n%s" % str(e))
        cmd = "grep -v '%s' %s > %s && cp %s %s && rm -rf %s" % (" #Gauss.* IP Hosts Mapping",
                                                                 '/etc/hosts', tmpHostIpName,
                                                                 tmpHostIpName, '/etc/hosts',
                                                                 tmpHostIpName)
        channel = ssh.open_session()
        channel.exec_command(cmd)
        ipHosts = channel.recv(9999).decode().strip()
        errInfo = channel.recv_stderr(9999).decode().strip()
        if(errInfo):
            writeResult.append(errInfo)
        else:
            if not ipHosts:
                cmd = "echo '%s' >> /etc/hosts" % (ipHostInfo)
                channel = ssh.open_session()
                channel.exec_command(cmd)
                errInfo = channel.recv_stderr(9999).decode().strip()
                if errInfo:
                    writeResult.append(errInfo)
        if channel:
            channel.close()
        result[ip] = writeResult
        if len(writeResult) > 0:
            return False, result
        else:
            return True, result

    def writeRemoteHosts(self, result, username, rootPasswd):
        """
        function:
         Write hostname and Ip into /etc/hosts when there's not the same one
         in /etc/hosts file
        precondition:
          NA
        postcondition:
           NA
        input: Dictionary result,key is IP and value is hostname
                    rootPasswd
        output: NA
        hideninfo:NA
        """
        self._debug("Write remote hostname and Ip into /etc/hosts.", "addStep")
        global ipHostInfo
        boolInvalidIp = False
        ipHostInfo = ""
        if os.getuid() == 0:
            writeResult = []
            tmpHostIpName = "./tmp_hostsiphostname_%d" % os.getpid()

            if len(rootPasswd) == 1:
                result1 = {}
                for (key, value) in list(result.items()):
                    ipHostInfo += '%s  %s  %s\n' % (key, value, HOSTS_MAPPING_FLAG)
                    if value not in (self.localHost, "localhost"):
                        if not value in list(result1.keys()):
                            result1[value] = key

                sshIps = list(result1.keys())
                ipHostInfo = ipHostInfo[:-1]
                if sshIps:
                    ipRemoteHostname = parallelTool.parallelExecute(self.writeRemoteHostName,
                                                                    sshIps)
                    errorMsg = ""
                    for (key, value) in ipRemoteHostname:
                        if not key:
                            errorMsg = errorMsg + '\n' + str(value)
                    if errorMsg != "":
                        raise Exception(ErrorCode.GAUSS_512["GAUSS_51221"] + " Error: %s" %
                                        errorMsg)
            else:
                for (key, value) in list(result.items()):
                    if value == self.localHost or value == "localhost":
                        continue
                    for pswd in rootPasswd:
                        try:
                            ssh = paramiko.Transport((key, 22))
                        except Exception as e:
                            self.logger.debug(str(e))
                            boolInvalidIp = True
                            break
                        try:
                            ssh.connect(username=username, password=pswd)
                            break
                        except Exception as e:
                            self.logger.debug(str(e))
                            continue
                    if boolInvalidIp:
                        boolInvalidIp = False
                        continue
                    cmd = "grep -v '%s' %s > %s && cp %s %s && rm -rf %s" % \
                          (" #Gauss.* IP Hosts Mapping", '/etc/hosts', tmpHostIpName,
                           tmpHostIpName, '/etc/hosts', tmpHostIpName)
                    channel = ssh.open_session()
                    channel.exec_command(cmd)
                    ipHosts = channel.recv(9999).decode().strip()
                    errInfo = channel.recv_stderr(9999).decode().strip()
                    if errInfo:
                        writeResult.append(errInfo)
                    else:                        
                        if not ipHosts:
                            ipHostInfo = ""
                            for (key1, value1) in list(result.items()): 
                                ipHostInfo += '%s  %s  %s\n' % (key1, value1, HOSTS_MAPPING_FLAG)
                            ipHostInfo = ipHostInfo[:-1]
                            cmd = "echo '%s' >> /etc/hosts" % ipHostInfo
                            channel = ssh.open_session()
                            channel.exec_command(cmd)
                            errInfo = channel.recv_stderr(9999).decode().strip()
                            if errInfo:
                                writeResult.append(errInfo)

                    if channel:
                        channel.close()

                if len(writeResult) > 0:
                    raise Exception(ErrorCode.GAUSS_512["GAUSS_51221"] +
                                    " Error: \n%s" % writeResult)
        self._debug("Successfully write remote hostname and Ip into /etc/hosts.", "constant")

    def initLogger(self):
        """
        function: Init logger
        input : NA
        output: NA
        """
        if self.logFile != "":
            self.logger = GaussLog(self.logFile, "gs_sshexkey")
        else:
            self.logger = PrintOnScreen()

    def checkNetworkInfo(self):
        """
        function: check  local node to other node Network Information
        input : NA
        output: NA
        """
        self._log("Checking network information.", "addStep")
        try:
            netWorkList = DefaultValue.checkIsPing(self.hostList)
            if not netWorkList:
                self.logger.log("All nodes in the network are Normal.")
            else:
                self.logger.logExit(ErrorCode.GAUSS_506["GAUSS_50600"] +
                                    "The IP list is:%s." % netWorkList)
        except Exception as e:
            self.logger.logExit(str(e))
        self._log("Successfully checked network information.", "constant")

    def run(self):
        """
        function: Do create SSH trust
        input : NA
        output: NA
        """
        self.parseCommandLine()
        self.checkParameter()
        self.localHost = socket.gethostname()
        self.init_sshtool()
        self.initLogger()
        global tmp_files
        tmp_files = "/tmp/%s" % TMP_TRUST_FILE
        if self.logFile != "":
            if not os.path.exists(tmp_files):
                self.logger.debug("gs_sshexkey execution takes %s steps in total" %
                                  ClusterCommand.countTotalSteps("gs_sshexkey", "",
                                                                 self.skipHostnameSet))
        Ips = []
        Ips.extend(self.hostList)
        result = self.getAllHosts(Ips)
        self.checkNetworkInfo()

        if not self.skipHostnameSet:
            self.writeLocalHosts(result)
            self.writeRemoteHosts(result, self.user, self.passwd)

        self.logger.log("Creating SSH trust.")
        try:                      
            self.retry_create_public_private_keyfile()
            self.addLocalAuthorized()
            self.updateKnow_hostsFile(result)
            self.addRemoteAuthorization()
            self.determinePublicAuthorityFile()
            self.synchronizationLicenseFile()
            self.retry_register_other_ssh_agent()
            self.verifyTrust()
            self.logger.log("Successfully created SSH trust.")
        except Exception as e:
            self.logger.logExit(str(e))
        finally:
            self.passwd = []

    def createPublicPrivateKeyFile(self):
        """
        function: create  local public private key file
        input : NA
        output: NA
        """
        # import pdb;pdb.set_trace()
        if self.logFile != "" and not os.path.exists(tmp_files):
            self.logger.log("Creating the local key file.", "addStep")
        else:
            self.logger.log("Creating the local key file.")

        FileUtil.removeFile(self.id_rsa_fname)
        FileUtil.removeFile(self.id_rsa_pub_fname)
        secret_word = self.get_secret(32)
        self.secret_word = secret_word
        localDirPath = os.path.dirname(os.path.realpath(__file__))
        encrypt_shell_file = os.path.join(localDirPath, "./local/sshexkey_encrypt_tool.sh")
        cmd = "echo \"%s\" | /bin/sh %s %s %s %s" % (secret_word, encrypt_shell_file,
                                                     "sshkeygen", self.id_rsa_fname,
                                                     self.id_rsa_pub_fname)
        self.logger.debug("ssh-keygen cmd is:%s" % cmd)
        proc = FastPopen(cmd, stdout=PIPE, stderr=PIPE)
        stdout, stderr = proc.communicate()
        output = stdout + stderr
        status = proc.returncode
        if status != 0:
            raise Exception(ErrorCode.GAUSS_511["GAUSS_51108"] + " Error:\n%s" % output)
        f = None
        try:
            try: 
                f = open(self.id_rsa_pub_fname, 'r') 
                return f.readline().strip()
            except IOError as e:
                self.logger.debug(str(e))
                raise Exception(ErrorCode.GAUSS_511["GAUSS_51108"] +
                                " Unable to read the generated file." + self.id_rsa_pub_fname)
        finally:
            if f:
                f.close()
            # register ssh agent for ssh passphrase
            self.encrypt_pass_phrase(secret_word)
            self.logger.debug("encrypt passphrase successfully.")
            mpprcfile = EnvUtil.getMpprcFile()
            DefaultValue.register_ssh_agent(mpprcfile, self.logger)

            #Mounting private keys to ssh-agent
            bashrc_file = os.path.join(pwd.getpwuid(os.getuid()).pw_dir,
                                       ".bashrc")
            localDirPath = os.path.dirname(os.path.realpath(__file__))
            shell_file = os.path.join(localDirPath, "./local/ssh-agent.sh")
            DefaultValue.add_ssh_id_rsa(secret_word, bashrc_file, shell_file, self.logger)
            self.logger.debug("Ssh agent register successfully.")
            self._log("Successfully created the local key files.", "constant")

    def addLocalAuthorized(self):
        """
        function: append the local id_rsa.pub value provided to authorized_keys
        input : NA
        output: NA
        """
        self._log("Appending local ID to authorized_keys.", "addStep")
        f = None
        try:
            FileUtil.createFileInSafeMode(self.authorized_keys_fname)
            f = open(self.authorized_keys_fname, 'a+')
            for line in f:
                if line.strip() == self.localID + " #OM":
                    # The localID is already in authorizedKeys; no need to add
                    return
            f.write(self.localID + " #OM")
            f.write('\n')
            self._log("Successfully appended local ID to authorized_keys.", "constant")
        finally:
            if f:
                f.close()
        FileUtil.changeMode(DefaultValue.KEY_FILE_MODE, self.authorized_keys_fname)

    def checkAuthentication(self, hostname):
        """
        function: Ensure the proper password-less access to the remote host.
        input : hostname
        output: True/False, hostname
        """
        bashrc_file = os.path.join(pwd.getpwuid(os.getuid()).pw_dir, ".bashrc")
        cmd = 'source %s;ssh -n %s %s true' % (bashrc_file,
                                               DefaultValue.SSH_OPTION, hostname)
        (status, output) = subprocess.getstatusoutput(cmd)
        if status != 0:
            self.logger.debug("Failed to check authentication.cmd:%s Hostname:%s. Error: \n%s" %
                              (cmd, hostname, output))
            return False, hostname
        return True, hostname

    def updateKnow_hostsFile(self, result):
        """
        function: keyscan all hosts and update known_hosts file
        input : result
        output: NA
        """
        self._log("Updating the known_hosts file.", "addStep")
        hostnameList = []
        hostnameList.extend(self.hostList)
        for(key, value) in list(result.items()):
            hostnameList.append(value)
        for hostname in hostnameList:
            cmd = 'ssh-keyscan -t ed25519 %s >> %s ' % (hostname, self.known_hosts_fname)
            cmd += '&& sed -i "$ s/$/ #OM/" %s ' % self.known_hosts_fname
            cmd += "&& chmod %s %s" % (DefaultValue.KEY_FILE_MODE, self.known_hosts_fname)
            (status, output) = subprocess.getstatusoutput(cmd)
            if status != 0:
                raise Exception(ErrorCode.GAUSS_514["GAUSS_51400"] % cmd + " Error:\n%s" % output)
        (status, output) = self.checkAuthentication(self.localHost)
        if not status:
            raise Exception(ErrorCode.GAUSS_511["GAUSS_51100"] % self.localHost)
        self._log("Successfully updated the known_hosts file.", "constant")

    def tryParamikoConnect(self, hostname, client, pswd = None, silence = False):
        """
        function: try paramiko connect
        input : hostname, client, pswd, silence
        output: True/False
        """
        try:
            client.connect(hostname, password=pswd, allow_agent=False, look_for_keys=False)
            return True
        except paramiko.AuthenticationException as e:
            if not silence: 
                self.logger.debug("Incorrect password. Node: %s." % hostname +
                                  " Error:\n%s" % str(e))
            client.close()
            return False
        except Exception as e:
            if not silence: 
                self.logger.debug('[SSHException %s] %s' % (hostname, str(e)))
            client.close()
            raise Exception(str(e))

    def addRemoteAuthorization(self):
        """
        function: Send local ID to remote over SSH, and append to authorized_key
        input : NA
        output: NA
        """
        self._log("Appending authorized_key on the remote node.", "addStep")
        try:
            parallelTool.parallelExecute(self.sendRemoteAuthorization, self.hostList)
            if self.incorrectPasswdInfo != "":
                self.logger.logExit(ErrorCode.GAUSS_511["GAUSS_51101"] %
                                    (self.incorrectPasswdInfo.rstrip("\n")))
            if self.failedToAppendInfo != "":
                self.logger.logExit(ErrorCode.GAUSS_511["GAUSS_51101"] %
                                    (self.failedToAppendInfo.rstrip("\n")))
        except Exception as e:
            self.logger.logExit(ErrorCode.GAUSS_511["GAUSS_51111"] + " Error:%s." % str(e))
        self._log("Successfully appended authorized_key on all remote node.", "constant")

    def sendRemoteAuthorization(self, hostname): 
        """
        function: send remote authorization
        input : hostname
        output: NA
        """
        if hostname != self.localHost:
            p = None
            cin = cout = cerr = None
            try:
                #ssh Remote Connection other node
                p = paramiko.SSHClient()
                # p.load_system_host_keys()    
                p.set_missing_host_key_policy(paramiko.AutoAddPolicy())      
                ok = self.tryParamikoConnect(hostname, p, self.passwd[0], silence = True)
                if not ok:
                    for pswd in self.passwd[1:]:
                        ok = self.tryParamikoConnect(hostname, p, pswd, silence = True)
                        if ok:
                            break
                if not ok:
                    self.incorrectPasswdInfo += "Without this node[%s] of the correct password.\n"\
                                                % hostname
                    return
                # Create .ssh directory and ensure content meets permission requirements 
                # for password-less SSH
                cmd = ('mkdir -p .ssh; ' +
                       "chown -R %s:%s %s; " % (self.user, self.group, self.sshDir) +
                       'chmod %s .ssh; ' % DefaultValue.KEY_DIRECTORY_MODE +
                       'touch .ssh/authorized_keys; ' +
                       'touch .ssh/known_hosts; ' +
                       'chmod %s .ssh/auth* .ssh/id* .ssh/known_hosts; ' %
                       DefaultValue.KEY_FILE_MODE)
                (cin, cout, cerr) = p.exec_command(cmd)
                cin.close()
                cout.close()
                cerr.close()

                # Append the ID to authorized_keys;
                cnt = 0
                cmd = 'echo \"%s #OM\" >> .ssh/authorized_keys && echo ok ok ok' % self.localID
                (cin, cout, cerr) = p.exec_command(cmd)
                cin.close()
                #readline will read other msg.
                line = cout.read().decode()
                while line.find("ok ok ok") < 0:
                    time.sleep(cnt * 2)
                    cmd = 'echo \"%s #OM\" >> .ssh/authorized_keys && echo ok ok ok' % self.localID
                    (cin, cout, cerr) = p.exec_command(cmd)
                    cin.close()
                    cnt += 1
                    line = cout.readline()
                    if cnt >= 3:
                        break
                    if line.find("ok ok ok") < 0:
                        continue
                    else:
                        break

                if line.find("ok ok ok") < 0:
                    self.failedToAppendInfo += "...send to %s\nFailed to append local ID to " \
                                               "authorized_keys on remote node %s.\n" % \
                                               (hostname, hostname)
                    return
                cout.close()
                cerr.close()
                self.logger.debug("Send to %s\nSuccessfully appended authorized_key on"
                                  " remote node %s." % (hostname, hostname))
            finally:
                if cin:
                    cin.close()
                if cout:
                    cout.close()
                if cerr:
                    cerr.close()
                if p:
                    p.close()

    def determinePublicAuthorityFile(self):
        '''
        function: determine common authentication file content
        input : NA
        output: NA
        '''
        self._log("Checking common authentication file content.", "addStep")
        # eliminate duplicates in known_hosts file
        try:
            tab = self.readKnownHosts()
            self.writeKnownHosts(tab)
        except IOError as e:
            self.logger.logExit(ErrorCode.GAUSS_502["GAUSS_50230"] % "known hosts file" +
                                " Error:\n%s" % str(e))
        
        # eliminate duploicates in authorized_keys file
        try:
            tab = self.readAuthorizedKeys()
            self.writeAuthorizedKeys(tab)
        except IOError as e:
            self.logger.logExit(ErrorCode.GAUSS_502["GAUSS_50230"] % "authorized keys file" +
                                " Error:\n%s" % str(e))
        self._log("Successfully checked common authentication content.", "constant")

    def addRemoteID(self, tab, line):
        """
        function: add remote node id
        input : tab, line
        output: True/False
        """
        key = line.strip().split()
        if line[0] == "#":
            return True
        elif len(key) != 4:
            tab[line] = line
        else:
            tab[key[2] + key[3]] = line

    def readAuthorizedKeys(self, tab=None, keysFile=None):
        """
        function: read authorized keys
        input : tab, keysFile
        output: tab
        """
        if not keysFile:
            keysFile = self.authorized_keys_fname
        if not tab:
            tab = {}
        with open(keysFile, 'r') as f:
            for line in f:
                self.addRemoteID(tab, line)
        return tab

    def writeAuthorizedKeys(self, tab, keysFile=None):
        """
        function: write authorized keys
        input : tab, keysFile
        output: True/False
        """
        if not keysFile:
            keysFile = self.authorized_keys_fname
        with open(keysFile, 'w') as f:
            for IDKey in tab:
                f.write(tab[IDKey])

    def addKnownHost(self, tab, line):
        """
        function: add known host
        input : tab, line
        output: True/False
        """
        key = line.strip().split()
        if line[0] == "#":
            return True
        elif len(key) != 4:
            tab[line] = line
        else:
            tab[key[0] + key[3]] = line

    def readKnownHosts(self, tab=None, hostsFile=None):
        """
        function: read known host
        input : tab, hostsFile
        output: tab
        """
        if not hostsFile:
            hostsFile = self.known_hosts_fname
        if not tab:
            tab = {}
        with open(hostsFile, 'r') as f:
            for line in f:
                self.addKnownHost(tab, line)
        return tab

    def writeKnownHosts(self, tab, hostsFile=None):
        """
        function: write known host
        input : tab, hostsFile
        output: NA
        """
        if not hostsFile:
            hostsFile = self.known_hosts_fname
        with open(hostsFile, 'w') as f:
            for key in tab:
                f.write(tab[key])

    def sendTrustFile(self, hostname):
        '''
        function: Set or update the authentication files on  hostname
        input : hostname
        output: NA
        '''
        bashrc_file = os.path.join(pwd.getpwuid(os.getuid()).pw_dir, ".bashrc")
        cmd = 'source %s;' %bashrc_file
        cmd += ('scp -q -o "BatchMode yes" -o "NumberOfPasswordPrompts 0" ' +
                '%s %s %s:.ssh/' % (self.id_rsa_fname, self.id_rsa_pub_fname, hostname))
        cmd += ''' && temp_auth=$(grep '#OM' %s)''' \
               ''' && ssh %s "sed -i '/#OM/d' %s; echo '${temp_auth}' >> %s"''' % (
                    self.authorized_keys_fname, hostname, self.authorized_keys_fname,
                    self.authorized_keys_fname)
        (status, output) = subprocess.getstatusoutput(cmd)
        if status != 0:
            raise Exception(ErrorCode.GAUSS_502["GAUSS_50223"] %"the authentication"
                            + "cmd is %s; Node:%s. Error:\n%s" % (cmd, hostname, output))

    def synchronizationLicenseFile(self):
        '''
        function: Distribution of documents through concurrent execution ThreadPool.
        input : NA
        output: NA
        '''
        self._log("Distributing SSH trust file to all node.", "addStep")
        try:
            parallelTool.parallelExecute(self.sendTrustFile, self.hostList)
            self.logger.log("Distributing trust keys file to all node successfully.")
            # send protect file to remote
            parallelTool.parallelExecute(self.send_protect_file, self.hostList)
        except Exception as e:
            self.logger.logExit(str(e))
        self._log("Successfully distributed SSH trust file to all node.", "constant")

    def verifyTrust(self):
        """
        function: Verify creating SSH trust is successful
        input : NA
        output: NA
        """
        self._log("Verifying SSH trust on all hosts.", "addStep")
        try:
            results = parallelTool.parallelExecute(self.checkAuthentication, self.hostList)
            hostnames = ""
            for (key, value) in results:
                if not key:
                    hostnames = hostnames + ',' + value
            if hostnames != "":
                raise Exception(ErrorCode.GAUSS_511["GAUSS_51100"] % hostnames.lstrip(','))
        except Exception as e:
            self.logger.logExit(str(e))
        self._log("Successfully verified SSH trust on all hosts.", "constant")

    def getUserPasswd(self):
        """
        function: get user passwd from cache
        input: NA
        output: NA
        """
        user_passwd = []
        if sys.stdin.isatty():
            GaussLog.printMessage("Please enter password for current user[%s]." % self.user)
            user_passwd.append(getpass.getpass())
        else:
            user_passwd.append(sys.stdin.readline().strip('\n'))

        if not user_passwd:
            GaussLog.exitWithError(ErrorCode.GAUSS_502["GAUSS_50203"] % "Password")

        return user_passwd

    def send_protect_file(self, hostname):
        """
        function: Scp the protect files to hostname
        input : hostname
        output: NA
        """
        if (hostname == self.localHost or
                hostname in DefaultValue.get_local_ips(NetUtil.get_ip_version(hostname))):
            return

        bashrc_file = os.path.join(pwd.getpwuid(os.getuid()).pw_dir, ".bashrc")
        tmp_path = os.path.expanduser("~/gaussdb_tmp/ssh_protect/")
        protect_path = os.path.expanduser("~/gaussdb_tmp/ssh_protect/*")
        local_path = os.path.dirname(os.path.realpath(__file__))
        pssh_path = os.path.realpath(os.path.join(local_path, "./gspylib/pssh/bin/pssh"))
        #Creating a Remote Directory
        create_cmd = "source ~/.bashrc && %s -s -H %s 'mkdir -p %s'" \
                     %(pssh_path, hostname, tmp_path)
        (status, output) = subprocess.getstatusoutput(create_cmd)
        self.logger.debug("Creating a Remote Directory:%s" % create_cmd)
        if status != 0:
            raise Exception(
                ErrorCode.GAUSS_502["GAUSS_50206"] % tmp_path
                + "cmd is %s; Node:%s. Error:\n%s" % (create_cmd, hostname, output))
        self.logger.debug("Creating a remote directory [%s] successfully on node "
                        "[%s]." %(tmp_path, hostname))
        # scp ssh_protect to remote node
        cmd = 'source %s; scp -q -r -2' % bashrc_file
        cmd = '%s -o "BatchMode yes" -o ' % (cmd)
        cmd = '%s "NumberOfPasswordPrompts 0" %s' % (cmd, protect_path)
        cmd = '%s [%s]:%s' % (cmd, hostname, tmp_path)
        self.logger.debug("scp ssh_protect file cmd:%s" %cmd)
        (status, output) = subprocess.getstatusoutput(cmd)
        if status != 0:
            raise Exception(
                ErrorCode.GAUSS_502["GAUSS_50223"] % "the protect path"
                + "cmd is %s Node:%s. Error:\n%s" % (cmd, hostname, output))
        self.logger.debug("Send protect file successfully on node[%s]." % hostname)

    def get_secret(self, length=32):
        """
        function : random secret
        input : int
        output : string
        """
        types = string.ascii_letters + string.digits + string.punctuation
        while True:
            secret_word = ''.join(secrets.choice(types) for i in range(length))
            if (any(c.islower() for c in secret_word)
                    and any(c.isupper() for c in secret_word)
                    and any(c in string.punctuation for c in secret_word)
                    and sum(c.isdigit() for c in secret_word) >= 4):
                break
        illegal = ["`", "\"", "\'", "!", "}", "{", "[", "]", "-",
                   "\\", "!", "\n", "&", "$", "\n", "|", ";", "(", ")"]
        if secret_word and len(secret_word) == length:
            for word in secret_word:
                if word in illegal:
                    secret_word = secret_word.replace(word, "*")
            self.logger.debug("Generate secret word successfully.")
        else:
            self.logger.error("Generate secret word failed.")
            raise Exception(ErrorCode.GAUSS_511["GAUSS_51113"])
        return secret_word

    def encrypt_pass_phrase(self, secret_word):
        """
        function : encrypt passphrase
        input : secret word
        output : NA
        """
        ssh_protect_path = os.path.expanduser("~/gaussdb_tmp/ssh_protect")
        cipher_path = os.path.join(ssh_protect_path, "cipher")
        rand_path = os.path.join(ssh_protect_path, "rand")
        if not os.path.isdir(cipher_path) or not os.path.isdir(rand_path):
            FileUtil.createDirectory(cipher_path, True, DefaultValue.KEY_DIRECTORY_MODE)
            FileUtil.createDirectory(rand_path, True, DefaultValue.KEY_DIRECTORY_MODE)
            self.logger.debug("Create ssh_protect directory [%s] successfully." % ssh_protect_path)
        else:
            self.logger.debug("Exists ssh protect directory.")
        os_system_type = platform.machine()
        encrypt_dir_path = os.path.abspath(os.path.join(os.path.dirname(os.path.
                                                                        abspath(__file__)),
                                                        "gspylib",
                                                        "clib"))
        cmd = " cd %s && ./encrypt '%s' %s %s" % (encrypt_dir_path, secret_word,
                                                  cipher_path, rand_path)
        if os_system_type.find("x86") != -1:
            self.logger.debug("[X86]:encrypt_user[%s]pwd_to_file" % self.user)
            cmd = "export LD_LIBRARY_PATH=%s && %s" % (encrypt_dir_path, cmd)
        else:
            self.logger.debug("[NON-X86]:encrypt_user[%s]pwd_to_file" % self.user)
        status, output = subprocess.getstatusoutput(cmd)
        if status != 0:
            raise Exception("Failed to encrypt secret words, error:%s." % output)
        change_file_list = []
        for main_dir, dirs, file_name in os.walk(ssh_protect_path):
            for f in file_name:
                change_file_list.append(os.path.join(main_dir, f))
        if change_file_list:
            cmd = "chmod 600 %s" % " ".join(change_file_list)
            proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, preexec_fn=os.setsid)
            stdout, stderr = proc.communicate()
            if proc.returncode != 0:
                errmsg = "Failed to chmod user[%s]pwd file." % self.user
                self.logger.error("execute cmd:%s, error:%s" % (cmd, stderr))
                raise Exception("%s execute cmd:%s, error:%s" % (errmsg, cmd, stderr))
        self.logger.debug("Successfully to encrypt user[%s]pwd to file." % self.user)

    def retry_register_other_ssh_agent(self, retryTimes = 3, sleepTime = 2):
        """
        :param retryTimes:
        :param sleepTime:
        :return:
        """
        for retryTime in range(retryTimes):
            try:
                self.register_other_ssh_agent(self.user, self.hostList, self.passwd)
                break
            except Exception as err:
                self.logger.debug(
                    "Error: Failed to register other ssh-agent, "
                    "output is [%s] for %s times" % (str(err), str(retryTime)))
                if retryTime == retryTimes - 1:
                    if err:
                        self.logger.logExit("Error: Failed to register other ssh-agent,"
                                            "output is [%s]" % (str(err)))
                else:
                    time.sleep(sleepTime)

    def register_other_ssh_agent(self, user, ips, passwd):
        try:
            self.create_all_sessions(user, ips, passwd)
            bashrc_file = os.path.join(pwd.getpwuid(os.getuid()).pw_dir,
                                       ".bashrc")
            localDirPath = os.path.dirname(os.path.realpath(__file__))
            shell_file = os.path.join(localDirPath, "./local/ssh-agent.sh")
            for ip in ips:
                if (ip == self.localHost or
                        ip in DefaultValue.get_local_ips(NetUtil.get_ip_version(ip))):
                    continue
                session = self.get_ssh_session(ip)
                DefaultValue.register_remote_ssh_agent(session, ip, self.logger)
                # Mounting private keys to ssh-agent
                self.copy_shell_to_remote_node(shell_file, ip)
                self.logger.debug("Copy shell file[%s] to rmote node [%s]successfully."
                                %(shell_file, ip))
                new_shell_file = os.path.join(self.sshDir, "./ssh-agent.sh")
                DefaultValue.add_remot_ssh_id_rsa(session, self.secret_word, bashrc_file,
                                                  new_shell_file, self.logger)
                delete_shell_cmd = "rm -rf %s" % new_shell_file
                (env_msg, channel_read) = DefaultValue.ssh_exec_cmd(
                    session, delete_shell_cmd)
                if env_msg:
                    self.logger.error("Failed to delete [%s] on node[%s]"
                                      %(new_shell_file, ip))
                self.logger.debug("Successfully to delete temp shell file [%s]"
                                % new_shell_file)
                self.logger.debug("Ssh agent register successfully.")
        except Exception as ex:
            self.close_all_session()
            raise Exception(str(ex))
        finally:
            self.close_all_session()

    def init_sshtool(self):
        """
        create ssh tool object
        :return:
        """
        self.ssh_tool = SshTool('')

    def get_ssh_session(self, remote_ip):
        """
        :param remote_ip:
        :return:
        """
        return self.ssh_tool.get_ssh_session(remote_ip)

    def create_all_sessions(self, user, all_ips, passwd):
        """
        :param all_ips:
        :return:
        """
        # the hosts have diffirent password.
        if len(self.hosts_paswd_list) == len(all_ips):
            for ip, pswd in self.hosts_paswd_list:
                self.ssh_tool.create_all_sessions(user, [ip], [pswd])
        else:
            self.ssh_tool.create_all_sessions(user, all_ips, passwd)

    def copy_shell_to_remote_node(self, shell_file, hostname):
        # scp ssh_protect to remote node
        cmd = 'source ~/.bashrc;'
        cmd += ('scp -q -o "BatchMode yes" -o "NumberOfPasswordPrompts 0" ' + '%s %s:.ssh/' % (
                shell_file, hostname))
        (status, output) = subprocess.getstatusoutput(cmd)
        if status != 0:
            raise Exception(
                ErrorCode.GAUSS_502["GAUSS_50214"] % "shell file to remote node;"
                + "cmd is %s; Node:%s. Error:\n%s" % (cmd, hostname, output))

    def close_all_session(self):
        """
        :return:
        """
        return self.ssh_tool.close_all_session()

    def retry_create_public_private_keyfile(self, retryTimes=3, sleepTime=2):
        for retryTime in range(retryTimes):
            try:
                self.localID = self.createPublicPrivateKeyFile()
                break
            except Exception as err:
                self.logger.debug(
                    "Error: Failed to create public private keyfile, "
                    "output is [%s] for %s times" % (str(err), str(retryTime)))
                if retryTime == retryTimes - 1:
                    if err:
                        self.logger.logExit("Error: Failed to create public private keyfile,"
                                            "output is [%s]" % (str(err)))
                else:
                    time.sleep(sleepTime)

    def _log(self, content, action):
        """
        inner log
        action: addStep, constant
        :return:
        """
        if self.logFile != "" and not os.path.exists(tmp_files):
            self.logger.log(content, action)
        else:
            self.logger.log(content)

    def _debug(self, content, action):
        """
        inner debug
        action: addStep, constant
        :return:
        """
        if self.logFile != "" and not os.path.exists(tmp_files):
            self.logger.debug(content, action)
        else:
            self.logger.debug(content)

if __name__ == '__main__':
    # main function
    createTrust = None
    try:
        createTrust = GaussCreateTrust()
        createTrust.run()
    except Exception as e:
        if str(e).startswith("[GAUSS-"):
            GaussLog.exitWithError(str(e))
        else:
            GaussLog.exitWithError("[GAUSS-50100]:"+str(e))

    sys.exit(0)
