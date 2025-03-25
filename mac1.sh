#!/bin/bash
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# 确保 PATH 包含必要目录
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# 判断是否已为 root 用户，若是则不使用 sudo
if [ $(id -u) -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo -e "${YEL}*   检查 MDM - 跳过 MacOS MDM 自动设置   *${NC}"
echo -e "${RED}*             SKIPMDM.COM                *${NC}"
echo -e "${RED}*            Phoenix Team                *${NC}"
echo -e "${CYAN}*-------------------*---------------------*${NC}"
echo ""

# 列出 /Volumes 下的磁盘卷供选择
echo -e "${BLU}请选择目标磁盘卷：${NC}"
volumes=()
while IFS= read -r line; do
    volumes+=("$line")
done < <(ls /Volumes)

if [ ${#volumes[@]} -eq 0 ]; then
    echo -e "${RED}未找到任何磁盘卷。${NC}"
    exit 1
fi

PS3='请输入你的选择: '
select disk in "${volumes[@]}"; do
    if [[ -n "$disk" ]]; then
        TARGET_DISK="$disk"
        echo -e "${GRN}选择的磁盘: $TARGET_DISK${NC}"
        break
    else
        echo "无效选项，请重新选择。"
    fi
done

# 主菜单
PS3='请输入你的选择: '
options=("在恢复模式下绕过MDM" "重启")
select opt in "${options[@]}"; do
    case $opt in
    "在恢复模式下绕过MDM")
        echo -e "${GRN}在恢复模式下绕过MDM${NC}"
        
        # 如果存在数据分区，重命名
        if [ -d "/Volumes/${TARGET_DISK} - Data" ]; then
            $SUDO diskutil rename "${TARGET_DISK} - Data" "Data"
        fi
        
        echo -e "${GRN}创建新用户${NC}"
        echo -e "${BLU}按回车继续 (留空将使用默认用户)${NC}"
        
        # 读取用户全名
        echo -e "请输入用户全名 (默认: Apple)"
        read realName
        realName="${realName:=Apple}"
        
        echo -e "${BLU}请输入用户名 (不含空格, 默认: Apple)${NC}"
        read username
        username="${username:=Apple}"
        
        # 读取密码
        echo -e "${BLU}请输入密码 (默认: 1234)${NC}"
        read passw
        passw="${passw:=1234}"
        
        # 定义 dscl 的路径，并检测其是否存在
        dscl_path="/Volumes/Data/private/var/db/dslocal/nodes/Default"
        if [ ! -d "$dscl_path" ]; then
            echo -e "${RED}错误：目录 $dscl_path 不存在。退出。${NC}"
            exit 1
        fi
        
        echo -e "${GRN}正在创建用户...${NC}"
        
        $SUDO dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" || { echo -e "${RED}创建用户失败${NC}"; exit 1; }
        $SUDO dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
        $SUDO dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
        $SUDO dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "501"
        $SUDO dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
        
        $SUDO mkdir -p "/Volumes/Data/Users/$username"
        $SUDO dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
        $SUDO dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
        $SUDO dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username"
        
        # 修改 hosts 文件，屏蔽相关域名
        if [ -f "/Volumes/${TARGET_DISK}/etc/hosts" ]; then
            $SUDO sh -c "echo '0.0.0.0 deviceenrollment.apple.com' >> /Volumes/${TARGET_DISK}/etc/hosts"
            $SUDO sh -c "echo '0.0.0.0 mdmenrollment.apple.com' >> /Volumes/${TARGET_DISK}/etc/hosts"
            $SUDO sh -c "echo '0.0.0.0 iprofiles.apple.com' >> /Volumes/${TARGET_DISK}/etc/hosts"
            echo -e "${GRN}成功屏蔽相关主机${NC}"
        else
            echo -e "${RED}错误：/Volumes/${TARGET_DISK}/etc/hosts 不存在。${NC}"
        fi
        
        # 创建或删除指定文件
        $SUDO touch /Volumes/Data/private/var/db/.AppleSetupDone
        $SUDO rm -rf /Volumes/${TARGET_DISK}/var/db/ConfigurationProfiles/Settings/.cloudConfigHasActivationRecord
        $SUDO rm -rf /Volumes/${TARGET_DISK}/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordFound
        $SUDO touch /Volumes/${TARGET_DISK}/var/db/ConfigurationProfiles/Settings/.cloudConfigProfileInstalled
        $SUDO touch /Volumes/${TARGET_DISK}/var/db/ConfigurationProfiles/Settings/.cloudConfigRecordNotFound
        
        echo -e "${CYAN}------ 绕过MDM成功 ------${NC}"
        echo -e "${CYAN}------ 退出终端，重置Mac并享受使用！ ------${NC}"
        break
        ;;
    
    "重启")
        echo -e "${GRN}正在重启...${NC}"
        $SUDO reboot
        break
        ;;
    
    *) echo "无效选项 $REPLY" ;;
    esac
done
