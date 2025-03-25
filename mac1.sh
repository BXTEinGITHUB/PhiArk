#!/bin/bash
# 设置 PATH，确保在多磁盘或恢复模式下能找到sudo等命令
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo -e "${YEL}*   检查MDM - MacOS绕过工具            *${NC}"
echo -e "${RED}*         SKIPMDM.COM                  *${NC}"
echo -e "${RED}*         Phoenix Team                 *${NC}"
echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo ""

# 选择磁盘功能
echo -e "${GRN}请选择磁盘：${NC}"
echo -e "${YEL}当前可用磁盘列表：${NC}"
ls /Volumes
echo ""
read -p "请输入系统磁盘名称 (默认: Macintosh HD): " sysdisk
sysdisk=${sysdisk:-"Macintosh HD"}

read -p "请输入数据磁盘名称 (默认: Macintosh HD - Data): " datadisk
datadisk=${datadisk:-"Macintosh HD - Data"}

# 如果数据磁盘存在，则重命名为 Data
if [ -d "/Volumes/${datadisk}" ]; then
    sudo diskutil rename "${datadisk}" "Data"
fi

# 提供功能选项
PS3='请选择一个选项: '
options=("恢复模式自动绕过" "重启" "禁用通知 (SIP)" "禁用通知 (恢复)" "检查MDM注册")
select opt in "${options[@]}"; do
    case $opt in
    "恢复模式自动绕过")
        echo -e "${GRN}正在恢复模式下自动绕过MDM...${NC}"
        
        echo -e "${GRN}创建新用户${NC}"
        echo -e "${BLU}按回车继续，注意：留空将使用默认用户${NC}"
        
        # 读取用户信息
        read -p "请输入全名 (默认: Apple): " realName
        realName=${realName:-"Apple"}
        
        read -p "请输入用户名（不含空格） (默认: Apple): " username
        username=${username:-"Apple"}
        
        read -p "请输入密码 (默认: 1234): " passw
        passw=${passw:-"1234"}
        
        # 定义 dscl 路径并检查是否存在
        dscl_path='/Volumes/Data/private/var/db/dslocal/nodes/Default'
        if [ ! -d "$dscl_path" ]; then
            echo -e "${RED}错误: 目录 $dscl_path 不存在. 退出.${NC}"
            exit 1
        fi
        
        echo -e "${GRN}正在创建用户...${NC}"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" || { echo -e "${RED}创建用户失败${NC}"; exit 1; }
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
        
        sudo mkdir -p "/Volumes/Data/Users/$username"
        sudo dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
        sudo dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
        sudo dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username"
        
        # 修改 hosts 文件
        if [ -f "/Volumes/${sysdisk}/etc/hosts" ]; then
            sudo sh -c "echo '0.0.0.0 deviceenrollment.apple.com' >> /Volumes/${sysdisk}/etc/hosts"
            sudo sh -c "echo '0.0.0.0 mdmenrollment.apple.com' >> /Volumes/${sysdisk}/etc/hosts"
            sudo sh -c "echo '0.0.0.0 iprofiles.apple.com' >> /Volumes/${sysdisk}/etc/hosts"
            echo -e "${GRN}成功屏蔽主机地址${NC}"
        else
            echo -e "${RED}错误: /Volumes/${sysdisk}/etc/hosts 未找到.${NC}"
        fi
        
        # 创建/删除相关配置文件
        sudo touch /Volumes/Data/private/var/db/.AppleSetupDone
        sudo rm -rf "/Volumes/${sysdisk}/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
        sudo rm -rf "/Volumes/${sysdisk}/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
        sudo touch "/Volumes/${sysdisk}/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
        sudo touch "/Volumes/${sysdisk}/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"
        
        echo -e "${CYAN}------ 自动绕过完成 ------${NC}"
        echo -e "${CYAN}------ 请退出终端，重启Mac，并享用新系统！ ------${NC}"
        break
        ;;
    "重启")
        echo -e "${GRN}正在重启...${NC}"
        sudo reboot
        break
        ;;
    "禁用通知 (SIP)")
        echo -e "${RED}请输入密码以继续${NC}"
        sudo rm "/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
        sudo rm "/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
        sudo touch "/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
        sudo touch "/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"
        break
        ;;
    "禁用通知 (恢复)")
        sudo rm -rf "/Volumes/${sysdisk}/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord"
        sudo rm -rf "/Volumes/${sysdisk}/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound"
        sudo touch "/Volumes/${sysdisk}/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled"
        sudo touch "/Volumes/${sysdisk}/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound"
        break
        ;;
    "检查MDM注册")
        echo ""
        echo -e "${GRN}检查MDM注册（出现错误即为成功）${NC}"
        echo ""
        echo -e "${RED}请输入密码以继续${NC}"
        echo ""
        sudo profiles show -type enrollment
        break
        ;;
    *) echo -e "${RED}无效选项 $REPLY${NC}" ;;
    esac
done
